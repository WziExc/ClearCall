import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/quality_presets.dart';
import '../services/call_manager.dart';
import '../services/signaling/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../utils/constants.dart';
import 'settings_provider.dart';
import 'signaling_provider.dart';

/// 通话状态 Provider
///
/// 持有 CallManager 实例，通过 Riverpod 暴露通话状态给 UI 层。
/// 所有 UI 通过此 Provider 观察和操作通话，不直接操作 CallManager。
///
/// 使用 ref.read（不 watch），CallNotifier 是长生命周期对象。
/// room_waiting_screen 等需要感知信令类型的页面应直接读取 signalingProvider。
final callProvider = StateNotifierProvider<CallNotifier, CallState2>(
  (ref) {
    final settings = ref.read(settingsProvider);
    final localId = settings.localId;
    final signaling = ref.read(signalingProvider);

    // 从 AppSettings 生成 MediaConfig（用户保存的画质偏好）
    final mediaConfig = presetToMediaConfig(
      settings.selectedPreset,
      customVideoCodec: settings.videoCodec,
      customVideoBitrate: settings.videoBitrate,
      customAudioCodec: audioCodecToRaw(settings.audioCodec),
      customAudioSampleRate: audioSampleRateFromCodec(settings.audioCodec),
      customAudioBitrate: settings.audioBitrate * 1000, // Kbps → bps
      aecEnabled: settings.aecEnabled,
      ansEnabled: settings.ansEnabled,
      agcEnabled: settings.agcEnabled,
    );

    final webrtc = WebRTCService(
      iceServers: WebRTCService.defaultIceServers,
      config: mediaConfig,
    );

    final notifier = CallNotifier(
      signaling: signaling,
      webrtc: webrtc,
      localUid: localId,
      initialSettings: settings,
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

  /// 房间创建时间（用于 UI 计算真实剩余超时秒数）
  final DateTime? roomCreatedAt;

  /// 本地视频渲染器是否已就绪（摄像头 + 流已绑定）
  final bool localRendererReady;

  /// 摄像头实时状态
  final CameraStatus cameraStatus;

  /// 可用摄像头列表
  final List<CameraInfo> availableCameras;

  /// 当前选中的摄像头 ID
  final String? selectedCameraId;

  /// 当前画质预设
  final QualityPreset currentPreset;

  /// 当前网络统计（最新一次采集）
  final WebRTCStats? currentStats;

  /// 自适应画质是否启用
  final bool autoAdaptEnabled;

  const CallState2({
    this.currentPreset = QualityPreset.standard,
    this.currentStats,
    this.autoAdaptEnabled = true,
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
    this.roomCreatedAt,
    this.localRendererReady = false,
    this.cameraStatus = CameraStatus.initializing,
    this.availableCameras = const [],
    this.selectedCameraId,
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
    DateTime? roomCreatedAt,
    bool? localRendererReady,
    CameraStatus? cameraStatus,
    List<CameraInfo>? availableCameras,
    String? selectedCameraId,
    QualityPreset? currentPreset,
    WebRTCStats? currentStats,
    bool? autoAdaptEnabled,
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
      roomCreatedAt: roomCreatedAt ?? this.roomCreatedAt,
      localRendererReady:
          localRendererReady ?? this.localRendererReady,
      cameraStatus: cameraStatus ?? this.cameraStatus,
      availableCameras: availableCameras ?? this.availableCameras,
      selectedCameraId: selectedCameraId ?? this.selectedCameraId,
      currentPreset: currentPreset ?? this.currentPreset,
      currentStats: currentStats ?? this.currentStats,
      autoAdaptEnabled: autoAdaptEnabled ?? this.autoAdaptEnabled,
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

/// 摄像头状态
enum CameraStatus {
  /// 正在初始化
  initializing,

  /// 已就绪（画面正常）
  ready,

  /// 异常（摄像头被占用、断开或未知错误）
  error,

  /// 权限被拒绝
  permissionDenied,
}

/// 可用摄像头信息
class CameraInfo {
  final String deviceId;
  final String label;

  const CameraInfo({required this.deviceId, required this.label});

  /// 是否为前置摄像头（根据标签推断）
  bool get isFront => label.contains('front') || label.contains('前置');

  /// 显示名称（简短友好）
  String get displayLabel {
    if (label.isEmpty) return '摄像头 ${deviceId.substring(0, 4)}';
    // 提取简短名称（去除冗长的 USB 描述）
    if (isFront) return '前置摄像头';
    if (label.contains('back') || label.contains('后置')) return '后置摄像头';
    if (label.length > 20) return '${label.substring(0, 18)}…';
    return label;
  }
}

/// 通话状态管理器
///
/// 封装 CallManager，通过 Riverpod 提供响应式状态。
/// 负责：
/// - 初始化 Firebase 和 WebRTC
/// - 将 CallManager 的回调转换为 state 更新
/// - 暴露简化的 API 给 UI
class CallNotifier extends StateNotifier<CallState2> {
  final SignalingService _signaling;
  final WebRTCService _webrtc;
  final String _localUid;

  /// 核心通话管理器
  late final CallManager _callManager;

  /// 信令服务是否已初始化
  bool _initialized = false;

  CallNotifier({
    required SignalingService signaling,
    required WebRTCService webrtc,
    required String localUid,
    AppSettings? initialSettings,
  })  : _signaling = signaling,
        _webrtc = webrtc,
        _localUid = localUid,
        _settings = initialSettings,
        super(CallState2(
          currentPreset: initialSettings?.selectedPreset ?? QualityPreset.standard,
          autoAdaptEnabled: initialSettings?.autoAdaptEnabled ?? true,
        ));

  /// 保存初始设置引用（用于创建 CallManager 时传递配置）
  final AppSettings? _settings;

  /// 初始化 Firebase 和 CallManager
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      state = state.copyWith(isLoading: true);

      await _signaling.initialize();

      // 从设置生成 MediaConfig
      final s = _settings;
      final mediaConfig = s != null
          ? presetToMediaConfig(
              s.selectedPreset,
              customVideoCodec: s.videoCodec,
              customVideoBitrate: s.videoBitrate,
              customAudioCodec: audioCodecToRaw(s.audioCodec),
              customAudioSampleRate: audioSampleRateFromCodec(s.audioCodec),
              customAudioBitrate: s.audioBitrate * 1000, // Kbps → bps
              aecEnabled: s.aecEnabled,
              ansEnabled: s.ansEnabled,
              agcEnabled: s.agcEnabled,
            )
          : null;

      _callManager = CallManager(
        signaling: _signaling,
        webrtc: _webrtc,
        localUid: _localUid,
        mediaConfig: mediaConfig,
        autoAdaptEnabled: _settings?.autoAdaptEnabled ?? true,
      );

      // 绑定 CallManager 回调 → state 更新
      _callManager.onStateChanged = (callState) {
        final phase = _mapCallState(callState);
        state = state.copyWith(phase: phase, errorMessage: null);

        if (callState == CallState.idle) {
          state = state.copyWith(
            roomId: null,
            roomCreatedAt: null,
            localRendererReady: false,
            friendCallTargetUid: null,
            isFriendCall: false,
            cameraStatus: CameraStatus.initializing,
          );
        }
      };

      // 绑定本地渲染器就绪回调
      _callManager.onLocalRendererReady = () {
        state = state.copyWith(
          localRendererReady: true,
          cameraStatus: CameraStatus.ready,
        );
      };

      // 绑定摄像头异常回调（视频轨道意外终止时恢复状态）
      _webrtc.onCameraError = () {
        state = state.copyWith(
          cameraStatus: CameraStatus.error,
          localRendererReady: false,
        );
      };

      _callManager.onParticipantsChanged = (participants) {
        state = state.copyWith(participants: participants);
      };

      _callManager.onDurationTick = (elapsed) {
        state = state.copyWith(elapsedSeconds: elapsed);
      };

      _callManager.onCallEnded = (report) {
        // 0 秒通话 = 房间从未接通 → 自动跳过结束报告
        if (report.durationSeconds == 0) {
          _callManager.resetStateToIdle();
          state = state.copyWith(
            phase: CallPhase.idle,
            roomId: null,
            roomCreatedAt: null,
            localRendererReady: false,
            participants: const [],
            elapsedSeconds: 0,
            friendCallTargetUid: null,
            isFriendCall: false,
            clearReport: true,
            clearError: true,
          );
          return;
        }
        state = state.copyWith(
          phase: CallPhase.ended,
          endReport: report,
          roomId: null,
          roomCreatedAt: null,
          localRendererReady: false,
          participants: [],
          elapsedSeconds: 0,
          friendCallTargetUid: null,
          isFriendCall: false,
        );

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

      // 监听画质预设自动变化（自适应引擎触发）
      _wireQualityController();

      // 后台加载可用摄像头列表
      unawaited(loadAvailableCameras());
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
      // 自动清理残留状态
      if (_callManager.state == CallState.ended) {
        _callManager.resetStateToIdle();
      } else if (_callManager.state == CallState.waiting) {
        await _callManager.hangUp();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      state = state.copyWith(phase: CallPhase.connecting, errorMessage: null);

      final roomId = await _callManager.createRoom();

      state = state.copyWith(
        phase: CallPhase.waiting,
        roomId: roomId,
        roomCreatedAt: _callManager.roomCreatedAt,
        localRendererReady: true,
        isFriendCall: false,
        errorMessage: null,
      );
    } on StateError {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '请先结束当前通话再创建新房间',
      );
    } catch (e) {
      state = state.copyWith(
        phase: CallPhase.idle,
        errorMessage: '创建房间失败，请检查网络或切换到「QR 扫码」模式',
      );
      rethrow; // 让 room_waiting_screen 的 try/catch 也能感知
    }
  }

  /// 为 QrSignaling 主动生成 Offer SDP（扫码交换模式专用）
  Future<void> prepareQrOffer() async {
    _ensureInitialized();
    await _callManager.prepareQrOffer();
  }

  /// 加入已有房间
  Future<void> joinRoom(String roomCode) async {
    _ensureInitialized();

    try {
      // 自动清理残留状态
      if (_callManager.state == CallState.ended) {
        _callManager.resetStateToIdle();
      } else if (_callManager.state == CallState.waiting) {
        await _callManager.hangUp();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      state = state.copyWith(phase: CallPhase.connecting, errorMessage: null);

      await _callManager.joinRoom(roomCode);

      state = state.copyWith(
        phase: CallPhase.waiting,
        roomId: roomCode,
        roomCreatedAt: _callManager.roomCreatedAt,
        localRendererReady: true,
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
    // 如果是 connecting 阶段（HTTP 请求可能卡住），强制重置状态
    if (state.phase == CallPhase.connecting) {
      _callManager.resetStateToIdle();
      state = state.copyWith(
        phase: CallPhase.idle,
        roomId: null,
        roomCreatedAt: null,
        localRendererReady: false,
        clearError: true,
      );
      return;
    }
    await hangUp();
  }

  /// 关闭结束报告，回到 idle
  void dismissEndReport() {
    _callManager.resetStateToIdle();
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

  // ═══════════════════════════════════════════════════════════
  // 摄像头管理
  // ═══════════════════════════════════════════════════════════

  /// 加载可用摄像头列表
  Future<void> loadAvailableCameras() async {
    try {
      final sources = await _webrtc.getVideoSources();
      final cameras = sources
          .map((d) => CameraInfo(
                deviceId: d['deviceId']?.toString() ?? '',
                label: d['label']?.toString() ?? '',
              ))
          .where((c) => c.deviceId.isNotEmpty)
          .toList();
      state = state.copyWith(availableCameras: cameras);
    } catch (_) {
      // 设备不支持枚举，忽略
    }
  }

  /// 切换到指定摄像头
  Future<void> switchToCamera(String deviceId) async {
    if (state.selectedCameraId == deviceId) return;

    try {
      state = state.copyWith(
        selectedCameraId: deviceId,
        cameraStatus: CameraStatus.initializing,
      );

      await _webrtc.switchCameraSource(deviceId);

      // 根据摄像头标签判断前后
      final camera = state.availableCameras
          .where((c) => c.deviceId == deviceId)
          .firstOrNull;
      final isFront = camera?.isFront ?? true;

      state = state.copyWith(
        isFrontCamera: isFront,
        cameraStatus: CameraStatus.ready,
      );
    } catch (e) {
      state = state.copyWith(
        cameraStatus: CameraStatus.error,
        errorMessage: '摄像头切换失败',
      );
    }
  }

  /// 更新摄像头状态（供 WebRTCService 回调）
  void updateCameraStatus(CameraStatus status) {
    state = state.copyWith(cameraStatus: status);
    if (status == CameraStatus.permissionDenied) {
      state = state.copyWith(cameraPermissionDenied: true, isCameraOn: false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 画质预设控制
  // ═══════════════════════════════════════════════════════════

  /// 切换画质预设（通话中即时生效码率）
  Future<void> switchPreset(QualityPreset preset) async {
    await _callManager.switchPreset(preset);
    state = state.copyWith(currentPreset: preset);
  }

  /// 开关自适应画质
  void setAutoAdapt(bool enabled) {
    _callManager.setAutoAdapt(enabled);
    state = state.copyWith(autoAdaptEnabled: enabled);
  }

  /// 刷新当前网络统计（供 UI 轮询）
  void refreshStats() {
    final stats = _callManager.latestStats;
    if (stats != null) {
      state = state.copyWith(currentStats: stats);
    }
  }

  /// 获取 QualityController（供 UI 访问预设变化回调）
  void _wireQualityController() {
    final qc = _callManager.qualityController;
    if (qc != null) {
      qc.onPresetChanged = (oldPreset, newPreset) {
        state = state.copyWith(currentPreset: newPreset);
      };
    }
  }

}
