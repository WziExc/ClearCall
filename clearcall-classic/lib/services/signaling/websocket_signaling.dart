import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/friend.dart';
import '../../models/room.dart';
import '../../utils/constants.dart' as constants;
import 'signaling_service.dart';

/// WebSocket 信令服务实现
///
/// 连接到自建的 ClearCall 信令中继服务器，通过 WebSocket 进行实时消息转发。
///
/// 协议：
/// - REST API：POST /rooms 创建房间，GET /rooms/{id} 查询房间
/// - WebSocket：/ws 端点，JSON 消息中继
///
/// 优势：不依赖任何第三方 BaaS，自由部署，国内可用。
class WebSocketSignaling implements SignalingService {
  final Logger _log = Logger('WebSocketSignaling');

  /// 信令服务器 URL
  final String _serverUrl;

  /// HTTP 客户端（用于 REST API）
  final http.Client _http;

  /// WebSocket 连接
  WebSocketChannel? _wsChannel;

  /// 当前用户 ID
  String? _userId;

  /// ─── 房间轮询（从 WebSocket 消息驱动）────────────────
  String? _currentRoomId;
  StreamController<RoomEvent>? _roomEventController;

  /// ─── 流控制器 ────────────────────────────────────
  StreamController<FriendRequest>? _friendRequestController;
  StreamController<Map<String, dynamic>>? _incomingCallController;
  StreamController<Map<String, OnlineStatus>>? _statusController;
  StreamSubscription<dynamic>? _wsSubscription;

  /// ─── 好友系统缓存（本地内存，无持久化）──────────
  final Map<String, Friend> _friendsCache = {};

  /// ─── ============================================
  /// 构造 & 初始化
  /// ─── ============================================

  WebSocketSignaling({
    String? serverUrl,
    http.Client? httpClient,
  })  : _serverUrl = serverUrl ?? constants.signalingServerUrl,
        _http = httpClient ?? http.Client();

  @override
  String get serviceName => 'WebSocket 中继';

  @override
  Future<void> initialize() async {
    _userId = 'u${DateTime.now().millisecondsSinceEpoch}';
    _log.info('WebSocket 信令初始化完成，userId: $_userId');
  }

  /// 连接到服务器（加入房间时调用）
  Future<void> _connect(String roomId) async {
    if (_wsChannel != null) {
      _disconnect();
    }

    final wsUrl = _serverUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');

    _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _log.info('WebSocket 已连接: $wsUrl');

    // 发送 join 消息
    _sendWs({
      'type': 'join',
      'roomId': roomId,
      'from': _userId,
      'data': {},
    });

    // 监听服务器消息
    _wsSubscription = _wsChannel!.stream.listen(
      (raw) => _onWsMessage(raw as String),
      onDone: () {
        _log.info('WebSocket 连接已关闭');
      },
      onError: (e) {
        _log.warning('WebSocket 错误: $e');
      },
    );
  }

  /// 断开 WebSocket 连接
  void _disconnect() {
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    _wsSubscription = null;
  }

  void _sendWs(Map<String, dynamic> message) {
    final json = jsonEncode(message);
    try {
      _wsChannel?.sink.add(json);
    } catch (e) {
      _log.warning('WebSocket 发送失败: $e');
    }
  }

  void _onWsMessage(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final from = msg['from'] as String?;

      switch (type) {
        case 'joined':
          // 加入确认
          _log.info('已加入房间: ${msg['data']}');
          break;

        case 'join':
          // 其他人加入
          if (from != null && from != _userId) {
            _emitRoomEvent(RoomEvent(
              type: RoomEventType.participantJoined,
              userId: from,
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'leave':
          // 其他人离开
          if (from != null && from != _userId) {
            _emitRoomEvent(RoomEvent(
              type: RoomEventType.participantLeft,
              userId: from,
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'sdp':
          // SDP Offer/Answer
          if (from != null && from != _userId) {
            final data = msg['data'] as Map<String, dynamic>?;
            if (data != null) {
              _emitRoomEvent(RoomEvent(
                type: data['type'] == 'offer'
                    ? RoomEventType.offerReceived
                    : RoomEventType.answerReceived,
                userId: from,
                sdp: {'type': data['type'], 'sdp': data['sdp']},
                timestamp: DateTime.now(),
              ));
            }
          }
          break;

        case 'ice':
          // ICE Candidate
          if (from != null && from != _userId) {
            final data = msg['data'] as Map<String, dynamic>?;
            if (data != null) {
              _emitRoomEvent(RoomEvent(
                type: RoomEventType.iceCandidateReceived,
                userId: from,
                candidate: data,
                timestamp: DateTime.now(),
              ));
            }
          }
          break;

        case 'pong':
          break;

        case 'error':
          _log.warning('服务器错误: ${msg['data']}');
          break;
      }
    } catch (e) {
      _log.warning('WebSocket 消息解析失败: $e');
    }
  }

  void _emitRoomEvent(RoomEvent event) {
    if (_roomEventController != null && !_roomEventController!.isClosed) {
      _roomEventController!.add(event);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 房间管理
  // ═══════════════════════════════════════════════════════════

  @override
  Future<String> createRoom(String appUserId) async {
    try {
      final response = await _http.post(
        Uri.parse('${_serverUrl.replaceAll('/ws', '')}/rooms'),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final roomId = data['roomId'] as String;
        _log.info('房间创建: $roomId');
        return roomId;
      } else {
        throw Exception('创建房间失败: ${response.statusCode}');
      }
    } catch (e) {
      _log.severe('创建房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> joinRoom(String roomId, String appUserId) async {
    try {
      // 查询房间是否存在
      final response = await _http.get(
        Uri.parse('${_serverUrl.replaceAll('/ws', '')}/rooms/$roomId'),
      );

      if (response.statusCode == 404) {
        throw RoomNotFoundException(roomId);
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final count = data['participantCount'] as int? ?? 0;

        if (count >= constants.maxParticipants) {
          throw RoomFullException(roomId, constants.maxParticipants);
        }

        // 连接 WebSocket 并加入房间
        await _connect(roomId);
        _log.info('加入房间: $roomId');
      } else {
        throw Exception('查询房间失败: ${response.statusCode}');
      }
    } catch (e) {
      if (e is RoomNotFoundException ||
          e is RoomFullException) {
        rethrow;
      }
      _log.severe('加入房间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> leaveRoom(String roomId, String appUserId) async {
    _sendWs({'type': 'leave', 'from': _userId});
    _disconnect();
    _log.info('离开房间: $roomId');
  }

  @override
  Future<void> closeRoom(String roomId) async {
    _sendWs({'type': 'leave', 'from': _userId});
    _disconnect();
    _log.info('关闭房间: $roomId');
  }

  @override
  Future<List<String>> getRoomParticipants(String roomId) async {
    try {
      final response = await _http.get(
        Uri.parse('${_serverUrl.replaceAll('/ws', '')}/rooms/$roomId'),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final ids = data['participantIds'] as List<dynamic>? ?? [];
        return ids.cast<String>();
      }
      return [];
    } catch (e) {
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
    _currentRoomId = roomId;

    _roomEventController = StreamController<RoomEvent>.broadcast(
      onCancel: () {
        _disconnect();
      },
    );

    // 连接到房间
    _connect(roomId);

    return _roomEventController!.stream;
  }

  // ═══════════════════════════════════════════════════════════
  // WebRTC 信令
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendOffer(
      String roomId, String userId, RTCSessionDescription offer) async {
    _sendWs({
      'type': 'sdp',
      'from': _userId,
      'to': userId,
      'data': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  @override
  Future<void> sendAnswer(
      String roomId, String userId, RTCSessionDescription answer) async {
    _sendWs({
      'type': 'sdp',
      'from': _userId,
      'to': userId,
      'data': {'type': answer.type, 'sdp': answer.sdp},
    });
  }

  @override
  Future<void> sendCandidate(
      String roomId, String userId, RTCIceCandidate candidate) async {
    _sendWs({
      'type': 'ice',
      'from': _userId,
      'to': userId,
      'data': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 好友系统（WebSocket 中继不支持持久化好友关系）
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendFriendRequest(
    String fromUid,
    String toUid,
    String nickname,
    String token,
  ) async {
    _log.info('WebSocket 模式下不支持好友申请，请使用扫码添加');
  }

  @override
  Stream<FriendRequest> onFriendRequest(String userId) {
    _friendRequestController ??=
        StreamController<FriendRequest>.broadcast();
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
    return _friendsCache.values.toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 在线状态（WebSocket 中继不支持）
  // ═══════════════════════════════════════════════════════════

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
    _statusController ??=
        StreamController<Map<String, OnlineStatus>>.broadcast();
    return _statusController!.stream;
  }

  // ═══════════════════════════════════════════════════════════
  // 呼叫信令（WebSocket 中继不支持点对点呼叫）
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendCallOffer(
    String fromUid,
    String toUid,
    Map<String, dynamic> callData,
  ) async {
    _log.info('WebSocket 模式下不支持好友呼叫');
  }

  @override
  Future<void> sendCallAnswer(String fromUid, String toUid) async {}

  @override
  Future<void> sendCallReject(String fromUid, String toUid) async {}

  @override
  Stream<Map<String, dynamic>> onIncomingCall(String userId) {
    _incomingCallController ??=
        StreamController<Map<String, dynamic>>.broadcast();
    return _incomingCallController!.stream;
  }

  @override
  Future<void> clearCallNode(String targetUid) async {}

  // ═══════════════════════════════════════════════════════════
  // 连接检测
  // ═══════════════════════════════════════════════════════════

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _http
          .get(Uri.parse('${_serverUrl.replaceAll('/ws', '')}/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 清理资源
  void dispose() {
    _disconnect();
    _roomEventController?.close();
    _friendRequestController?.close();
    _incomingCallController?.close();
    _statusController?.close();
    _http.close();
    _log.info('WebSocketSignaling 已清理');
  }
}
