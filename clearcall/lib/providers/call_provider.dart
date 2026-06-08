import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/call_manager.dart';
import '../services/signaling/firebase_signaling.dart';
import '../services/webrtc_service.dart';
import '../utils/constants.dart';
import 'settings_provider.dart';

/// 通话状态 Provider
///
/// 持有 CallManager 实例，通过 Riverpod 暴露通话状态给 UI 层。
/// 所有 UI 通过此 Provider 观察和操作通话，不直接操作 CallManager。
final callProvider = StateNotifierProvider<CallNotifier, CallState2>(
  (ref) {
    final localId = ref.read(settingsProvider).localId;

    final signaling = FirebaseSignaling();
    final webrtc = WebRTCService(
      iceServers: WebRTCService.defaultIceServers,
    );

    final notifier = CallNotifier(
      signaling: signaling,
      webrtc: webrtc,
      localUid: localId,
    );

    // 异步初始化 Firebase
    notifier.initialize();

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

  const CallState2({
    this.phase = CallPhase.idle,
    this.roomId,
    this.participants = const [],
    this.elapsedSeconds = 0,
    this.isLoading = false,
    this.errorMessage,
    this.endReport,
  });

  CallState2 copyWith({
    CallPhase? phase,
    String? roomId,
    List<CallParticipant>? participants,
    int? elapsedSeconds,
    bool? isLoading,
    String? errorMessage,
    CallEndReport? endReport,
    bool clearError = false,
    bool clearReport = false,
  }) {
    return CallState2(
      phase: phase ?? this.phase,
      roomId: roomId ?? this.roomId,
      participants: participants ?? this.participants,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      endReport: clearReport ? null : (endReport ?? this.endReport),
    );
  }
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

        // 如果回到 idle（呼叫被拒等情况），清除房间号
        if (callState == CallState.idle) {
          state = state.copyWith(roomId: null);
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
        );
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

  /// 创建新房间
  Future<void> createRoom() async {
    _ensureInitialized();

    try {
      state = state.copyWith(phase: CallPhase.connecting, errorMessage: null);

      final roomId = await _callManager.createRoom();

      state = state.copyWith(
        phase: CallPhase.waiting,
        roomId: roomId,
        errorMessage: null,
      );
    } on StateError catch (e) {
      // 已在通话中
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

  @override
  void dispose() {
    _signaling.dispose();
    super.dispose();
  }
}
