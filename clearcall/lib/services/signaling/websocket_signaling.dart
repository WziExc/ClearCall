import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:http/http.dart' as http;

import '../../models/friend.dart';
import '../../models/room.dart';
import '../../utils/constants.dart';
import 'signaling_service.dart';

/// WebSocket 信令中继适配器
///
/// 通过信令中继服务器（Render.com 免费部署）实现远程房间创建/加入。
/// 协议：REST API 房间管理 + WebSocket 实时消息转发。
///
/// 用户可在设置中切换 WebSocket 中继 / QR 扫码。
class WebSocketSignaling implements SignalingService {
  final Logger _log = Logger('WebSocketSignaling');

  final String _serverUrl;
  String? _userId;
  String? _currentRoomId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 5;
  static const _reconnectDelay = Duration(seconds: 3);

  /// 房间事件控制器
  StreamController<RoomEvent>? _roomEventController;

  /// 好友申请事件控制器
  StreamController<FriendRequest>? _friendRequestController;

  /// 来电控制器
  StreamController<Map<String, dynamic>>? _incomingCallController;

  /// 在线状态控制器
  StreamController<Map<String, OnlineStatus>>? _statusController;

  WebSocketSignaling({String? serverUrl})
      : _serverUrl = serverUrl ?? _defaultServerUrl;

  static const _defaultServerUrl = 'https://clearcall-signal.onrender.com';

  @override
  String get serviceName => 'WebSocket 中继';

  @override
  Future<void> initialize() async {
    _userId = 'ws_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    _log.info('WebSocket 信令初始化完成，userId: $_userId');
  }

  // ═══════════════════════════════════════════════════════════
  // 房间管理
  // ═══════════════════════════════════════════════════════════

  @override
  Future<String> createRoom(String appUserId) async {
    try {
      final uri = Uri.parse('$_serverUrl/rooms');
      final response = await http.post(uri);
      if (response.statusCode != 200) {
        throw Exception('创建房间失败: ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final roomId = data['roomId'] as String;
      _currentRoomId = roomId;
      _log.info('房间已创建: $roomId');
      return roomId;
    } catch (e) {
      _log.severe('创建房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> joinRoom(String roomId, String appUserId) async {
    try {
      // 检查房间是否存在
      final uri = Uri.parse('$_serverUrl/rooms/$roomId');
      final response = await http.get(uri);
      if (response.statusCode == 404) {
        throw RoomNotFoundException(roomId);
      }
      if (response.statusCode != 200) {
        throw Exception('查询房间失败: ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final count = data['participantCount'] as int? ?? 0;
      if (count >= maxParticipants) {
        throw RoomFullException(roomId, maxParticipants);
      }
      _currentRoomId = roomId;
      _log.info('加入房间: $roomId');
    } catch (e) {
      if (e is RoomNotFoundException || e is RoomFullException) rethrow;
      _log.severe('加入房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> leaveRoom(String roomId, String appUserId) async {
    _sendMessage({
      'type': 'leave',
      'roomId': roomId,
      'from': _userId,
    });
    _currentRoomId = null;
    _disconnect();
  }

  @override
  Future<void> closeRoom(String roomId) async {
    try {
      final uri = Uri.parse('$_serverUrl/rooms/$roomId');
      await http.delete(uri);
    } catch (_) {}
    _currentRoomId = null;
    _disconnect();
  }

  @override
  Future<List<String>> getRoomParticipants(String roomId) async {
    try {
      final uri = Uri.parse('$_serverUrl/rooms/$roomId');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final ids = data['participantIds'] as List<dynamic>? ?? [];
        return ids.cast<String>();
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<bool> isRoomFull(String roomId) async {
    final participants = await getRoomParticipants(roomId);
    return participants.length >= maxParticipants;
  }

  @override
  Stream<RoomEvent> onRoomEvent(String roomId) {
    _currentRoomId = roomId;
    _roomEventController = StreamController<RoomEvent>.broadcast();
    _connect(roomId);
    return _roomEventController!.stream;
  }

  // ═══════════════════════════════════════════════════════════
  // WebSocket 连接管理
  // ═══════════════════════════════════════════════════════════

  void _connect(String roomId) {
    try {
      final wsUrl = _serverUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      // 携带 room 和 uid 参数，兼容 CF Worker 路由
      final uri = Uri.parse('$wsUrl/ws?room=$roomId&uid=$_userId');

      _channel = WebSocketChannel.connect(uri);
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        (msg) => _onMessage(msg as String),
        onDone: () => _onDisconnected(roomId),
        onError: (e) {
          _log.warning('WebSocket 错误: $e');
          _onDisconnected(roomId);
        },
      );

      // 发送 join（Dart 服务器需要，CF Worker 也会处理）
      _sendMessage({
        'type': 'join',
        'roomId': roomId,
        'from': _userId,
        'data': {},
      });

      // 心跳（每 30 秒）
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _sendMessage({'type': 'ping', 'from': _userId});
      });

      _log.info('WebSocket 已连接: $wsUrl');
    } catch (e) {
      _log.severe('WebSocket 连接失败', e);
      _tryReconnect(roomId);
    }
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _onDisconnected(String roomId) {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    if (_currentRoomId != null) {
      _tryReconnect(roomId);
    }
  }

  void _tryReconnect(String roomId) {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _log.warning('重连次数已达上限');
      if (_roomEventController != null && !_roomEventController!.isClosed) {
        _roomEventController!.add(RoomEvent(
          type: RoomEventType.roomClosed,
          timestamp: DateTime.now(),
        ));
      }
      return;
    }
    _reconnectAttempts++;
    _log.info('尝试重连 ($_reconnectAttempts/$_maxReconnectAttempts)...');
    _reconnectTimer = Timer(_reconnectDelay, () => _connect(roomId));
  }

  // ═══════════════════════════════════════════════════════════
  // 消息处理
  // ═══════════════════════════════════════════════════════════

  void _onMessage(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final type = m['type'] as String?;
      final from = m['from'] as String?;
      final data = m['data'] as Map<String, dynamic>?;

      switch (type) {
        case 'joined':
          // 服务器确认加入
          _log.info('已加入房间，参与者: ${data?['participants']}');
          break;

        case 'join':
          // 其他参与者加入
          if (from != null && _roomEventController != null &&
              !_roomEventController!.isClosed) {
            _roomEventController!.add(RoomEvent(
              type: RoomEventType.participantJoined,
              userId: from,
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'leave':
          // 参与者离开
          if (from != null && _roomEventController != null &&
              !_roomEventController!.isClosed) {
            _roomEventController!.add(RoomEvent(
              type: RoomEventType.participantLeft,
              userId: from,
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'sdp':
          // 收到的 SDP
          final sdpData = data?['data'] as Map<String, dynamic>?;
          final sdpType = sdpData?['type'] as String?;
          if (from != null && sdpType != null && _roomEventController != null &&
              !_roomEventController!.isClosed) {
            final eventType = sdpType == 'offer'
                ? RoomEventType.offerReceived
                : RoomEventType.answerReceived;
            _roomEventController!.add(RoomEvent(
              type: eventType,
              userId: from,
              sdp: sdpData,
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'ice':
          // ICE Candidate
          final iceData = data?['data'] as Map<String, dynamic>?;
          if (iceData != null && _roomEventController != null &&
              !_roomEventController!.isClosed) {
            _roomEventController!.add(RoomEvent(
              type: RoomEventType.iceCandidateReceived,
              userId: from,
              candidate: iceData,
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'signal':
          // 通用信令消息
          final sigData = data?['data'] as Map<String, dynamic>?;
          if (sigData != null) {
            final sigType = sigData['type'] as String?;
            if (sigType == 'offer' && _roomEventController != null &&
                !_roomEventController!.isClosed) {
              _roomEventController!.add(RoomEvent(
                type: RoomEventType.offerReceived,
                userId: from,
                sdp: sigData,
                timestamp: DateTime.now(),
              ));
            } else if (sigType == 'answer' && _roomEventController != null &&
                !_roomEventController!.isClosed) {
              _roomEventController!.add(RoomEvent(
                type: RoomEventType.answerReceived,
                userId: from,
                sdp: sigData,
                timestamp: DateTime.now(),
              ));
            }
          }
          break;

        case 'error':
          _log.warning('服务器错误: ${data?['message']}');
          break;

        case 'pong':
          break;
      }
    } catch (e) {
      _log.fine('消息解析错误: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // WebRTC 信令（通过 WebSocket 发送）
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendOffer(
      String roomId, String userId, RTCSessionDescription offer) async {
    _sendMessage({
      'type': 'sdp',
      'roomId': roomId,
      'from': _userId,
      'to': userId,
      'data': {'type': 'offer', 'sdp': offer.sdp},
    });
  }

  @override
  Future<void> sendAnswer(
      String roomId, String userId, RTCSessionDescription answer) async {
    _sendMessage({
      'type': 'sdp',
      'roomId': roomId,
      'from': _userId,
      'to': userId,
      'data': {'type': 'answer', 'sdp': answer.sdp},
    });
  }

  @override
  Future<void> sendCandidate(
      String roomId, String userId, RTCIceCandidate candidate) async {
    _sendMessage({
      'type': 'ice',
      'roomId': roomId,
      'from': _userId,
      'to': userId,
      'data': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  void _sendMessage(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (e) {
      _log.warning('发送消息失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 好友系统（WebSocket 模式当前仅支持基础功能）
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendFriendRequest(
    String fromUid,
    String toUid,
    String nickname,
    String token,
  ) async {
    _log.info('WebSocket 模式暂不支持远程好友申请');
  }

  @override
  Stream<FriendRequest> onFriendRequest(String userId) {
    _friendRequestController = StreamController<FriendRequest>.broadcast();
    return _friendRequestController!.stream;
  }

  @override
  Future<void> acceptFriendRequest(String fromUid, String toUid) async {}

  @override
  Future<void> rejectFriendRequest(String fromUid, String toUid) async {}

  @override
  Future<void> removeFriend(String uid, String friendUid) async {}

  @override
  Future<List<Friend>> getFriends(String userId) async {
    return [];
  }

  @override
  Future<void> setOnlineStatus(String userId, OnlineStatus status) async {}

  @override
  Future<void> setDisconnectCleanup(String userId) async {}

  @override
  Future<OnlineStatus> getUserStatus(String userId) async {
    return OnlineStatus.offline;
  }

  @override
  Stream<Map<String, OnlineStatus>> onFriendsStatusChange(
      List<String> friendUids) {
    _statusController = StreamController<Map<String, OnlineStatus>>.broadcast();
    return _statusController!.stream;
  }

  @override
  Future<void> sendCallOffer(
    String fromUid,
    String toUid,
    Map<String, dynamic> callData,
  ) async {
    _log.info('WebSocket 模式暂不支持远程呼叫');
  }

  @override
  Future<void> sendCallAnswer(String fromUid, String toUid) async {}

  @override
  Future<void> sendCallReject(String fromUid, String toUid) async {}

  @override
  Stream<Map<String, dynamic>> onIncomingCall(String userId) {
    _incomingCallController =
        StreamController<Map<String, dynamic>>.broadcast();
    return _incomingCallController!.stream;
  }

  @override
  Future<void> clearCallNode(String targetUid) async {}

  @override
  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse('$_serverUrl/health');
      final response = await http.get(uri);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _disconnect();
    _roomEventController?.close();
    _friendRequestController?.close();
    _incomingCallController?.close();
    _statusController?.close();
  }
}
