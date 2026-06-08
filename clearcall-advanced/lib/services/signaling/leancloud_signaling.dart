import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../models/friend.dart';
import '../../models/room.dart';
import '../../utils/constants.dart' as constants;
import 'signaling_service.dart';

/// Leancloud REST API 信令服务实现
///
/// 使用 Leancloud REST API 实现所有信令操作。
/// 由于 Leancloud 免费版不保证 LiveQuery 可靠性，实时更新通过轮询实现：
/// - 房间事件（SDP/ICE 交换）：每 2 秒轮询
/// - 呼来信令：每 3 秒轮询
/// - 好友申请：每 5 秒轮询
/// - 在线状态：每 10 秒轮询
///
/// 数据映射（对齐 08-leancloud-adapter.md）：
/// - Room Class        → 房间 + 信令数据
/// - UserProfile Class → 用户公开信息
/// - CallSignal Class  → 呼叫信令
/// - FriendReq Class   → 好友申请
class LeancloudSignaling implements SignalingService {
  final Logger _log = Logger('LeancloudSignaling');

  /// Leancloud App ID（在 Leancloud 控制台获取）
  final String _appId;

  /// Leancloud App Key（在 Leancloud 控制台获取）
  final String _appKey;

  /// Leancloud API 基础 URL
  final String _serverUrl;

  /// HTTP 客户端
  final http.Client _http;

  /// 匿名登录后的 sessionToken（用于认证 API 请求）
  String? _sessionToken;

  /// 当前用户的 Leancloud objectId
  String? _userId;

  /// ─── 房间轮询 ────────────────────────────────────
  /// 当前活跃的房间 ID
  String? _currentRoomId;

  /// 房间轮询定时器
  Timer? _roomPollTimer;

  /// 上次轮询时的房间信号快照（用于检测变化）
  Map<String, dynamic>? _lastRoomSignalState;

  /// ─── 呼叫轮询 ────────────────────────────────────
  Timer? _callPollTimer;
  String? _lastCallStatus;

  /// ─── 好友申请轮询 ─────────────────────────────────
  Timer? _friendRequestPollTimer;
  final Set<String> _seenFriendRequestIds = {};

  /// ─── 在线状态轮询 ────────────────────────────────
  Timer? _statusPollTimer;
  List<String> _friendUids = [];

  /// ─── 流控制器 ────────────────────────────────────
  StreamController<RoomEvent>? _roomEventController;
  StreamController<FriendRequest>? _friendRequestController;
  StreamController<Map<String, dynamic>>? _incomingCallController;
  StreamController<Map<String, OnlineStatus>>? _statusController;

  /// ─── ============================================
  /// 构造 & 初始化
  /// ─── ============================================

  LeancloudSignaling({
    String? appId,
    String? appKey,
    String? server,
    http.Client? httpClient,
  })  : _appId = appId ?? constants.leancloudAppId,
        _appKey = appKey ?? constants.leancloudAppKey,
        _serverUrl = (server ?? constants.leancloudServer)
            .replaceAll('TARGET_APP_ID', appId ?? constants.leancloudAppId),
        _http = httpClient ?? http.Client();

  /// 初始化 Leancloud（匿名登录）
  ///
  /// 在调用其他方法前必须先调用此方法。
  @override
  Future<void> initialize() async {
    _log.info('初始化 Leancloud 信令服务...');
    _log.info('Server: $_serverUrl');

    try {
      await _anonymousLogin();
      _log.info('Leancloud 匿名登录成功，userId: $_userId');
    } catch (e) {
      _log.severe('Leancloud 初始化失败', e);
      rethrow;
    }
  }

  /// 匿名登录获取 sessionToken
  Future<void> _anonymousLogin() async {
    final randomId = _generateRandomId(32);
    final body = jsonEncode({
      'authData': {
        'anonymous': {
          'id': randomId,
        },
      },
    });

    final response = await _http.post(
      Uri.parse('$_serverUrl/1.1/users'),
      headers: _baseHeaders,
      body: body,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _sessionToken = data['sessionToken'] as String?;
      _userId = data['objectId'] as String?;

      if (_sessionToken == null || _userId == null) {
        throw Exception('Leancloud 匿名登录返回数据不完整');
      }
    } else {
      throw Exception('Leancloud 匿名登录失败: ${response.statusCode} ${response.body}');
    }
  }

  @override
  String get serviceName => 'Leancloud';

  // ═══════════════════════════════════════════════════════════
  // 房间管理
  // ═══════════════════════════════════════════════════════════

  @override
  Future<String> createRoom(String appUserId) async {
    _ensureInitialized();

    final roomId = _generateRoomCode();
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final body = jsonEncode({
        'roomId': roomId,
        'creatorId': appUserId,
        'status': 'waiting',
        'participantIds': [appUserId],
        'signals': <String, dynamic>{},
        'createdAt': now,
        'updatedAt': now,
      });

      final response = await _http.post(
        Uri.parse('$_serverUrl/1.1/classes/Room'),
        headers: _authHeaders,
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log.info('房间创建成功: $roomId，创建者: $appUserId');
        return roomId;
      } else {
        throw Exception('创建房间失败: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      _log.severe('创建房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> joinRoom(String roomId, String appUserId) async {
    _ensureInitialized();

    try {
      // 查询房间
      final roomData = await _findRoom(roomId);
      if (roomData == null) {
        throw RoomNotFoundException(roomId);
      }

      final status = roomData['status'] as String?;
      if (status == 'closed') {
        throw RoomClosedException(roomId);
      }

      // 检查是否已满
      final participantIds =
          (roomData['participantIds'] as List<dynamic>?)?.cast<String>() ?? [];
      if (participantIds.length >= constants.maxParticipants) {
        throw RoomFullException(roomId, constants.maxParticipants);
      }

      // 添加参与者
      if (!participantIds.contains(appUserId)) {
        participantIds.add(appUserId);
      }

      final objectId = roomData['objectId'] as String;
      final now = DateTime.now().millisecondsSinceEpoch;

      final body = jsonEncode({
        'participantIds': participantIds,
        'status': 'active',
        'updatedAt': now,
      });

      final response = await _http.put(
        Uri.parse('$_serverUrl/1.1/classes/Room/$objectId'),
        headers: _authHeaders,
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log.info('加入房间成功: $roomId，用户: $appUserId');
      } else {
        throw Exception('加入房间失败: ${response.statusCode}');
      }
    } catch (e) {
      if (e is RoomNotFoundException ||
          e is RoomClosedException ||
          e is RoomFullException) {
        rethrow;
      }
      _log.severe('加入房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> leaveRoom(String roomId, String appUserId) async {
    _ensureInitialized();

    try {
      final roomData = await _findRoom(roomId);
      if (roomData == null) return;

      final objectId = roomData['objectId'] as String;
      final participantIds =
          (roomData['participantIds'] as List<dynamic>?)?.cast<String>() ?? [];

      // 移除该参与者及其信号
      participantIds.remove(appUserId);
      final signals =
          roomData['signals'] as Map<String, dynamic>? ?? {};
      final mutableSignals = Map<String, dynamic>.from(signals);
      mutableSignals.remove(appUserId);

      // 如果房间空了 → 关闭
      final newStatus = participantIds.isEmpty ? 'closed' : roomData['status'];
      final now = DateTime.now().millisecondsSinceEpoch;

      final body = jsonEncode({
        'participantIds': participantIds,
        'signals': mutableSignals,
        'status': newStatus,
        'updatedAt': now,
      });

      await _http.put(
        Uri.parse('$_serverUrl/1.1/classes/Room/$objectId'),
        headers: _authHeaders,
        body: body,
      );

      _log.info('离开房间: $roomId，用户: $appUserId');
    } catch (e) {
      _log.severe('离开房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> closeRoom(String roomId) async {
    _ensureInitialized();

    try {
      final roomData = await _findRoom(roomId);
      if (roomData == null) return;

      final objectId = roomData['objectId'] as String;
      final now = DateTime.now().millisecondsSinceEpoch;

      await _http.put(
        Uri.parse('$_serverUrl/1.1/classes/Room/$objectId'),
        headers: _authHeaders,
        body: jsonEncode({
          'status': 'closed',
          'updatedAt': now,
        }),
      );

      _log.info('房间已关闭: $roomId');
    } catch (e) {
      _log.severe('关闭房间失败', e);
      rethrow;
    }
  }

  @override
  Future<List<String>> getRoomParticipants(String roomId) async {
    _ensureInitialized();

    try {
      final roomData = await _findRoom(roomId);
      if (roomData == null) return [];

      final participantIds =
          (roomData['participantIds'] as List<dynamic>?)?.cast<String>() ?? [];
      return participantIds;
    } catch (e) {
      _log.severe('获取房间参与者失败', e);
      return [];
    }
  }

  @override
  Future<bool> isRoomFull(String roomId) async {
    final participants = await getRoomParticipants(roomId);
    return participants.length >= constants.maxParticipants;
  }

  @override
  Stream<RoomEvent> onRoomEvent(String roomId) {
    _ensureInitialized();

    // 停止之前的房间轮询
    _stopRoomPolling();

    _currentRoomId = roomId;
    _lastRoomSignalState = null;

    _roomEventController = StreamController<RoomEvent>.broadcast(
      onCancel: () {
        _stopRoomPolling();
      },
    );

    // 启动轮询
    _startRoomPolling();

    return _roomEventController!.stream;
  }

  /// 启动房间轮询
  void _startRoomPolling() {
    _roomPollTimer = Timer.periodic(
      Duration(milliseconds: constants.leancloudRoomPollIntervalMs),
      (_) => _pollRoom(),
    );
    // 立即执行第一次轮询
    _pollRoom();
  }

  /// 停止房间轮询
  void _stopRoomPolling() {
    _roomPollTimer?.cancel();
    _roomPollTimer = null;
    _currentRoomId = null;
    _lastRoomSignalState = null;
  }

  /// 轮询房间状态
  Future<void> _pollRoom() async {
    if (_currentRoomId == null || _roomEventController == null) return;

    try {
      final roomData = await _findRoom(_currentRoomId!);
      if (roomData == null) {
        _emitRoomEvent(RoomEvent(
          type: RoomEventType.roomClosed,
          timestamp: DateTime.now(),
        ));
        return;
      }

      // 检查房间是否关闭
      final status = roomData['status'] as String?;
      if (status == 'closed') {
        _emitRoomEvent(RoomEvent(
          type: RoomEventType.roomClosed,
          timestamp: DateTime.now(),
        ));
        return;
      }

      // 检查参与者变化
      final currentParticipantIds =
          (roomData['participantIds'] as List<dynamic>?)?.cast<String>() ?? [];
      final lastParticipantIds = (_lastRoomSignalState?['participantIds']
              as List<dynamic>?)?.cast<String>() ??
          [];

      for (final pid in currentParticipantIds) {
        if (!lastParticipantIds.contains(pid) && pid != _userId) {
          _emitRoomEvent(RoomEvent(
            type: RoomEventType.participantJoined,
            userId: pid,
            timestamp: DateTime.now(),
          ));
        }
      }
      for (final pid in lastParticipantIds) {
        if (!currentParticipantIds.contains(pid) && pid != _userId) {
          _emitRoomEvent(RoomEvent(
            type: RoomEventType.participantLeft,
            userId: pid,
            timestamp: DateTime.now(),
          ));
        }
      }

      // 检查信号变化（SDP/ICE）
      final currentSignals =
          roomData['signals'] as Map<String, dynamic>? ?? {};
      final lastSignals =
          _lastRoomSignalState?['signals'] as Map<String, dynamic>? ?? {};

      for (final entry in currentSignals.entries) {
        final uid = entry.key;
        if (uid == _userId) continue; // 忽略自己的信号

        final signalData = entry.value as Map<String, dynamic>?;
        if (signalData == null) continue;

        final lastSignalData = lastSignals[uid] as Map<String, dynamic>?;

        // 检测新的 SDP
        final sdpType = signalData['sdpType'] as String?;
        final sdp = signalData['sdp'] as String?;
        final lastSdp = lastSignalData?['sdp'] as String?;

        if (sdp != null && sdp != lastSdp) {
          _emitRoomEvent(RoomEvent(
            type: sdpType == 'offer'
                ? RoomEventType.offerReceived
                : RoomEventType.answerReceived,
            userId: uid,
            sdp: {'type': sdpType, 'sdp': sdp},
            timestamp: DateTime.now(),
          ));
        }

        // 检测新的 ICE candidates
        final candidates = signalData['candidates'] as List<dynamic>? ?? [];
        final lastCandidates = lastSignalData?['candidates'] as List<dynamic>? ?? [];

        for (var i = lastCandidates.length; i < candidates.length; i++) {
          final candidate = candidates[i] as Map<String, dynamic>?;
          if (candidate != null) {
            _emitRoomEvent(RoomEvent(
              type: RoomEventType.iceCandidateReceived,
              userId: uid,
              candidate: candidate,
              timestamp: DateTime.now(),
            ));
          }
        }
      }

      // 更新快照
      _lastRoomSignalState = {
        'participantIds': currentParticipantIds,
        'signals': currentSignals,
      };
    } catch (e) {
      _log.warning('房间轮询失败: $e');
    }
  }

  void _emitRoomEvent(RoomEvent event) {
    if (!_roomEventController!.isClosed) {
      _roomEventController!.add(event);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // WebRTC 信令
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendOffer(
      String roomId, String userId, RTCSessionDescription offer) async {
    _ensureInitialized();
    await _updateRoomSignal(roomId, userId, offer.type, offer.sdp, null);
    _log.info('SDP Offer 发送: $roomId -> $userId');
  }

  @override
  Future<void> sendAnswer(
      String roomId, String userId, RTCSessionDescription answer) async {
    _ensureInitialized();
    await _updateRoomSignal(roomId, userId, answer.type, answer.sdp, null);
    _log.info('SDP Answer 发送: $roomId -> $userId');
  }

  @override
  Future<void> sendCandidate(
      String roomId, String userId, RTCIceCandidate candidate) async {
    _ensureInitialized();
    final candidateMap = {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    };
    await _updateRoomSignal(roomId, userId, null, null, candidateMap);
  }

  /// 更新房间中信令数据
  Future<void> _updateRoomSignal(
    String roomId,
    String userId,
    String? sdpType,
    String? sdp,
    Map<String, dynamic>? newCandidate,
  ) async {
    try {
      final roomData = await _findRoom(roomId);
      if (roomData == null) return;

      final objectId = roomData['objectId'] as String;
      final signals =
          Map<String, dynamic>.from(roomData['signals'] as Map<String, dynamic>? ?? {});

      var userSignal =
          Map<String, dynamic>.from(signals[userId] as Map<String, dynamic>? ?? {});

      if (sdpType != null && sdp != null) {
        userSignal['sdpType'] = sdpType;
        userSignal['sdp'] = sdp;
      }

      if (newCandidate != null) {
        final candidates =
            List<Map<String, dynamic>>.from(userSignal['candidates'] as List? ?? []);
        candidates.add(newCandidate);
        userSignal['candidates'] = candidates;
      }

      signals[userId] = userSignal;

      final now = DateTime.now().millisecondsSinceEpoch;
      await _http.put(
        Uri.parse('$_serverUrl/1.1/classes/Room/$objectId'),
        headers: _authHeaders,
        body: jsonEncode({
          'signals': signals,
          'updatedAt': now,
        }),
      );
    } catch (e) {
      _log.severe('更新房间信令失败', e);
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 好友系统
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendFriendRequest(
    String fromUid,
    String toUid,
    String nickname,
    String token,
  ) async {
    _ensureInitialized();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final body = jsonEncode({
        'fromUid': fromUid,
        'toUid': toUid,
        'nickname': nickname,
        'token': token,
        'status': 'pending',
        'timestamp': now,
      });

      final response = await _http.post(
        Uri.parse('$_serverUrl/1.1/classes/FriendReq'),
        headers: _authHeaders,
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log.info('好友申请发送: $fromUid -> $toUid');
      } else {
        throw Exception('发送好友申请失败: ${response.statusCode}');
      }
    } catch (e) {
      _log.severe('发送好友申请失败', e);
      rethrow;
    }
  }

  @override
  Stream<FriendRequest> onFriendRequest(String userId) {
    _ensureInitialized();

    _friendRequestController = StreamController<FriendRequest>.broadcast(
      onCancel: () {
        _stopFriendRequestPolling();
      },
    );

    _startFriendRequestPolling(userId);

    return _friendRequestController!.stream;
  }

  void _startFriendRequestPolling(String userId) {
    _friendRequestPollTimer = Timer.periodic(
      Duration(milliseconds: constants.leancloudFriendPollIntervalMs),
      (_) => _pollFriendRequests(userId),
    );
    // 立即执行第一次
    _pollFriendRequests(userId);
  }

  void _stopFriendRequestPolling() {
    _friendRequestPollTimer?.cancel();
    _friendRequestPollTimer = null;
  }

  Future<void> _pollFriendRequests(String userId) async {
    if (_friendRequestController == null) return;

    try {
      final encodedWhere = Uri.encodeComponent(
        jsonEncode({'toUid': userId, 'status': 'pending'}),
      );
      final response = await _http.get(
        Uri.parse('$_serverUrl/1.1/classes/FriendReq?where=$encodedWhere'),
        headers: _authHeaders,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];

        for (final item in results) {
          final req = item as Map<String, dynamic>;
          final objectId = req['objectId'] as String? ?? '';

          // 跳过已处理过的
          if (_seenFriendRequestIds.contains(objectId)) continue;
          _seenFriendRequestIds.add(objectId);

          if (!_friendRequestController!.isClosed) {
            _friendRequestController!.add(FriendRequest(
              fromUid: req['fromUid']?.toString() ?? '',
              nickname: req['nickname']?.toString() ?? '未知',
              token: req['token']?.toString() ?? '',
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                (req['timestamp'] as num?)?.toInt() ?? 0,
              ),
              status: FriendRequestStatus.pending,
            ));
          }
        }
      }
    } catch (e) {
      _log.warning('轮询好友申请失败: $e');
    }
  }

  @override
  Future<void> acceptFriendRequest(String fromUid, String toUid) async {
    _ensureInitialized();

    try {
      // 1. 更新好友申请状态
      await _updateFriendRequestStatus(fromUid, toUid, 'accepted');

      // 2. 双向添加好友关系
      await _addFriendRelation(toUid, fromUid);
      await _addFriendRelation(fromUid, toUid);

      _log.info('好友申请已接受: $fromUid <-> $toUid');
    } catch (e) {
      _log.severe('接受好友申请失败', e);
      rethrow;
    }
  }

  @override
  Future<void> rejectFriendRequest(String fromUid, String toUid) async {
    _ensureInitialized();

    try {
      await _updateFriendRequestStatus(fromUid, toUid, 'rejected');
      _log.info('好友申请已拒绝: $fromUid');
    } catch (e) {
      _log.severe('拒绝好友申请失败', e);
      rethrow;
    }
  }

  Future<void> _updateFriendRequestStatus(
    String fromUid,
    String toUid,
    String status,
  ) async {
    final encodedWhere = Uri.encodeComponent(
      jsonEncode({'fromUid': fromUid, 'toUid': toUid}),
    );
    final response = await _http.get(
      Uri.parse('$_serverUrl/1.1/classes/FriendReq?where=$encodedWhere'),
      headers: _authHeaders,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];

      if (results.isEmpty) return;

      final objectId = (results.first as Map<String, dynamic>)['objectId'] as String;
      await _http.put(
        Uri.parse('$_serverUrl/1.1/classes/FriendReq/$objectId'),
        headers: _authHeaders,
        body: jsonEncode({'status': status}),
      );
    }
  }

  Future<void> _addFriendRelation(String uid, String friendUid) async {
    // 查找或创建 UserProfile
    final profile = await _findOrCreateUserProfile(uid);
    if (profile == null) return;

    final friends =
        (profile['friends'] as List<dynamic>?)?.cast<String>() ?? [];
    if (!friends.contains(friendUid)) {
      friends.add(friendUid);
    }

    final objectId = profile['objectId'] as String;
    await _http.put(
      Uri.parse('$_serverUrl/1.1/classes/UserProfile/$objectId'),
      headers: _authHeaders,
      body: jsonEncode({'friends': friends}),
    );
  }

  @override
  Future<void> removeFriend(String uid, String friendUid) async {
    _ensureInitialized();

    try {
      // 双向删除
      await _removeFriendRelation(uid, friendUid);
      await _removeFriendRelation(friendUid, uid);
      _log.info('好友已删除: $uid <-> $friendUid');
    } catch (e) {
      _log.severe('删除好友失败', e);
      rethrow;
    }
  }

  Future<void> _removeFriendRelation(String uid, String friendUid) async {
    final profile = await _findUserProfile(uid);
    if (profile == null) return;

    final friends =
        (profile['friends'] as List<dynamic>?)?.cast<String>() ?? [];
    friends.remove(friendUid);

    final objectId = profile['objectId'] as String;
    await _http.put(
      Uri.parse('$_serverUrl/1.1/classes/UserProfile/$objectId'),
      headers: _authHeaders,
      body: jsonEncode({'friends': friends}),
    );
  }

  @override
  Future<List<Friend>> getFriends(String userId) async {
    _ensureInitialized();

    try {
      final profile = await _findOrCreateUserProfile(userId);
      if (profile == null) return [];

      final friendUids =
          (profile['friends'] as List<dynamic>?)?.cast<String>() ?? [];
      if (friendUids.isEmpty) return [];

      // 批量获取好友信息
      final friends = <Friend>[];
      for (final friendUid in friendUids) {
        final friendProfile = await _findUserProfile(friendUid);
        if (friendProfile != null) {
          friends.add(Friend(
            uid: friendUid,
            nickname: friendProfile['nickname']?.toString() ?? '未知',
            status: _parseOnlineStatus(
                friendProfile['status']?.toString()),
            lastSeen: _parseTimestamp(friendProfile['lastSeen']),
          ));
        }
      }

      return friends;
    } catch (e) {
      _log.severe('获取好友列表失败', e);
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 在线状态
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> setOnlineStatus(String userId, OnlineStatus status) async {
    _ensureInitialized();

    try {
      final profile = await _findOrCreateUserProfile(userId);
      if (profile == null) return;

      final objectId = profile['objectId'] as String;
      final now = DateTime.now().millisecondsSinceEpoch;

      final statusStr = status == OnlineStatus.inCall
          ? 'in-call'
          : status == OnlineStatus.online
              ? 'online'
              : 'offline';

      await _http.put(
        Uri.parse('$_serverUrl/1.1/classes/UserProfile/$objectId'),
        headers: _authHeaders,
        body: jsonEncode({
          'status': statusStr,
          'lastSeen': now,
        }),
      );
    } catch (e) {
      _log.severe('设置在线状态失败', e);
      rethrow;
    }
  }

  @override
  Future<void> setDisconnectCleanup(String userId) async {
    // Leancloud REST API 不支持 onDisconnect
    // 替代方案：通过轮询检测超时（5 分钟无心跳视为离线）
    // 心跳由 setOnlineStatus 每次调用时更新 lastSeen
    _log.info('Leancloud 不支持 onDisconnect，使用心跳超时替代');
  }

  @override
  Future<OnlineStatus> getUserStatus(String userId) async {
    _ensureInitialized();

    try {
      final profile = await _findUserProfile(userId);
      if (profile == null) return OnlineStatus.offline;

      // 检查心跳超时（5 分钟）
      final lastSeen = _parseTimestamp(profile['lastSeen']);
      if (lastSeen != null) {
        final elapsed = DateTime.now().difference(lastSeen);
        if (elapsed.inMinutes >= 5) {
          return OnlineStatus.offline;
        }
      }

      return _parseOnlineStatus(profile['status']?.toString());
    } catch (e) {
      return OnlineStatus.offline;
    }
  }

  @override
  Stream<Map<String, OnlineStatus>> onFriendsStatusChange(
      List<String> friendUids) {
    _ensureInitialized();

    _friendUids = friendUids;

    _statusController =
        StreamController<Map<String, OnlineStatus>>.broadcast(
      onCancel: () {
        _stopStatusPolling();
      },
    );

    _startStatusPolling();

    return _statusController!.stream;
  }

  void _startStatusPolling() {
    _statusPollTimer = Timer.periodic(
      Duration(milliseconds: constants.leancloudStatusPollIntervalMs),
      (_) => _pollFriendStatuses(),
    );
    // 立即执行第一次
    _pollFriendStatuses();
  }

  void _stopStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
  }

  Future<void> _pollFriendStatuses() async {
    if (_statusController == null || _statusController!.isClosed) return;

    try {
      final statusMap = <String, OnlineStatus>{};

      for (final uid in _friendUids) {
        // 检查心跳超时（5 分钟）
        final profile = await _findUserProfile(uid);
        if (profile != null) {
          final lastSeen = _parseTimestamp(profile['lastSeen']);
          if (lastSeen != null) {
            final elapsed = DateTime.now().difference(lastSeen);
            if (elapsed.inMinutes >= 5) {
              statusMap[uid] = OnlineStatus.offline;
              continue;
            }
          }
          statusMap[uid] =
              _parseOnlineStatus(profile['status']?.toString());
        } else {
          statusMap[uid] = OnlineStatus.offline;
        }
      }

      if (statusMap.isNotEmpty && !_statusController!.isClosed) {
        _statusController!.add(statusMap);
      }
    } catch (e) {
      _log.warning('轮询好友状态失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 呼叫信令
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendCallOffer(
    String fromUid,
    String toUid,
    Map<String, dynamic> callData,
  ) async {
    _ensureInitialized();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final body = jsonEncode({
        'callerUid': fromUid,
        'targetUid': toUid,
        'callerName': callData['callerName'] ?? '未知',
        'callType': callData['callType'] ?? 'video',
        'status': 'ringing',
        'timestamp': now,
      });

      final response = await _http.post(
        Uri.parse('$_serverUrl/1.1/classes/CallSignal'),
        headers: _authHeaders,
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log.info('呼叫信令发送: $fromUid -> $toUid');
      } else {
        throw Exception('发送呼叫信令失败: ${response.statusCode}');
      }
    } catch (e) {
      _log.severe('发送呼叫信令失败', e);
      rethrow;
    }
  }

  @override
  Future<void> sendCallAnswer(String fromUid, String toUid) async {
    _ensureInitialized();

    try {
      await _updateCallStatus(fromUid, toUid, 'answered');
      _log.info('呼叫应答: $fromUid -> $toUid');
    } catch (e) {
      _log.severe('发送呼叫应答失败', e);
      rethrow;
    }
  }

  @override
  Future<void> sendCallReject(String fromUid, String toUid) async {
    _ensureInitialized();

    try {
      await _updateCallStatus(fromUid, toUid, 'rejected');
      _log.info('呼叫拒绝: $fromUid -> $toUid');
    } catch (e) {
      _log.severe('发送呼叫拒绝失败', e);
      rethrow;
    }
  }

  Future<void> _updateCallStatus(
    String fromUid,
    String toUid,
    String status,
  ) async {
    final encodedWhere = Uri.encodeComponent(
      jsonEncode({
        'callerUid': fromUid,
        'targetUid': toUid,
        'status': 'ringing',
      }),
    );
    final response = await _http.get(
      Uri.parse('$_serverUrl/1.1/classes/CallSignal?where=$encodedWhere'),
      headers: _authHeaders,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];

      if (results.isEmpty) return;

      final objectId =
          (results.first as Map<String, dynamic>)['objectId'] as String;
      await _http.put(
        Uri.parse('$_serverUrl/1.1/classes/CallSignal/$objectId'),
        headers: _authHeaders,
        body: jsonEncode({'status': status}),
      );
    }
  }

  @override
  Stream<Map<String, dynamic>> onIncomingCall(String userId) {
    _ensureInitialized();

    _incomingCallController =
        StreamController<Map<String, dynamic>>.broadcast(
      onCancel: () {
        _stopCallPolling();
      },
    );

    _startCallPolling(userId);

    return _incomingCallController!.stream;
  }

  void _startCallPolling(String userId) {
    _callPollTimer = Timer.periodic(
      Duration(milliseconds: constants.leancloudCallPollIntervalMs),
      (_) => _pollIncomingCalls(userId),
    );
    // 立即执行第一次
    _pollIncomingCalls(userId);
  }

  void _stopCallPolling() {
    _callPollTimer?.cancel();
    _callPollTimer = null;
    _lastCallStatus = null;
  }

  Future<void> _pollIncomingCalls(String userId) async {
    if (_incomingCallController == null ||
        _incomingCallController!.isClosed) {
      return;
    }

    try {
      final encodedWhere = Uri.encodeComponent(
        jsonEncode({'targetUid': userId, 'status': 'ringing'}),
      );
      final response = await _http.get(
        Uri.parse(
            '$_serverUrl/1.1/classes/CallSignal?where=$encodedWhere'),
        headers: _authHeaders,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];

        if (results.isNotEmpty) {
          final call = results.first as Map<String, dynamic>;
          final currentStatus = call['status'] as String?;
          final callerUid = call['callerUid'] as String?;
          final callerName = call['callerName'] as String?;

          if (currentStatus == 'ringing' && _lastCallStatus != 'ringing') {
            // 新的来电
            if (!_incomingCallController!.isClosed) {
              _incomingCallController!.add({
                'callerUid': callerUid,
                'callerName': callerName,
                'callType': call['callType'],
                'status': currentStatus,
              });
            }
          } else if (currentStatus != _lastCallStatus) {
            // 状态变化
            if (!_incomingCallController!.isClosed) {
              _incomingCallController!.add({
                'status': currentStatus,
              });
            }
          }
          _lastCallStatus = currentStatus;
        } else {
          // 没有 ringing 状态的呼叫 → 可能是超时或已清理
          if (_lastCallStatus == 'ringing') {
            if (!_incomingCallController!.isClosed) {
              _incomingCallController!.add({
                'status': 'timeout',
              });
            }
          }
          _lastCallStatus = null;
        }
      }
    } catch (e) {
      _log.warning('轮询呼来信令失败: $e');
    }
  }

  @override
  Future<void> clearCallNode(String targetUid) async {
    _ensureInitialized();

    try {
      // 删除所有与该用户相关的呼叫信令
      final encodedWhere = Uri.encodeComponent(
        jsonEncode({'targetUid': targetUid}),
      );
      final response = await _http.get(
        Uri.parse(
            '$_serverUrl/1.1/classes/CallSignal?where=$encodedWhere'),
        headers: _authHeaders,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];

        for (final item in results) {
          final objectId =
              (item as Map<String, dynamic>)['objectId'] as String;
          await _http.delete(
            Uri.parse('$_serverUrl/1.1/classes/CallSignal/$objectId'),
            headers: _authHeaders,
          );
        }
      }
      _log.info('呼叫节点已清理: $targetUid');
    } catch (e) {
      _log.severe('清理呼叫节点失败', e);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 连接检测
  // ═══════════════════════════════════════════════════════════

  @override
  Future<bool> isAvailable() async {
    try {
      // 尝试 ping Leancloud API
      final response = await _http
          .get(
            Uri.parse('$_serverUrl/1.1/date'),
            headers: _baseHeaders,
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      _log.warning('Leancloud 服务不可用: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════════

  /// 基础 HTTP 头（无 sessionToken）
  Map<String, String> get _baseHeaders => {
        'X-LC-Id': _appId,
        'X-LC-Key': _appKey,
        'Content-Type': 'application/json',
      };

  /// 认证 HTTP 头（含 sessionToken）
  Map<String, String> get _authHeaders => {
        'X-LC-Id': _appId,
        'X-LC-Key': _appKey,
        'X-LC-Session': _sessionToken ?? '',
        'Content-Type': 'application/json',
      };

  void _ensureInitialized() {
    if (_sessionToken == null || _userId == null) {
      throw StateError(
          'LeancloudSignaling 尚未初始化，请先调用 initialize()');
    }
  }

  /// 通过 roomId 查询房间（返回含 objectId 的房间数据）
  Future<Map<String, dynamic>?> _findRoom(String roomId) async {
    final encodedWhere =
        Uri.encodeComponent(jsonEncode({'roomId': roomId}));
    final response = await _http.get(
      Uri.parse('$_serverUrl/1.1/classes/Room?where=$encodedWhere'),
      headers: _authHeaders,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isNotEmpty) {
        return results.first as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// 通过 uid 查找 UserProfile
  Future<Map<String, dynamic>?> _findUserProfile(String uid) async {
    final encodedWhere =
        Uri.encodeComponent(jsonEncode({'uid': uid}));
    final response = await _http.get(
      Uri.parse(
          '$_serverUrl/1.1/classes/UserProfile?where=$encodedWhere'),
      headers: _authHeaders,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isNotEmpty) {
        return results.first as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// 查找或创建 UserProfile
  Future<Map<String, dynamic>?> _findOrCreateUserProfile(
      String uid) async {
    var profile = await _findUserProfile(uid);
    if (profile != null) return profile;

    // 创建新的 UserProfile
    final now = DateTime.now().millisecondsSinceEpoch;
    final body = jsonEncode({
      'uid': uid,
      'nickname': 'User',
      'status': 'offline',
      'lastSeen': now,
      'friends': <String>[],
    });

    final response = await _http.post(
      Uri.parse('$_serverUrl/1.1/classes/UserProfile'),
      headers: _authHeaders,
      body: body,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 创建成功，重新查询以获取完整的 objectId
      return await _findUserProfile(uid);
    }
    return null;
  }

  /// 生成 6 位数字房间号
  static String _generateRoomCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// 生成随机十六进制 ID
  static String _generateRandomId(int length) {
    final random = Random.secure();
    return List.generate(
        length, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  /// 解析时间戳
  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  /// 解析在线状态字符串
  static OnlineStatus _parseOnlineStatus(String? status) {
    switch (status) {
      case 'online':
        return OnlineStatus.online;
      case 'in-call':
        return OnlineStatus.inCall;
      default:
        return OnlineStatus.offline;
    }
  }

  /// 清理所有资源
  void dispose() {
    _stopRoomPolling();
    _stopCallPolling();
    _stopFriendRequestPolling();
    _stopStatusPolling();
    _roomEventController?.close();
    _friendRequestController?.close();
    _incomingCallController?.close();
    _statusController?.close();
    _http.close();
    _log.info('LeancloudSignaling 已清理');
  }
}
