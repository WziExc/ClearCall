import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

import '../../models/friend.dart';
import '../../models/room.dart';
import '../../utils/constants.dart';
import 'signaling_service.dart';

/// Firebase Realtime Database 信令服务实现
///
/// 所有信令操作通过 Firebase RTDB 的 JSON 节点完成。
/// 使用 Firebase Anonymous Auth 进行匿名认证。
///
/// 数据路径映射（对齐 06-firebase-schema.md）：
/// - /rooms/{roomId}/          — 房间 + 信令
/// - /users/{uid}/             — 用户公开信息
/// - /calls/{targetUid}/       — 呼叫信令
/// - /friendRequests/{uid}/    — 好友申请
class FirebaseSignaling implements SignalingService {
  final Logger _log = Logger('FirebaseSignaling');

  /// Firebase Realtime Database 实例
  final FirebaseDatabase _db;

  /// 当前用户 Firebase Auth UID
  String? _authUid;

  /// 活跃的 Firebase 监听器订阅，用于取消订阅
  final Map<String, StreamSubscription> _subscriptions = {};

  FirebaseSignaling({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  /// 初始化 Firebase（必须在调用其他方法前执行）
  Future<void> initialize() async {
    _log.info('初始化 Firebase...');

    // 确保 Firebase 已初始化
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    // 匿名登录
    final auth = FirebaseAuth.instance;
    try {
      final userCredential = await auth.signInAnonymously();
      _authUid = userCredential.user?.uid;
      _log.info('Firebase 匿名登录成功: $_authUid');
    } catch (e) {
      _log.severe('Firebase 匿名登录失败', e);
      throw FirebaseException(
        plugin: 'clearcall',
        message: '匿名登录失败: $e',
      );
    }
  }

  /// 确保 Firebase 已初始化
  void _ensureInitialized() {
    if (_authUid == null) {
      throw StateError('FirebaseSignaling 尚未初始化，请先调用 initialize()');
    }
  }

  @override
  String get serviceName => 'Firebase';

  // ═══════════════════════════════════════════════════════════
  // 房间管理
  // ═══════════════════════════════════════════════════════════

  @override
  Future<String> createRoom(String userId) async {
    _ensureInitialized();

    final roomId = _generateRoomCode();
    const now = ServerValue.timestamp;

    try {
      await _db.ref('rooms/$roomId').set({
        'creator': userId,
        'createdAt': now,
        'status': 'waiting',
      });

      // 将创建者加入参与者列表
      await _db.ref('rooms/$roomId/participants/$userId').set({
        'joinedAt': now,
      });

      _log.info('房间创建成功: $roomId，创建者: $userId');
      return roomId;
    } catch (e) {
      _log.severe('创建房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> joinRoom(String roomId, String userId) async {
    _ensureInitialized();

    try {
      // 检查房间是否存在
      final snapshot = await _db.ref('rooms/$roomId').get();
      if (!snapshot.exists) {
        throw RoomNotFoundException(roomId);
      }

      final roomData = snapshot.value as Map<dynamic, dynamic>;
      final status = roomData['status'] as String?;

      if (status == 'closed') {
        throw RoomClosedException(roomId);
      }

      // 检查房间是否已满
      final participantsSnapshot =
          await _db.ref('rooms/$roomId/participants').get();
      final participants = participantsSnapshot.value as Map<dynamic, dynamic>?;

      if (participants != null && participants.length >= maxParticipants) {
        throw RoomFullException(roomId, maxParticipants);
      }

      // 加入房间
      await _db.ref('rooms/$roomId/participants/$userId').set({
        'joinedAt': ServerValue.timestamp,
      });

      // 更新房间状态为 active
      await _db.ref('rooms/$roomId/status').set('active');

      _log.info('加入房间成功: $roomId，用户: $userId');
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
  Future<void> leaveRoom(String roomId, String userId) async {
    _ensureInitialized();

    try {
      // 移除该参与者的信令数据
      await _db.ref('rooms/$roomId/participants/$userId').remove();

      // 检查是否还有参与者
      final participantsSnapshot =
          await _db.ref('rooms/$roomId/participants').get();

      if (!participantsSnapshot.exists ||
          (participantsSnapshot.value as Map?)!.isEmpty) {
        // 无参与者 → 关闭房间
        await _db.ref('rooms/$roomId/status').set('closed');
      }

      _log.info('离开房间: $roomId，用户: $userId');
    } catch (e) {
      _log.severe('离开房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> closeRoom(String roomId) async {
    _ensureInitialized();

    try {
      await _db.ref('rooms/$roomId/status').set('closed');
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
      final snapshot = await _db.ref('rooms/$roomId/participants').get();
      if (!snapshot.exists) return [];

      final participants = snapshot.value as Map<dynamic, dynamic>;
      return participants.keys.map((k) => k.toString()).toList();
    } catch (e) {
      _log.severe('获取房间参与者失败', e);
      return [];
    }
  }

  @override
  Future<bool> isRoomFull(String roomId) async {
    final participants = await getRoomParticipants(roomId);
    return participants.length >= maxParticipants;
  }

  @override
  Stream<RoomEvent> onRoomEvent(String roomId) {
    _ensureInitialized();

    final streamController = StreamController<RoomEvent>.broadcast();

    // 监听房间参与者变化
    _db.ref('rooms/$roomId/participants').onChildAdded.listen((event) {
      final userId = event.snapshot.key;
      if (userId != null && userId != _authUid) {
        streamController.add(RoomEvent(
          type: RoomEventType.participantJoined,
          userId: userId,
          timestamp: DateTime.now(),
        ));
      }
    });

    _db.ref('rooms/$roomId/participants').onChildRemoved.listen((event) {
      final userId = event.snapshot.key;
      if (userId != null) {
        streamController.add(RoomEvent(
          type: RoomEventType.participantLeft,
          userId: userId,
          timestamp: DateTime.now(),
        ));
      }
    });

    // 清理订阅
    streamController.onCancel = () {
      _log.info('取消房间事件监听: $roomId');
    };

    return streamController.stream;
  }

  // ═══════════════════════════════════════════════════════════
  // WebRTC 信令
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendOffer(
      String roomId, String userId, RTCSessionDescription offer) async {
    _ensureInitialized();

    try {
      await _db.ref('rooms/$roomId/participants/$userId/sdp').set({
        'type': offer.type,
        'sdp': offer.sdp,
      });
      _log.info('SDP Offer 发送: $roomId -> $userId');
    } catch (e) {
      _log.severe('发送 Offer 失败', e);
      rethrow;
    }
  }

  @override
  Future<void> sendAnswer(
      String roomId, String userId, RTCSessionDescription answer) async {
    _ensureInitialized();

    try {
      await _db.ref('rooms/$roomId/participants/$userId/sdp').set({
        'type': answer.type,
        'sdp': answer.sdp,
      });
      _log.info('SDP Answer 发送: $roomId -> $userId');
    } catch (e) {
      _log.severe('发送 Answer 失败', e);
      rethrow;
    }
  }

  @override
  Future<void> sendCandidate(
      String roomId, String userId, RTCIceCandidate candidate) async {
    _ensureInitialized();

    try {
      final index = DateTime.now().millisecondsSinceEpoch.toString();
      await _db
          .ref('rooms/$roomId/participants/$userId/candidates/$index')
          .set({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    } catch (e) {
      _log.severe('发送 ICE Candidate 失败', e);
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
      await _db.ref('friendRequests/$toUid/from/$fromUid').set({
        'nickname': nickname,
        'token': token,
        'timestamp': ServerValue.timestamp,
        'status': 'pending',
      });
      _log.info('好友申请发送: $fromUid -> $toUid');
    } catch (e) {
      _log.severe('发送好友申请失败', e);
      rethrow;
    }
  }

  @override
  Stream<FriendRequest> onFriendRequest(String userId) {
    _ensureInitialized();

    final streamController = StreamController<FriendRequest>.broadcast();

    _db.ref('friendRequests/$userId/from').onChildAdded.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        streamController.add(FriendRequest(
          fromUid: event.snapshot.key!,
          nickname: data['nickname']?.toString() ?? '未知',
          token: data['token']?.toString() ?? '',
          timestamp: _parseTimestamp(data['timestamp']) ?? DateTime.now(),
          status: data['status'] == 'accepted'
              ? FriendRequestStatus.accepted
              : data['status'] == 'rejected'
                  ? FriendRequestStatus.rejected
                  : FriendRequestStatus.pending,
        ));
      }
    });

    streamController.onCancel = () {
      _log.info('取消好友申请监听: $userId');
    };

    return streamController.stream;
  }

  @override
  Future<void> acceptFriendRequest(String fromUid, String toUid) async {
    _ensureInitialized();

    try {
      // 更新申请状态
      await _db.ref('friendRequests/$toUid/from/$fromUid/status').set('accepted');

      // 双向写入好友关系
      await _db.ref('users/$toUid/friends/$fromUid').set(true);
      await _db.ref('users/$fromUid/friends/$toUid').set(true);

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
      await _db.ref('friendRequests/$toUid/from/$fromUid/status').set('rejected');
      _log.info('好友申请已拒绝: $fromUid');
    } catch (e) {
      _log.severe('拒绝好友申请失败', e);
      rethrow;
    }
  }

  @override
  Future<void> removeFriend(String uid, String friendUid) async {
    _ensureInitialized();

    try {
      // 双向删除
      await _db.ref('users/$uid/friends/$friendUid').remove();
      await _db.ref('users/$friendUid/friends/$uid').remove();
      _log.info('好友已删除: $uid <-> $friendUid');
    } catch (e) {
      _log.severe('删除好友失败', e);
      rethrow;
    }
  }

  @override
  Future<List<Friend>> getFriends(String userId) async {
    _ensureInitialized();

    try {
      final snapshot = await _db.ref('users/$userId/friends').get();
      if (!snapshot.exists) return [];

      final friendsMap = snapshot.value as Map<dynamic, dynamic>;
      final friendUids = friendsMap.keys.map((k) => k.toString()).toList();

      // 批量获取好友的公开信息
      final friends = <Friend>[];
      for (final friendUid in friendUids) {
        final userSnapshot = await _db.ref('users/$friendUid').get();
        if (userSnapshot.exists) {
          final data = userSnapshot.value as Map<dynamic, dynamic>;
          friends.add(Friend(
            uid: friendUid,
            nickname: data['nickname']?.toString() ?? '未知',
            status: _parseOnlineStatus(data['status']?.toString()),
            lastSeen: _parseTimestamp(data['lastSeen']),
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
      await _db.ref('users/$userId').update({
        'status': status.name == 'inCall' ? 'in-call' : status.name,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (e) {
      _log.severe('设置在线状态失败', e);
      rethrow;
    }
  }

  @override
  Future<void> setDisconnectCleanup(String userId) async {
    _ensureInitialized();

    try {
      // 使用 Firebase onDisconnect 确保断线自动标记离线
      await _db.ref('users/$userId/status').onDisconnect().set('offline');
      await _db.ref('users/$userId/lastSeen').onDisconnect().set(ServerValue.timestamp);
    } catch (e) {
      _log.severe('设置 onDisconnect 失败', e);
      rethrow;
    }
  }

  @override
  Future<OnlineStatus> getUserStatus(String userId) async {
    _ensureInitialized();

    try {
      final snapshot = await _db.ref('users/$userId/status').get();
      if (!snapshot.exists) return OnlineStatus.offline;
      return _parseOnlineStatus(snapshot.value?.toString());
    } catch (e) {
      return OnlineStatus.offline;
    }
  }

  @override
  Stream<Map<String, OnlineStatus>> onFriendsStatusChange(
      List<String> friendUids) {
    _ensureInitialized();

    final streamController =
        StreamController<Map<String, OnlineStatus>>.broadcast();

    for (final uid in friendUids) {
      _db.ref('users/$uid/status').onValue.listen((event) {
        final status = _parseOnlineStatus(event.snapshot.value?.toString());
        streamController.add({uid: status});
      });
    }

    streamController.onCancel = () {
      _log.info('取消好友状态监听');
    };

    return streamController.stream;
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
      await _db.ref('calls/$toUid').set({
        'callerUid': fromUid,
        'callerName': callData['callerName'] ?? '未知',
        'callType': callData['callType'] ?? 'video',
        'timestamp': ServerValue.timestamp,
        'status': 'ringing',
      });
      _log.info('呼叫信令发送: $fromUid -> $toUid');
    } catch (e) {
      _log.severe('发送呼叫信令失败', e);
      rethrow;
    }
  }

  @override
  Future<void> sendCallAnswer(String fromUid, String toUid) async {
    _ensureInitialized();

    try {
      await _db.ref('calls/$toUid/status').set('answered');
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
      await _db.ref('calls/$toUid/status').set('rejected');
      _log.info('呼叫拒绝: $fromUid -> $toUid');
    } catch (e) {
      _log.severe('发送呼叫拒绝失败', e);
      rethrow;
    }
  }

  @override
  Stream<Map<String, dynamic>> onIncomingCall(String userId) {
    _ensureInitialized();

    final streamController =
        StreamController<Map<String, dynamic>>.broadcast();

    _db.ref('calls/$userId').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        streamController.add({
          'callerUid': data['callerUid']?.toString(),
          'callerName': data['callerName']?.toString(),
          'callType': data['callType']?.toString(),
          'status': data['status']?.toString(),
        });
      }
    });

    streamController.onCancel = () {
      _log.info('取消来电监听: $userId');
    };

    return streamController.stream;
  }

  @override
  Future<void> clearCallNode(String targetUid) async {
    _ensureInitialized();

    try {
      await _db.ref('calls/$targetUid').remove();
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
      await _db.ref('.info/connected').once();
      return true;
    } catch (e) {
      _log.warning('信令服务不可用: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════════

  /// 生成 6 位数字房间号
  static String _generateRoomCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// 解析 Firebase ServerValue.timestamp
  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
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

  /// 清理所有活跃订阅（dispose 时调用）
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _log.info('FirebaseSignaling 已清理');
  }
}

// ═══════════════════════════════════════════════════════════
// 自定义异常
// ═══════════════════════════════════════════════════════════

/// 房间不存在异常
class RoomNotFoundException implements Exception {
  final String roomId;
  const RoomNotFoundException(this.roomId);

  @override
  String toString() => '房间 $roomId 不存在或已过期';
}

/// 房间已关闭异常
class RoomClosedException implements Exception {
  final String roomId;
  const RoomClosedException(this.roomId);

  @override
  String toString() => '房间 $roomId 已关闭';
}

/// 房间已满异常
class RoomFullException implements Exception {
  final String roomId;
  final int maxParticipants;
  const RoomFullException(this.roomId, this.maxParticipants);

  @override
  String toString() => '房间已满（最多$maxParticipants人）';
}
