import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../providers/call_provider.dart';
import '../providers/settings_provider.dart';
import '../services/audio_device_service.dart';
import '../services/call_manager.dart';

import '../utils/constants.dart';
import '../widgets/call_controls.dart';
import '../widgets/connectivity_banner.dart';
import '../widgets/debug_panel.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/name_card_overlay.dart';
import '../widgets/speaker_picker.dart';

/// 通话主界面
///
/// 支持 2 人和 3 人两种布局，自动根据参与者数量切换。
/// 包含：视频画面、网络指示、菜单按钮、控制栏、叠加层。
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ─── 叠加层状态 ───────────────────────────────────
  bool _showNameCard = false;
  bool _showSpeakerPicker = false;
  bool _showMenu = false;
  String? _nameCardTargetId; // 当前显示名片的参与者 ID

  // ─── 小窗拖拽 ────────────────────────────────────
  Offset _pipOffset = const Offset(0, 0); // 从右上角偏移
  static const double _pipWidth = 120.0;
  static const double _pipHeight = 180.0;

  // ─── 好友加入动画 ────────────────────────────────
  List<String> _previousParticipantIds = []; // 上一个参与者 ID 列表
  String? _joiningParticipantName; // 正在加入的参与者名称
  Offset _joinBannerOffset = Offset.zero; // 加入横幅动画偏移

  // ─── 网络统计 ────────────────────────────────────
  bool _showNetworkDetail = false;

  // ─── 本地渲染器 ──────────────────────────────────
  RTCVideoRenderer? _localRenderer;

  // ─── 参与者远端渲染器缓存 ────────────────────────
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  // ─── 挂断动画 ────────────────────────────────────
  late final AnimationController _hangupAnimController;
  late final Animation<double> _hangupScale;
  late final Animation<double> _hangupFade;
  bool _showHangupAnim = false;
  bool _hangupAnimPlayed = false;

  /// 当前可用音频设备列表（含蓝牙检测）
  List<AudioDevice> _availableAudioDevices = const [
    AudioDevice.speaker,
    AudioDevice.earpiece,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRenderers();
    _initHangupAnimation();
    _loadAudioDevices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PiP 画中画功能（阶段 6 实现）
  }

  /// 初始化挂断缩小消失动画
  void _initHangupAnimation() {
    _hangupAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _hangupScale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _hangupAnimController, curve: Curves.easeInBack),
    );
    _hangupFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _hangupAnimController, curve: Curves.easeOut),
    );
    _hangupAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _showHangupAnim = false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hangupAnimController.dispose();
    _cleanupRenderers();
    super.dispose();
  }

  /// 加载可用音频设备（含蓝牙检测）
  Future<void> _loadAudioDevices() async {
    final devices = await AudioDeviceService.getAvailableDevices();
    if (mounted) setState(() => _availableAudioDevices = devices);
  }

  /// 初始化渲染器
  Future<void> _initRenderers() async {
    final notifier = ref.read(callProvider.notifier);
    _localRenderer = notifier.getLocalRenderer();
    setState(() {});
  }

  /// 清理渲染器
  void _cleanupRenderers() {
    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    _remoteRenderers.clear();
    // 注意：_localRenderer 由 WebRTCService 管理，不在这里 dispose
  }

  /// 获取或创建远端渲染器
  Future<RTCVideoRenderer> _getRemoteRenderer(String participantId) async {
    if (_remoteRenderers.containsKey(participantId)) {
      return _remoteRenderers[participantId]!;
    }
    final renderer =
        await ref.read(callProvider.notifier).getRemoteRenderer(participantId);
    _remoteRenderers[participantId] = renderer;
    return renderer;
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final settings = ref.watch(settingsProvider);

    // 检测新参与者加入 → 触觉反馈 + 弹入动画
    _detectNewParticipants(callState);

    // 通话结束且动画已完成 → 显示结束报告
    if (callState.phase == CallPhase.ended &&
        callState.endReport != null &&
        _hangupAnimPlayed) {
      return _buildEndReport(callState.endReport!);
    }

    // 检测到通话结束 → 触发挂断缩小消失动画
    if (callState.phase == CallPhase.ended &&
        callState.endReport != null &&
        !_hangupAnimPlayed &&
        !_showHangupAnim) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _showHangupAnim = true);
          _hangupAnimController.forward().then((_) {
            if (mounted) {
              setState(() {
                _showHangupAnim = false;
                _hangupAnimPlayed = true;
              });
            }
          });
        }
      });
    }

    // 通话结束（无报告）→ 直接返回
    if (callState.phase == CallPhase.ended ||
        callState.phase == CallPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final participantCount = callState.participants.length;
    final layoutMode =
        participantCount <= 1 ? CallLayoutMode.twoPerson : CallLayoutMode.threePerson;

    // 主通话内容
    final body = Stack(
        children: [
          // 主视频区
          _buildVideoGrid(callState, layoutMode),

          // 前置补光效果
          if (callState.isFlashOn && callState.isFrontCamera)
            _buildFrontFlash(),

          // 顶层叠加：网络指示 + 菜单 + 名片 + 扬声器
          _buildOverlayLayer(callState, layoutMode),

          // 底部控制栏
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CallControls(
              state: ControlButtonState(
                isMuted: callState.isMuted,
                isFlashOn: callState.isFlashOn,
                isCameraOn: callState.isCameraOn,
                isFrontCamera: callState.isFrontCamera,
                isFlashAvailable: callState.isFrontCamera,
                onMicToggle: () =>
                    ref.read(callProvider.notifier).toggleMicrophone(),
                onFlashToggle: () =>
                    ref.read(callProvider.notifier).toggleFlash(),
                onCameraToggle: () =>
                    ref.read(callProvider.notifier).toggleCamera(),
                onSpeakerTap: () =>
                    setState(() => _showSpeakerPicker = !_showSpeakerPicker),
                availableCameras: callState.availableCameras,
                selectedCameraId: callState.selectedCameraId,
                onSwitchCamera: (deviceId) =>
                    ref.read(callProvider.notifier).switchToCamera(deviceId),
                onHangUp: () => ref.read(callProvider.notifier).hangUp(),
                onSettingsTap: () => _showSettingsPanel(context, settings),
              ),
            ),
          ),
        ],
      );

    // 挂断动画包裹：缩小 + 淡出
    final animatedBody = _showHangupAnim
        ? FadeTransition(
            opacity: _hangupFade,
            child: ScaleTransition(
              scale: _hangupScale,
              child: body,
            ),
          )
        : body;

    return Scaffold(
      backgroundColor: colorBlack,
      body: animatedBody,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 视频网格
  // ═══════════════════════════════════════════════════════════

  Widget _buildVideoGrid(CallState2 callState, CallLayoutMode mode) {
    switch (mode) {
      case CallLayoutMode.twoPerson:
        return _build2PLayout(callState);
      case CallLayoutMode.threePerson:
        return _build3PLayout(callState);
    }
  }

  /// 2 人布局：对方全屏 + 自己可拖拽小窗
  Widget _build2PLayout(CallState2 callState) {
    final remoteParticipants =
        callState.participants.where((p) => p.uid != _getLocalUid()).toList();

    return Stack(
      children: [
        // 对方全屏（或有远端流时显示，否则显示等待提示）
        if (remoteParticipants.isNotEmpty)
          _RemoteVideoTile(
            participantId: remoteParticipants.first.uid,
            getRenderer: _getRemoteRenderer,
            isFullScreen: true,
          )
        else
          _buildWaitingForParticipant(),

        // 自己小窗（可拖拽，松手吸附边缘）
        Positioned(
          left: _pipOffset.dx,
          top: _pipOffset.dy + MediaQuery.of(context).padding.top + 48.0,
          child: _DraggablePipWindow(
            localRenderer: _localRenderer,
            isCameraOn: callState.isCameraOn,
            nickname: ref.read(settingsProvider).nickname,
            onDragUpdate: (offset) => setState(() => _pipOffset += offset),
            onDragEnd: (velocity) => _snapPipToEdge(context, velocity),
            onTap: () => _toggleNameCard(null), // 轻触自己画面
          ),
        ),
      ],
    );
  }

  /// 3 人布局：等分网格
  Widget _build3PLayout(CallState2 callState) {
    final allParticipants = callState.participants;
    final myUid = _getLocalUid();

    return Column(
      children: [
        // 上方：远端参与者（最多 2 人）
        Expanded(
          child: Row(
            children: allParticipants
                .where((p) => p.uid != myUid)
                .map((p) => Expanded(
                      child: GestureDetector(
                        onTap: () => _toggleNameCard(p.uid),
                        child: FutureBuilder<RTCVideoRenderer>(
                          future: _getRemoteRenderer(p.uid),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return RTCVideoView(
                                snapshot.data!,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              );
                            }
                            return const Center(
                              child: CircularProgressIndicator(
                                  color: colorNeutral),
                            );
                          },
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        // 下方：自己（占一半高度）
        Expanded(
          child: GestureDetector(
            onTap: () => _toggleNameCard(null),
            child: callState.isCameraOn && _localRenderer != null
                ? RTCVideoView(
                    _localRenderer!,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : _buildStillAvatar(
                    ref.read(settingsProvider).nickname,
                    myUid,
                  ),
          ),
        ),
      ],
    );
  }

  /// 等待参与者加入的占位界面
  Widget _buildWaitingForParticipant() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48.0,
            height: 48.0,
            child: CircularProgressIndicator(color: colorNeutral),
          ),
          const SizedBox(height: 16.0),
          Text(
            '等待参与者加入...',
            style: styleBody.copyWith(color: colorWhite),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 叠加层
  // ═══════════════════════════════════════════════════════════

  Widget _buildOverlayLayer(CallState2 callState, CallLayoutMode mode) {
    final settings = ref.watch(settingsProvider);

    return Stack(
      children: [
        // 网络中断自动重连提示（通话中检测到网络中断时显示）
        const ConnectivityBanner(),

        // 好友加入弹入横幅
        if (_joiningParticipantName != null)
          _buildJoinBanner(_joiningParticipantName!),

        // 🔴 权限降级警告条
        if (callState.micPermissionDenied)
          Positioned(
            left: paddingHorizontal,
            right: paddingHorizontal,
            top: MediaQuery.of(context).padding.top + 4.0,
            child: _buildPermissionBanner('麦克风权限已拒绝，对方无法听到您的声音'),
          ),

        // 🔴 摄像头权限降级警告条
        if (callState.cameraPermissionDenied)
          Positioned(
            left: paddingHorizontal,
            right: paddingHorizontal,
            top: MediaQuery.of(context).padding.top +
                (callState.micPermissionDenied ? 48.0 : 4.0),
            child: _buildPermissionBanner('摄像头权限已拒绝，已切换为纯音频通话'),
          ),

        // 🧪 调试面板（设置中开启后显示）
        if (settings.debugPanelEnabled)
          Positioned(
            left: paddingHorizontal,
            top: MediaQuery.of(context).padding.top +
                (callState.micPermissionDenied ? 94.0 : 4.0) +
                (callState.cameraPermissionDenied ? 44.0 : 0.0) +
                50.0,
            child: const DebugPanel(),
          ),

        // 左上：网络质量指示
        Positioned(
          left: paddingHorizontal,
          top: MediaQuery.of(context).padding.top + 8.0,
          child: _NetworkIndicator(
            showDetail: _showNetworkDetail,
            onTap: () =>
                setState(() => _showNetworkDetail = !_showNetworkDetail),
          ),
        ),

        // 右上：菜单按钮
        Positioned(
          right: paddingHorizontal,
          top: MediaQuery.of(context).padding.top + 8.0,
          child: _MenuButton(
            onTap: () => setState(() => _showMenu = !_showMenu),
            showMenu: _showMenu,
            onNameCard: () {
              setState(() {
                _showMenu = false;
                _showNameCard = true;
              });
            },
            onSettings: () {
              setState(() => _showMenu = false);
              final settings = ref.read(settingsProvider);
              _showSettingsPanel(context, settings);
            },
          ),
        ),

        // 通话时长（顶部居中）
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).padding.top + 12.0,
          child: Center(
            child: Text(
              callState.formattedDuration,
              style: styleCaption.copyWith(
                color: colorWhite,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        // 底部：名片条
        if (_showNameCard) _buildNameCardBar(callState),

        // 扬声器选择面板
        if (_showSpeakerPicker)
          SpeakerPicker(
            selectedDevice:
                callState.isSpeakerOn ? AudioDevice.speaker : AudioDevice.earpiece,
            availableDevices: _availableAudioDevices,
            onSelected: (device) {
              ref
                  .read(callProvider.notifier)
                  .toggleSpeaker(device == AudioDevice.speaker);
            },
            onClose: () => setState(() => _showSpeakerPicker = false),
          ),
      ],
    );
  }

  /// 名片条
  Widget _buildNameCardBar(CallState2 callState) {
    final targetId = _nameCardTargetId;
    final settings = ref.read(settingsProvider);

    // 如果是点击自己或 targetId 为空 → 显示自己信息
    if (targetId == null || targetId == _getLocalUid()) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 80.0,
        child: NameCardBar(
          name: settings.nickname,
          avatarColor: _avatarColor(settings.localId),
          avatarText: settings.nickname.isNotEmpty
              ? settings.nickname[0]
              : '?',
          isFriend: true,
          durationText: callState.formattedDuration,
          onDismiss: () => setState(() {
            _showNameCard = false;
            _nameCardTargetId = null;
          }),
        ),
      );
    }

    // 参与者信息（从 participants 列表查找昵称，暂无则用 UID 前 4 位）
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80.0,
      child: NameCardBar(
        name: '用户 ${targetId.substring(0, min(4, targetId.length))}',
        avatarColor: _avatarColor(targetId),
        avatarText: targetId[0],
        isFriend: false,
        durationText: callState.formattedDuration,
        onAddFriend: () {
          // TODO(阶段3): 发送好友申请
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('好友申请功能将在阶段 3 实现')),
          );
        },
        onDismiss: () => setState(() {
          _showNameCard = false;
          _nameCardTargetId = null;
        }),
      ),
    );
  }

  /// 检测新参与者加入
  ///
  /// 对比前后参与者列表，当检测到新加入时：
  /// - 触发触觉反馈（HapticFeedback.lightImpact）
  /// - 显示加入横幅（顶部滑入，2秒后自动消失）
  void _detectNewParticipants(CallState2 callState) {
    if (callState.phase != CallPhase.inCall) {
      _previousParticipantIds = [];
      return;
    }

    final currentIds = callState.participants
        .where((p) => p.uid != _getLocalUid())
        .map((p) => p.uid)
        .toList();

    // 检测新加入的参与者
    final newIds = currentIds
        .where((id) => !_previousParticipantIds.contains(id))
        .toList();

    if (newIds.isNotEmpty && _previousParticipantIds.isNotEmpty) {
      // 有新参与者加入
      final newParticipant = callState.participants.firstWhere(
        (p) => p.uid == newIds.first,
        orElse: () => callState.participants.first,
      );
      final nickname = newParticipant.nickname;
      final name = (nickname != null && nickname.isNotEmpty)
          ? nickname
          : '新参与者';
      _showJoinBanner(name);
    }

    _previousParticipantIds = currentIds;
  }

  /// 显示好友加入横幅（顶部弹入 + 触觉反馈）
  void _showJoinBanner(String name) {
    // 触觉反馈
    HapticFeedback.lightImpact();

    setState(() {
      _joiningParticipantName = name;
      _joinBannerOffset = const Offset(0, -1.0); // 从顶部外开始
    });

    // 弹入动画
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        setState(() => _joinBannerOffset = Offset.zero);
      }
    });

    // 2 秒后自动消失
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _joiningParticipantName = null;
          _joinBannerOffset = const Offset(0, -1.0);
        });
      }
    });
  }

  /// 好友加入弹入横幅
  ///
  /// 顶部居中的磨砂横幅，从上方弹入，显示"XXX 加入了通话"。
  Widget _buildJoinBanner(String name) {
    return Positioned(
      left: paddingHorizontal,
      right: paddingHorizontal,
      top: MediaQuery.of(context).padding.top + 52.0,
      child: AnimatedSlide(
        offset: _joinBannerOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: colorSuccess.withAlpha(220),
            borderRadius: BorderRadius.circular(radiusPill),
            boxShadow: [
              BoxShadow(
                color: colorSuccess.withAlpha(60),
                blurRadius: 12.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_add_rounded,
                  color: colorWhite, size: 18.0),
              const SizedBox(width: 8.0),
              Flexible(
                child: Text(
                  '$name 加入了通话',
                  style: styleCaption.copyWith(
                    color: colorWhite,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 小窗松手后吸附到最近边缘
  ///
  /// 根据当前偏移量和拖拽速度判断目标边缘：
  /// - 如果速度足够大（>300 px/s），根据速度方向吸附
  /// - 否则吸附到最近边缘（左/右）
  void _snapPipToEdge(BuildContext context, Offset velocity) {
    final screenWidth = MediaQuery.of(context).size.width;
    final pipCenterX = _pipOffset.dx + _pipWidth / 2;

    // 速度足够大 → 根据速度方向判断
    final velocityLeft = velocity.dx < -300;
    final velocityRight = velocity.dx > 300;

    double targetX;
    if (velocityLeft) {
      targetX = 0; // 吸附到左边缘
    } else if (velocityRight) {
      targetX = screenWidth - _pipWidth; // 吸附到右边缘
    } else {
      // 无显著速度 → 吸附到最近边缘
      targetX = pipCenterX < screenWidth / 2
          ? 0
          : screenWidth - _pipWidth;
    }

    // 限制垂直范围
    final maxY = MediaQuery.of(context).size.height - _pipHeight - 120;
    final targetY = _pipOffset.dy.clamp(0.0, maxY);

    setState(() {
      _pipOffset = Offset(targetX, targetY);
    });
  }

  void _toggleNameCard(String? participantId) {
    setState(() {
      if (_showNameCard && _nameCardTargetId == participantId) {
        _showNameCard = false;
        _nameCardTargetId = null;
      } else {
        _showNameCard = true;
        _nameCardTargetId = participantId;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 权限降级提示条
  // ═══════════════════════════════════════════════════════════

  Widget _buildPermissionBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: colorWarning.withAlpha(200),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: colorWhite, size: 16.0),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(message,
                style: styleTiny.copyWith(color: colorWhite)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 前置补光
  // ═══════════════════════════════════════════════════════════

  Widget _buildFrontFlash() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: colorWhite.withAlpha(180),
            width: 2.0,
          ),
        ),
        // 屏幕边缘白色渐变
        foregroundDecoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorWhite.withAlpha(40),
              colorWhite.withAlpha(10),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 视频静画（摄像头关闭时的头像替代）
  // ═══════════════════════════════════════════════════════════

  Widget _buildStillAvatar(String nickname, String uid) {
    return Container(
      color: colorBlack,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80.0,
              height: 80.0,
              decoration: BoxDecoration(
                color: _avatarColor(uid),
                borderRadius: BorderRadius.circular(radiusAvatarStill),
              ),
              child: Center(
                child: Text(
                  nickname.isNotEmpty ? nickname[0] : '?',
                  style: styleTitle1.copyWith(color: colorWhite),
                ),
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              nickname,
              style: styleCaption.copyWith(color: colorNeutral),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 通话结束报告
  // ═══════════════════════════════════════════════════════════

  Widget _buildEndReport(CallEndReport report) {
    return Scaffold(
      backgroundColor: colorBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(paddingHorizontal),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.call_end_rounded,
                    color: colorDanger, size: 48.0),
                const SizedBox(height: 16.0),
                const Text('通话结束', style: styleTitle2),
                const SizedBox(height: 24.0),
                _reportRow('通话对象', report.targetName),
                _reportRow('通话时长',
                    '${report.durationSeconds ~/ 60}分${report.durationSeconds % 60}秒'),
                _reportRow('质量评级', report.qualityRating),
                _reportRow('预估流量', '${report.estimatedTrafficMB.toStringAsFixed(1)} MB'),
                if (report.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 16.0),
                  ...report.suggestions.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text('💡 $s',
                            style: styleSmall.copyWith(color: colorNeutral)),
                      )),
                ],
                const SizedBox(height: 32.0),
                GlassButton(
                  label: '返回',
                  icon: Icons.arrow_back_rounded,
                  type: GlassButtonType.normal,
                  onPressed: () {
                    ref.read(callProvider.notifier).dismissEndReport();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: styleCaption.copyWith(color: colorNeutral)),
          Text(value, style: styleBody.copyWith(color: colorTextPrimary)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 通话设置面板（底部半屏）
  // ═══════════════════════════════════════════════════════════

  void _showSettingsPanel(BuildContext context, AppSettings settings) {
    showGlassBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _CallSettingsSheet(settings: settings, ref: ref),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════════

  String _getLocalUid() => ref.read(settingsProvider).localId;

  Color _avatarColor(String uid) {
    final hash = uid.hashCode.abs();
    return avatarColorPalette[hash % avatarColorPalette.length];
  }
}

/// 通话布局模式
enum CallLayoutMode { twoPerson, threePerson }

// ═══════════════════════════════════════════════════════════
// 远端视频瓦片
// ═══════════════════════════════════════════════════════════

class _RemoteVideoTile extends StatefulWidget {
  final String participantId;
  final Future<RTCVideoRenderer> Function(String) getRenderer;
  final bool isFullScreen;

  const _RemoteVideoTile({
    required this.participantId,
    required this.getRenderer,
    this.isFullScreen = false,
  });

  @override
  State<_RemoteVideoTile> createState() => _RemoteVideoTileState();
}

class _RemoteVideoTileState extends State<_RemoteVideoTile> {
  RTCVideoRenderer? _renderer;

  @override
  void initState() {
    super.initState();
    _loadRenderer();
  }

  Future<void> _loadRenderer() async {
    final renderer = await widget.getRenderer(widget.participantId);
    if (mounted) {
      setState(() => _renderer = renderer);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_renderer == null) {
      return const Center(
        child: CircularProgressIndicator(color: colorNeutral),
      );
    }
    return RTCVideoView(
      _renderer!,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 可拖拽小窗（PIP）
// ═══════════════════════════════════════════════════════════

class _DraggablePipWindow extends StatefulWidget {
  final RTCVideoRenderer? localRenderer;
  final bool isCameraOn;
  final String nickname;
  final void Function(Offset offset) onDragUpdate;
  final void Function(Offset velocity) onDragEnd;
  final VoidCallback onTap;

  const _DraggablePipWindow({
    required this.localRenderer,
    required this.isCameraOn,
    required this.nickname,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTap,
  });

  @override
  State<_DraggablePipWindow> createState() => _DraggablePipWindowState();
}

class _DraggablePipWindowState extends State<_DraggablePipWindow> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onPanUpdate: (details) => widget.onDragUpdate(details.delta),
      onPanEnd: (details) => widget.onDragEnd(details.velocity.pixelsPerSecond),
      child: Container(
        width: 120.0,
        height: 180.0,
        decoration: BoxDecoration(
          color: colorBlack,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: colorWhite.withAlpha(77), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: colorBlack.withAlpha(77),
              blurRadius: 8.0,
              offset: const Offset(0, 2.0),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11.0),
          child: widget.isCameraOn && widget.localRenderer != null
              ? RTCVideoView(
                  widget.localRenderer!,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : _buildStillAvatar(widget.nickname),
        ),
      ),
    );
  }

  Widget _buildStillAvatar(String nickname) {
    return Container(
      color: colorBlack,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.0,
              height: 40.0,
              decoration: BoxDecoration(
                color: avatarColorPalette[nickname.hashCode.abs() % avatarColorPalette.length],
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Center(
                child: Text(
                  nickname.isNotEmpty ? nickname[0] : '?',
                  style: const TextStyle(
                    color: colorWhite,
                    fontSize: 20.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 网络质量指示器
// ═══════════════════════════════════════════════════════════

class _NetworkIndicator extends StatelessWidget {
  final bool showDetail;
  final VoidCallback onTap;

  const _NetworkIndicator({
    required this.showDetail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 默认绿色（阶段 2-C 先静态，阶段 2-D 接入真实统计）
    const color = colorSuccess;
    const rtt = 45;
    const loss = 0.2;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: colorGlassBackground.withAlpha(120),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: networkIndicatorDiameter,
              height: networkIndicatorDiameter,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(100),
                    blurRadius: 2.0,
                  ),
                ],
              ),
            ),
            if (showDetail) ...[
              const SizedBox(width: 8.0),
              Text(
                '${rtt}ms · ${loss.toStringAsFixed(1)}%',
                style: styleTiny.copyWith(color: colorWhite),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 菜单按钮
// ═══════════════════════════════════════════════════════════

class _MenuButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool showMenu;
  final VoidCallback onNameCard;
  final VoidCallback onSettings;

  const _MenuButton({
    required this.onTap,
    required this.showMenu,
    required this.onNameCard,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 弹出菜单
        if (showMenu)
          Container(
            margin: const EdgeInsets.only(bottom: 4.0),
            decoration: BoxDecoration(
              color: colorGlassBackground.withAlpha(200),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _menuItem('名片', Icons.badge_rounded, onNameCard),
                _menuItem('设置', Icons.settings_rounded, onSettings),
              ],
            ),
          ),

        // ☰ 按钮
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36.0,
            height: 36.0,
            decoration: BoxDecoration(
              color: colorGlassBackground.withAlpha(120),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.menu_rounded,
              color: colorWhite,
              size: 22.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuItem(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colorWhite, size: 18.0),
            const SizedBox(width: 8.0),
            Text(label, style: styleSmall.copyWith(color: colorWhite)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 通话设置底部面板
// ═══════════════════════════════════════════════════════════

class _CallSettingsSheet extends StatefulWidget {
  final AppSettings settings;
  final WidgetRef ref;
  const _CallSettingsSheet({required this.settings, required this.ref});

  @override
  State<_CallSettingsSheet> createState() => _CallSettingsSheetState();
}

class _CallSettingsSheetState extends State<_CallSettingsSheet> {
  late CameraResolution _resolution;
  late FrameRateOption _frameRate;
  late String _qualityPref;
  late bool _h265Enabled;
  late String _audioCodec;
  late int _audioBitrate;
  late bool _aec;
  late bool _ans;
  late bool _agc;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _resolution = s.cameraResolution;
    _frameRate = s.frameRate;
    _qualityPref = s.qualityPreference.name;
    _h265Enabled = s.h265Enabled;
    _audioCodec = s.audioCodec;
    _audioBitrate = s.audioBitrate;
    _aec = s.aecEnabled;
    _ans = s.ansEnabled;
    _agc = s.agcEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: colorGlassBackground,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
      ),
      child: Column(
        children: [
          // 标题栏
          _buildHeader(),
          // 可滚动内容
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
              children: [
                _sectionTitle('视频'),
                ..._buildVideoSettings(),
                const SizedBox(height: 16.0),
                _sectionTitle('音频'),
                ..._buildAudioSettings(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.close_rounded, color: colorTextPrimary),
          ),
          const Text('通话设置', style: styleTitle3),
          GestureDetector(
            onTap: _applySettings,
            child: Text(
              '应用',
              style: styleCaption.copyWith(
                color: colorAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 应用并保存所有通话设置
  void _applySettings() {
    final newSettings = widget.settings.copyWith(
      cameraResolution: _resolution,
      frameRate: _frameRate,
      qualityPreference: _qualityPref == 'smooth'
          ? QualityPreference.smooth
          : _qualityPref == 'balanced'
              ? QualityPreference.balanced
              : QualityPreference.clear,
      h265Enabled: _h265Enabled,
      audioCodec: _audioCodec,
      audioBitrate: _audioBitrate,
      aecEnabled: _aec,
      ansEnabled: _ans,
      agcEnabled: _agc,
    );

    // 持久化保存
    widget.ref.read(settingsProvider.notifier).saveAllSettings(newSettings);

    // 如果正在通话中，立即应用媒体配置
    final callNotifier = widget.ref.read(callProvider.notifier);
    if (callNotifier.isInCallOrWaiting) {
      callNotifier.applyMediaSettings(newSettings);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('设置已应用'),
        duration: Duration(seconds: 1),
      ),
    );
    Navigator.of(context).pop();
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Text(title,
          style: styleCaption.copyWith(
              color: colorNeutral, fontWeight: FontWeight.w600)),
    );
  }

  List<Widget> _buildVideoSettings() {
    return [
      _dropdownRow('分辨率', _resolution.label,
          CameraResolution.values.map((r) => r.label).toList(),
          (v) => setState(() => _resolution = CameraResolution.values.firstWhere((r) => r.label == v))),
      _dropdownRow('最高帧率', _frameRate.label,
          FrameRateOption.values.map((f) => f.label).toList(),
          (v) => setState(() => _frameRate = FrameRateOption.values.firstWhere((f) => f.label == v))),
      _dropdownRow('画质偏好', _qualityLabel(_qualityPref),
          ['smooth', 'balanced', 'clear'],
          (v) => setState(() => _qualityPref = v)),
      _switchRow('H.265编码', _h265Enabled,
          (v) => setState(() => _h265Enabled = v)),
    ].map((w) => _settingsCard(child: w)).toList();
  }

  List<Widget> _buildAudioSettings() {
    return [
      _dropdownRow('编码格式', _audioCodec,
          ['Opus 标准', 'Opus 省流', 'G.722'],
          (v) => setState(() => _audioCodec = v)),
      _dropdownRow('音频码率', '$_audioBitrate Kbps',
          ['24', '48', '64'],
          (v) => setState(() => _audioBitrate = int.parse(v))),
      _switchRow('回声消除', _aec, (v) => setState(() => _aec = v)),
      _switchRow('噪声抑制', _ans, (v) => setState(() => _ans = v)),
      _switchRow('自动增益', _agc, (v) => setState(() => _agc = v)),
    ].map((w) => _settingsCard(child: w)).toList();
  }

  String _qualityLabel(String key) {
    return {
      'smooth': '流畅优先',
      'balanced': '均衡',
      'clear': '清晰优先',
    }[key] ?? key;
  }

  Widget _settingsCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1.0),
      child: child,
    );
  }

  Widget _dropdownRow(
      String label, String currentValue, List<String> options,
      void Function(String) onChanged) {
    return Container(
      height: 56.0,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: colorGlassBackground.withAlpha(60),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        children: [
          Text(label, style: styleCaption.copyWith(color: colorTextPrimary)),
          const Spacer(),
          Text(currentValue, style: styleCaption.copyWith(color: colorAccent)),
          const Icon(Icons.arrow_drop_down_rounded, color: colorAccent),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, void Function(bool) onChanged) {
    return Container(
      height: 56.0,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: colorGlassBackground.withAlpha(60),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        children: [
          Text(label, style: styleCaption.copyWith(color: colorTextPrimary)),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: colorAccent,
          ),
        ],
      ),
    );
  }
}
