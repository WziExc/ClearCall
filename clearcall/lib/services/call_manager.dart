import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

import '../models/room.dart';
import '../utils/constants.dart';
import 'signaling/signaling_service.dart';
import 'webrtc_service.dart';

/// 通话状态
enum CallState {
  /// 空闲（无通话）
  idle,

  /// 等待连接（创建或加入房间后，等待他人）
  waiting,

  /// 呼叫中（等待对方接听）
  ringing,

  /// 通话中
  inCall,

  /// 已结束
  ended,
}

/// 通话参与者信息
class CallParticipant {
  /// 用户 ID
  final String uid;

  /// 昵称
  final String? nickname;

  /// 远端视频渲染器
  final RTCVideoRenderer? remoteRenderer;

  /// ICE 连接状态
  String iceConnectionState;

  /// 是否连接成功
  bool get isConnected => iceConnectionState == 'connected';

  CallParticipant({
    required this.uid,
    this.nickname,
    this.remoteRenderer,
    this.iceConnectionState = 'new',
  });
}

/// 通话结束报告
class CallEndReport {
  /// 通话对象名称
  final String targetName;

  /// 通话时长（秒）
  final int durationSeconds;

  /// 平均往返延迟（ms）
  final int avgRtt;

  /// 质量评级（优秀/一般/差）
  final String qualityRating;

  /// 估计流量消耗（MB）
  final double estimatedTrafficMB;

  /// 优化建议
  final List<String> suggestions;

  const CallEndReport({
    required this.targetName,
    required this.durationSeconds,
    this.avgRtt = 0,
    this.qualityRating = '未知',
    this.estimatedTrafficMB = 0,
    this.suggestions = const [],
  });
}

/// 通话管理器
///
/// 管理整个通话生命周期，协调 SignalingService 和 WebRTCService。
/// 状态转换：
/// ```
/// idle → waiting（创建/加入房间）
/// idle → ringing（发起好友呼叫）
/// idle → ringing（收到来电）
/// waiting → inCall（有参与者加入/连接建立）
/// ringing → inCall（对方接听/本地接听）
/// inCall → ended（挂断/超时/对方离开）
/// waiting → ended（超时/取消）
/// ringing → ended（超时/拒绝/取消）
/// ```
class CallManager {
  final Logger _log = Logger('CallManager');

  /// 信令服务
  final SignalingService _signaling;

  /// WebRTC 服务
  final WebRTCService _webrtc;

  /// 当前用户 ID
  final String _localUid;

  /// 当前通话状态
  CallState _state = CallState.idle;

  /// 当前房间 ID（如果是房间通话）
  String? _roomId;

  /// 通话时长计时器
  Timer? _durationTimer;

  /// 当前通话时长（秒）
  int _elapsedSeconds = 0;

  /// 参与者列表
  final Map<String, CallParticipant> _participants = {};

  /// 房间超时定时器（5 分钟无响应自动关闭）
  Timer? _roomTimeoutTimer;

  /// 呼叫超时定时器（60 秒无人接听）
  Timer? _callTimeoutTimer;

  /// 状态变化回调
  void Function(CallState newState)? onStateChanged;

  /// 参与者变化回调
  void Function(List<CallParticipant> participants)? onParticipantsChanged;

  /// 通话时长变化回调（每秒更新）
  void Function(int elapsedSeconds)? onDurationTick;

  /// 通话结束回调
  void Function(CallEndReport report)? onCallEnded;

  /// 收到来电回调
  void Function(
      String callerUid, String callerName, String callType)? onIncomingCall;

  CallManager({
    required SignalingService signaling,
    required WebRTCService webrtc,
    required String localUid,
  })  : _signaling = signaling,
        _webrtc = webrtc,
        _localUid = localUid;

  // ═══════════════════════════════════════════════════════════
  // 公共属性
  // ═══════════════════════════════════════════════════════════

  CallState get state => _state;
  String? get roomId => _roomId;
  int get elapsedSeconds => _elapsedSeconds;
  List<CallParticipant> get participants => _participants.values.toList();
  bool get isInCall => _state == CallState.inCall;
  int get participantCount => _participants.length;

  // ═══════════════════════════════════════════════════════════
  // 房间通话：创建房间
  // ═══════════════════════════════════════════════════════════

  /// 创建新房间并等待他人加入
  Future<String> createRoom() async {
    if (_state != CallState.idle) {
      throw StateError('当前已在通话中，无法创建新房间');
    }

    try {
      _setState(CallState.waiting);

      // 创建房间
      _roomId = await _signaling.createRoom(_localUid);
      _log.info('创建房间: $_roomId');

      // 初始化 WebRTC
      await _webrtc.getLocalStream();
      await _webrtc.initLocalRenderer();
      _webrtc.attachLocalStream();

      // 设置房间超时（5 分钟）
      _startRoomTimeout();

      // 监听房间事件
      _signaling.onRoomEvent(_roomId!).listen(_handleRoomEvent);

      return _roomId!;
    } catch (e) {
      _setState(CallState.idle);
      _roomId = null;
      _log.severe('创建房间失败', e);
      rethrow;
    }
  }

  /// 加入已有房间
  Future<void> joinRoom(String roomCode) async {
    if (_state != CallState.idle) {
      throw StateError('当前已在通话中，无法加入新房间');
    }

    try {
      _setState(CallState.waiting);

      // 加入房间（可能抛出 RoomFullException / RoomNotFoundException）
      await _signaling.joinRoom(roomCode, _localUid);
      _roomId = roomCode;
      _log.info('加入房间: $roomCode');

      // 初始化 WebRTC
      await _webrtc.getLocalStream();
      await _webrtc.initLocalRenderer();
      _webrtc.attachLocalStream();

      // 监听房间事件
      _signaling.onRoomEvent(roomCode).listen(_handleRoomEvent);

      // 搜索已有参与者的 Offer
      _waitForExistingOffer(roomCode);
    } catch (e) {
      _setState(CallState.idle);
      _roomId = null;
      _log.severe('加入房间失败', e);
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 好友呼叫
  // ═══════════════════════════════════════════════════════════

  /// 发起好友呼叫
  Future<void> startFriendCall(String targetUid, String targetName) async {
    if (_state != CallState.idle) {
      throw StateError('当前已在通话中');
    }

    try {
      _setState(CallState.ringing);

      // 发送呼叫信令
      await _signaling.sendCallOffer(
        _localUid,
        targetUid,
        {
          'callerName': targetName,
          'callType': 'video',
        },
      );

      // 初始化 WebRTC
      await _webrtc.getLocalStream();
      await _webrtc.initLocalRenderer();
      _webrtc.attachLocalStream();

      // 呼叫超时（60 秒）
      _startCallTimeout();

      // 监听对方响应
      _listenForCallResponse(targetUid);
    } catch (e) {
      _setState(CallState.idle);
      _log.severe('发起呼叫失败', e);
      rethrow;
    }
  }

  /// 接听来电
  Future<void> answerIncomingCall(String callerUid) async {
    if (_state != CallState.ringing) {
      throw StateError('没有来电');
    }

    try {
      await _signaling.sendCallAnswer(_localUid, callerUid);

      // 初始化 WebRTC
      await _webrtc.getLocalStream();
      await _webrtc.initLocalRenderer();
      _webrtc.attachLocalStream();

      // 创建 PeerConnection 并发送 Offer
      await _webrtc.initPeerConnection();
      _webrtc.setupPeerConnectionListeners(
        onIceCandidate: (candidate) {
          _signaling.sendCandidate('friend_call', callerUid, candidate);
        },
        onAddStream: (stream) {
          _log.info('收到来电远端流');
        },
        onRemoveStream: (stream) {
          _log.info('来电远端流移除');
        },
      );
      await _webrtc.addLocalStreamToPeer();

      final offer = await _webrtc.createOffer();
      await _signaling.sendOffer('friend_call', callerUid, offer);

      _startCall();
    } catch (e) {
      _hangUpInternal();
      _log.severe('接听来电失败', e);
      rethrow;
    }
  }

  /// 拒绝来电
  Future<void> rejectIncomingCall(String callerUid) async {
    try {
      await _signaling.sendCallReject(_localUid, callerUid);
      _setState(CallState.ended);
    } catch (e) {
      _log.severe('拒绝来电失败', e);
      rethrow;
    }
  }

  /// 取消发起的呼叫
  Future<void> cancelCall(String targetUid) async {
    try {
      await _signaling.clearCallNode(targetUid);
      _hangUpInternal();
    } catch (e) {
      _log.severe('取消呼叫失败', e);
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 挂断
  // ═══════════════════════════════════════════════════════════

  /// 挂断当前通话
  Future<void> hangUp() async {
    _log.info('挂断通话');

    // 如果是在房间中 → 离开房间
    if (_roomId != null) {
      try {
        await _signaling.leaveRoom(_roomId!, _localUid);
      } catch (e) {
        _log.warning('离开房间失败: $e');
      }
    }

    _hangUpInternal();
  }

  /// 内部挂断逻辑（释放资源 + 生成报告）
  void _hangUpInternal() {
    final duration = _elapsedSeconds;

    // 释放 WebRTC 资源
    _webrtc.hangUp();

    // 计算结束报告
    final report = _generateEndReport(duration);

    // 清理状态
    _stopDurationTimer();
    _cancelTimeouts();
    _participants.clear();
    _roomId = null;

    _setState(CallState.ended);

    // 触发结束回调
    onCallEnded?.call(report);
    _log.info('通话结束，时长: ${duration}s');
  }

  // ═══════════════════════════════════════════════════════════
  // 内部：房间事件处理
  // ═══════════════════════════════════════════════════════════

  void _handleRoomEvent(RoomEvent event) {
    _log.info('房间事件: ${event.type}, userId: ${event.userId}');

    switch (event.type) {
      case RoomEventType.participantJoined:
        _cancelRoomTimeout();
        _onParticipantJoined(event.userId!);

      case RoomEventType.participantLeft:
        _onParticipantLeft(event.userId!);

      case RoomEventType.roomClosed:
        _hangUpInternal();

      case RoomEventType.offerReceived:
        _onOfferReceived(event);

      case RoomEventType.answerReceived:
        _onAnswerReceived(event);

      case RoomEventType.iceCandidateReceived:
        _onIceCandidateReceived(event);
    }
  }

  /// 参与者加入
  Future<void> _onParticipantJoined(String userId) async {
    if (userId == _localUid) return;

    _log.info('参与者加入: $userId');

    // 3 人 Mesh 组网
    // 如果是第 2 个人 → 建立 1 对 1 连接
    // 如果是第 3 个人 → 建立 2 条新连接（与原先两人各建一条）

    try {
      // 创建 PeerConnection
      final targetUid = userId;
      await _webrtc.initPeerConnection();
      _webrtc.setupPeerConnectionListeners(
        onIceCandidate: (candidate) {
          _signaling.sendCandidate(_roomId!, targetUid, candidate);
        },
        onAddStream: (stream) {
          _log.info('收到远端流: ${stream.id}');
        },
        onRemoveStream: (stream) {
          _log.info('远端流移除: ${stream.id}');
        },
      );
      await _webrtc.addLocalStreamToPeer();

      // 创建并发送 SDP Offer
      final offer = await _webrtc.createOffer();
      await _signaling.sendOffer(_roomId!, userId, offer);

      // 添加参与者
      _participants[userId] = CallParticipant(uid: userId);
      onParticipantsChanged?.call(participants);

      if (_state == CallState.waiting) {
        _startCall();
      }
    } catch (e) {
      _log.severe('处理参与者加入失败', e);
    }
  }

  /// 参与者离开
  void _onParticipantLeft(String userId) {
    _log.info('参与者离开: $userId');
    _participants.remove(userId);
    _webrtc.removeRemoteRenderer(userId);
    onParticipantsChanged?.call(participants);

    // 如果没有其他参与者了 → 挂断
    final otherParticipants =
        _participants.values.where((p) => p.uid != _localUid).toList();
    if (otherParticipants.isEmpty && _state == CallState.inCall) {
      _log.info('所有参与者已离开，自动挂断');
      _hangUpInternal();
    }
  }

  /// 收到远端 Offer
  Future<void> _onOfferReceived(RoomEvent event) async {
    if (event.sdp == null || event.userId == null) return;

    _log.info('收到远端 Offer: ${event.userId}');

    try {
      // 创建 PeerConnection
      final targetUid = event.userId!;
      await _webrtc.initPeerConnection();
      _webrtc.setupPeerConnectionListeners(
        onIceCandidate: (candidate) {
          _signaling.sendCandidate(_roomId!, targetUid, candidate);
        },
        onAddStream: (stream) {
          _log.info('收到远端流: ${stream.id}');
        },
        onRemoveStream: (stream) {
          _log.info('远端流移除: ${stream.id}');
        },
      );
      await _webrtc.addLocalStreamToPeer();

      // 设置远端 Offer
      final desc = RTCSessionDescription(
        event.sdp!['sdp'] as String,
        event.sdp!['type'] as String,
      );
      await _webrtc.setRemoteDescription(desc);

      // 创建 Answer
      final answer = await _webrtc.createAnswer();
      await _signaling.sendAnswer(_roomId!, event.userId!, answer);

      // 添加参与者
      _participants[event.userId!] = CallParticipant(uid: event.userId!);
      onParticipantsChanged?.call(participants);

      if (_state == CallState.waiting) {
        _startCall();
      }
    } catch (e) {
      _log.severe('处理 Offer 失败', e);
    }
  }

  /// 收到远端 Answer
  Future<void> _onAnswerReceived(RoomEvent event) async {
    if (event.sdp == null) return;

    _log.info('收到远端 Answer');

    try {
      final desc = RTCSessionDescription(
        event.sdp!['sdp'] as String,
        event.sdp!['type'] as String,
      );
      await _webrtc.setRemoteDescription(desc);

      if (_state == CallState.waiting) {
        _startCall();
      }
    } catch (e) {
      _log.severe('处理 Answer 失败', e);
    }
  }

  /// 收到 ICE Candidate
  void _onIceCandidateReceived(RoomEvent event) {
    if (event.candidate == null) return;

    final candidate = RTCIceCandidate(
      event.candidate!['candidate'] as String,
      event.candidate!['sdpMid'] as String?,
      event.candidate!['sdpMLineIndex'] as int? ?? 0,
    );
    _webrtc.addCandidate(candidate);
  }

  /// 等待已有参与者的 Offer（加入已有房间时）
  void _waitForExistingOffer(String roomId) {
    // 监听参与者的 SDP 变化（已有参与者可能已经发送了 Offer）
    // 在实际实现中，需要监听 Firebase 的 participant 子节点 sdp 字段
    _log.info('等待已有参与者的 Offer...');
  }

  // ═══════════════════════════════════════════════════════════
  // 内部：好友呼叫响应监听
  // ═══════════════════════════════════════════════════════════

  void _listenForCallResponse(String targetUid) {
    _signaling.onIncomingCall(targetUid).listen((data) {
      final status = data['status'] as String?;
      switch (status) {
        case 'answered':
          _cancelCallTimeout();
          _startCall();
        case 'rejected':
          _cancelCallTimeout();
          _log.info('对方拒绝通话');
          _hangUpInternal();
        case 'timeout':
          _cancelCallTimeout();
          _log.info('呼叫超时');
          _hangUpInternal();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 内部：状态管理
  // ═══════════════════════════════════════════════════════════

  void _setState(CallState newState) {
    _state = newState;
    onStateChanged?.call(newState);
    _log.info('通话状态: ${newState.name}');
  }

  /// 通话正式开始
  void _startCall() {
    _setState(CallState.inCall);
    // 通话开始时间记录

    // 启动时长计时器（每秒更新）
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      onDurationTick?.call(_elapsedSeconds);
    });

    // 启动统计收集
    _webrtc.startStatsCollection();

    _log.info('通话开始');
  }

  /// 停止时长计时器
  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  // ═══════════════════════════════════════════════════════════
  // 内部：超时管理
  // ═══════════════════════════════════════════════════════════

  void _startRoomTimeout() {
    _roomTimeoutTimer = Timer(roomTimeout, () {
      if (_state == CallState.waiting) {
        _log.info('房间超时（5 分钟无响应），自动关闭');
        _hangUpInternal();
      }
    });
  }

  void _startCallTimeout() {
    _callTimeoutTimer = Timer(callTimeout, () {
      if (_state == CallState.ringing) {
        _log.info('呼叫超时（60 秒无应答）');
        _hangUpInternal();
      }
    });
  }

  void _cancelRoomTimeout() {
    _roomTimeoutTimer?.cancel();
    _roomTimeoutTimer = null;
  }

  void _cancelCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
  }

  void _cancelTimeouts() {
    _cancelRoomTimeout();
    _cancelCallTimeout();
  }

  // ═══════════════════════════════════════════════════════════
  // 结束报告
  // ═══════════════════════════════════════════════════════════

  CallEndReport _generateEndReport(int durationSeconds) {
    // 简单的质量评级
    String quality;
    List<String> suggestions = [];

    if (durationSeconds < 10) {
      quality = '未接通';
    } else {
      quality = '良好';
      suggestions.add('保持 Wi-Fi 连接可获得更稳定的画质');
    }

    // 估算流量（~1.5Mbps = 0.1875 MB/s × 秒数）
    final estimatedTraffic = durationSeconds * 0.1875;

    return CallEndReport(
      targetName: _roomId != null ? '房间#$_roomId' : '好友',
      durationSeconds: durationSeconds,
      qualityRating: quality,
      estimatedTrafficMB: estimatedTraffic,
      suggestions: suggestions,
    );
  }
}
