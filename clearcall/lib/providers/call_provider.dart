import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_manager.dart';
import '../models/call_record.dart';
import '../services/call_history_db.dart';
import '../services/signaling/firebase_signaling.dart';
import '../services/webrtc_service.dart';
import '../utils/constants.dart';
import 'settings_provider.dart';
import 'signaling_provider.dart';

/// 通话状态 Provider
///
/// 持有 CallManager 实例，通过 Riverpod 暴露通话状态给 UI 层。
/// 所有 UI 通过此 Provider 观察和操作通话，不直接操作 CallManager。
final callProvider = StateNotifierProvider<CallNotifier, CallState2>(
  (ref) {
    final localId = ref.read(settingsProvider).localId;
    final signaling = ref.read(signalingProvider);

    final webrtc = WebRTCService(
      iceServers: WebRTCService.defaultIceServers,
    );

    final notifier = CallNotifier(
      signaling: signaling,
      webrtc: webrtc,
      localUid: localId,
    );

    // 初始化由 AppRoot._initializeServices() 统一控制时序
    return notifier;
  },
);

/// UI 层可见的通话状态
class CallState2 {
  /// 当前通话阶段
  final CallPhase phase;

  /// 当前房间号（房间通话时）
  final String? roomId;

  /// 参与者列表
  final List<CallParticipant> participants;

  /// 通话已过秒数
  final int elapsedSeconds;

  /// 是否正在加载（初始化中）
  final bool isLoading;

  /// 最后的错误信息
  final String? errorMessage;

  /// 通话结束报告（挂断后可用）
  final CallEndReport? endReport;

  /// 麦克风是否静音
  final bool isMuted;

  /// 摄像头是否开启
  final bool isCameraOn;

  /// 补光是否开启
  final bool isFlashOn;

  /// 是否为前置摄像头
  final bool isFrontCamera;

  /// 扬声器是否开启
  final bool isSpeakerOn;

  /// 摄像头权限是否被拒绝（降级为纯音频模式）
  final bool cameraPermissionDenied;

  /// 麦克风权限是否被拒绝
  final bool micPermissionDenied;

  /// 来电信息（好友呼叫时）
  final String? incomingCallerUid;
  final String? incomingCallerName;

  /// 当前是否为好友通话
  final bool isFriendCall;
  final String? friendCallTargetUid;

  const CallState2({
    this.phase = CallPhase.idle,
    this.roomId,
    this.participants = const [],
    this.elapsedSeconds = 0,
    this.isLoading = false,
    this.errorMessage,
    this.endReport,
    this.isMuted = false,
    this.isCameraOn = true,
    this.isFlashOn = false,
    this.isFrontCamera = true,
    this.isSpeakerOn = true,
    this.cameraPermissionDenied = false,
    this.micPermissionDenied = false,
    this.incomingCallerUid,
    this.incomingCallerName,
    this.isFriendCall = false,
    this.friendCallTargetUid,
  });

  CallState2 copyWith({
    CallPhase? phase,
    String? roomId,
    List<CallParticipant>? participants,
    int? elapsedSeconds,
    bool? isLoading,
    String? errorMessage,
    CallEndReport? endReport,
    bool? isMuted,
    bool? isCameraOn,
    bool? isFlashOn,
    bool? isFrontCamera,
    bool? isSpeakerOn,
    bool? cameraPermissionDenied,
    bool? micPermissionDenied,
    String? incomingCallerUid,
    String? incomingCallerName,
    bool? isFriendCall,
    String? friendCallTargetUid,
    bool clearError = false,
    bool clearReport = false,
    bool clearIncoming = false,
  }) {
    return CallState2(
      phase: phase ?? this.phase,
      roomId: roomId ?? this.roomId,
      participants: participants ?? this.participants,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      endReport: clearReport ? null : (endReport ?? this.endReport),
      isMuted: isMuted ?? this.isMuted,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isFlashOn: isFlashOn ?? this.isFlashOn,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      cameraPermissionDenied:
          cameraPermissionDenied ?? this.cameraPermissionDenied,
      micPermissionDenied:
          micPermissionDenied ?? this.micPermissionDenied,
      incomingCallerUid:
          clearIncoming ? null : (incomingCallerUid ?? this.incomingCallerUid),
      incomingCallerName:
          clearIncoming ? null : (incomingCallerName ?? this.incomingCallerName),
      isFriendCall: isFriendCall ?? this.isFriendCall,
      friendCallTargetUid: friendCallTargetUid ?? this.friendCallTargetUid,
    );
  }

  /// 格式化时长（如 "02:34"）
  String get formattedDuration {
    final mins = elapsedSeconds ~/ 60;
    final secs = elapsedSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 是否有来电
  bool get hasIncomingCall => incomingCallerUid != null;
}

/// 通话阶段（UI 驱动，比 CallManager.CallState 更细）
enum CallPhase {
  /// 空闲
  idle,

  /// 正在创建/加入房间（加载中）
  connecting,

  /// 等待他人加入（已创建房间，展示房间号/二维码）
  waiting,

  /// 呼叫中（好友呼叫 / 来电）
  ringing,

  /// 通话中
  inCall,

  /// 已结束（展示结束报告）
  ended,
}

/// 通话状态管理器
///
/// 封装 CallManager，通过 Riverpod 提供响应式状态。
/// 负责：
/// - 初始化 Firebase 和 WebRTC
/// - 将 CallManager 的回调转换为 state 更新
/// - 暴露简化的 API 给 UI
class CallNotifier extends StateNotifier<CallState2> {
  final FirebaseSignaling _signaling;
  final WebRTCService _webrtc;
  final String _localUid;

  /// 核心通话管理器
  late final CallManager _callManager;

  /// Firebase 是否已初始化
  bool _initialized = false;

  CallNotifier({
    required FirebaseSignaling signaling,
    required WebRTCService webrtc,
    required String localUid,
  })  : _signaling = signaling,
        _webrtc = webrtc,
        _localUid = localUid,
        super(const CallState2());

  /// 初始化 Firebase 和 CallManager
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      state = state.copyWith(isLoading: true);

      await _signaling.initialize();

      _callManager = CallManager(
        signaling: _signaling,
        webrtc: _webrtc,
        localUid: _localUid,
      );

      // 绑定 CallManager 回调 → state 更新
      _callManager.onStateChanged = (callState) {
        final phase = _mapCallState(callState);
        state = state.copyWith(phase: phase, errorMessage: null);

        if (callState == CallState.idle) {
          state = state.copyWith(
            roomId: null,
            friendCallTargetUid: null,
            isFriendCall: false,
          );
        }
      };

      _callManager.onParticipantsChanged = (participants) {
        state = state.copyWith(participants: participants);
      };

      _callManager.onDurationTick = (elapsed) {
        state = state.copyWith(elapsedSeconds: elapsed);
      };

      _callManager.onCallEnded = (report) {
        state = state.copyWith(
          phase: CallPhase.ended,
          endReport: report,
          roomId: null,
          participants: [],
          elapsedSeconds: 0,
          friendCallTargetUid: null,
          isFriendCall: false,
        );
        _saveCallRecord(report);
      };

      // 监听到来电 → 更新 state 通知 UI
      _callManager.onIncomingCall = (callerUid, callerName, callType) {
        if (state.phase == CallPhase.idle) {
          state = state.copyWith(
            phase: CallPhase.ringing,
            incomingCallerUid: callerUid,
            incomingCallerName: callerName,
            isFriendCall: true,
          );
        }
      };

      _initialized = true;
    } catch (e) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '初始化失败: $e',
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 获取 CallManager 实例（供 FriendNotifier 同步状态）
  CallManager? get callManager => _initialized ? _callManager : null;

  /// 创建新房间
  Future<void> createRoom() async {
    _ensureInitialized();

    try {
      state = state.copyWith(phase: CallPhase.connecting, errorMessage: null);

      final roomId = await _callManager.createRoom();

      state = state.copyWith(
        phase: CallPhase.waiting,
        roomId: roomId,
        isFriendCall: false,
        errorMessage: null,
      );
    } on StateError catch (e) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: e.toString(),
      );
    } catch (e) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '创建房间失败: $e',
      );
    }
  }

  /// 加入已有房间
  Future<void> joinRoom(String roomCode) async {
    _ensureInitialized();

    try {
      state = state.copyWith(phase: CallPhase.connecting, errorMessage: null);

      await _callManager.joinRoom(roomCode);

      state = state.copyWith(
        phase: CallPhase.waiting,
        roomId: roomCode,
        isFriendCall: false,
        errorMessage: null,
      );
    } on RoomNotFoundException catch (_) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '房间不存在或已过期',
      );
    } on RoomClosedException catch (_) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '房间已关闭',
      );
    } on RoomFullException catch (_) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '房间已满（最多$maxParticipants人）',
      );
    } on StateError catch (e) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: e.toString(),
      );
    } catch (e) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '加入房间失败: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 好友呼叫（3.11）
  // ═══════════════════════════════════════════════════════════

  /// 发起好友呼叫
  Future<void> startFriendCall(String targetUid, String targetName) async {
    _ensureInitialized();

    try {
      state = state.copyWith(phase: CallPhase.connecting, errorMessage: null);

      await _callManager.startFriendCall(targetUid, targetName);

      state = state.copyWith(
        phase: CallPhase.ringing,
        isFriendCall: true,
        friendCallTargetUid: targetUid,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '发起呼叫失败: $e',
        isFriendCall: false,
        friendCallTargetUid: null,
      );
    }
  }

  /// 接听来电
  Future<void> answerIncomingCall() async {
    _ensureInitialized();

    final callerUid = state.incomingCallerUid;
    if (callerUid == null) {
      state = state.copyWith(errorMessage: '没有来电');
      return;
    }

    try {
      await _callManager.answerIncomingCall(callerUid);

      // 清除来电信息，状态由 CallManager 回调更新
      state = state.copyWith(clearIncoming: true);
    } catch (e) {
      state = state.copyWith(
        errorMessage: '接听失败: $e',
        clearIncoming: true,
        phase: CallPhase.idle,
      );
    }
  }

  /// 拒绝来电
  Future<void> rejectIncomingCall() async {
    final callerUid = state.incomingCallerUid;
    if (callerUid == null) return;

    try {
      await _callManager.rejectIncomingCall(callerUid);
    } catch (_) {
      // 即使拒绝失败也清除来电状态
    }

    state = state.copyWith(
      phase: CallPhase.idle,
      clearIncoming: true,
      isFriendCall: false,
    );
  }

  /// 取消发起的呼叫
  Future<void> cancelFriendCall() async {
    final targetUid = state.friendCallTargetUid;
    if (targetUid == null) return;

    try {
      await _callManager.cancelCall(targetUid);
    } catch (_) {}

    state = state.copyWith(
      phase: CallPhase.idle,
      isFriendCall: false,
      friendCallTargetUid: null,
    );
  }

  /// 挂断通话
  Future<void> hangUp() async {
    _ensureInitialized();

    try {
      await _callManager.hangUp();
    } catch (_) {
      // hangUp 总是会触发 onCallEnded 回调
    }
  }

  /// 取消等待（房间创建后无人加入，主动退出）
  Future<void> cancelWaiting() async {
    await hangUp();
  }

  /// 关闭结束报告，回到 idle
  void dismissEndReport() {
    state = state.copyWith(
      phase: CallPhase.idle,
      clearReport: true,
      clearError: true,
    );
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// 当前是否在通话相关状态
  bool get isInCallOrWaiting =>
      state.phase == CallPhase.waiting ||
      state.phase == CallPhase.ringing ||
      state.phase == CallPhase.inCall;

  /// 保存通话记录到本地数据库
  void _saveCallRecord(CallEndReport report) {
    final now = DateTime.now();
    final record = CallRecord(
      targetId: state.friendCallTargetUid ?? state.roomId ?? _localUid,
      targetName: report.targetName,
      startTime: now.subtract(Duration(seconds: report.durationSeconds)),
      endTime: now,
      durationSeconds: report.durationSeconds,
      isFriendCall: state.isFriendCall,
      callType: 'video',
      direction: state.incomingCallerUid != null ? 'incoming' : 'outgoing',
      answered: report.durationSeconds > 0,
    );
    CallHistoryDB().insert(record);
  }

  /// 标记摄像头权限被拒绝
  void setCameraPermissionDenied() {
    state = state.copyWith(cameraPermissionDenied: true, isCameraOn: false);
  }

  /// 标记麦克风权限被拒绝
  void setMicPermissionDenied() {
    state = state.copyWith(micPermissionDenied: true, isMuted: true);
  }

  /// 应用媒体设置（通话中即时生效）
  ///
  /// 大部分设置需要下一次通话才完全生效（分辨率/帧率/编码），
  /// 音频处理开关（AEC/ANS/AGC）可即时生效。
  void applyMediaSettings(AppSettings settings) {
    // 音频处理开关可即时切换
    _webrtc.applyAudioProcessing(
      aec: settings.aecEnabled,
      ans: settings.ansEnabled,
      agc: settings.agcEnabled,
    );
  }

  /// 确保已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('通话服务尚未初始化');
    }
  }

  /// 将 CallManager.CallState 映射为 UI 友好的 CallPhase
  static CallPhase _mapCallState(CallState callState) {
    switch (callState) {
      case CallState.idle:
        return CallPhase.idle;
      case CallState.waiting:
        return CallPhase.waiting;
      case CallState.ringing:
        return CallPhase.ringing;
      case CallState.inCall:
        return CallPhase.inCall;
      case CallState.ended:
        return CallPhase.ended;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 视频渲染器访问
  // ═══════════════════════════════════════════════════════════

  /// 获取本地视频渲染器
  RTCVideoRenderer? getLocalRenderer() => _webrtc.localRenderer;

  /// 获取远端视频渲染器
  Future<RTCVideoRenderer> getRemoteRenderer(String participantId) {
    return _webrtc.getRemoteRenderer(participantId);
  }

  // ═══════════════════════════════════════════════════════════
  // 媒体控制
  // ═══════════════════════════════════════════════════════════

  /// 切换麦克风静音
  void toggleMicrophone() {
    final newMuted = !state.isMuted;
    _webrtc.toggleMicrophone(!newMuted);
    state = state.copyWith(isMuted: newMuted);
  }

  /// 切换摄像头
  void toggleCamera() {
    final newCameraOn = !state.isCameraOn;
    _webrtc.toggleCamera(newCameraOn);
    state = state.copyWith(isCameraOn: newCameraOn);
  }

  /// 切换补光
  void toggleFlash() {
    final newFlash = !state.isFlashOn;
    state = state.copyWith(isFlashOn: newFlash);
  }

  /// 翻转前后摄像头
  Future<void> flipCamera() async {
    try {
      await _webrtc.switchCamera();
      final newFront = !state.isFrontCamera;
      state = state.copyWith(isFrontCamera: newFront);
    } catch (e) {
      // 翻转失败不阻塞
    }
  }

  /// 切换扬声器
  void toggleSpeaker(bool enabled) {
    _webrtc.enableSpeakerphone(enabled);
    state = state.copyWith(isSpeakerOn: enabled);
  }

}
