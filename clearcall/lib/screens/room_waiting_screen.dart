import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/call_provider.dart';
import '../providers/signaling_provider.dart';
import '../services/signaling/qr_signaling.dart';
import '../utils/constants.dart';
import '../utils/dialogs.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_dialog.dart';
import 'call_screen.dart';

/// 房间等待页面
///
/// 创建或加入房间后显示。精简设计：
/// - 顶部标题 "等待加入" + 省略号循环动画（2 秒周期）
/// - 全屏摄像头预览背景
/// - 渐变模糊光韵白边（等待感）
/// - 底部显示倒计时 + 超时提示
/// - "邀请好友" / "退出房间" 按钮
///
/// [createOnEnter] 为 true 时，initState 中自动调用 createRoom()。
/// [sharedRenderer] CallTab 共享的预览渲染器，用于动画期间保持画面连续。
/// [onReleaseCamera] 释放摄像头硬件但保留渲染器最后一帧（避免黑屏）。
/// [onCleanupRenderer] WebRTC 就绪后彻底清理共享渲染器。
/// [fromRect] 摄像头卡片在 CallTab 中的位置（用于入场/退场缩放动画）。
class RoomWaitingScreen extends ConsumerStatefulWidget {
  final bool createOnEnter;
  final RTCVideoRenderer? sharedRenderer;
  final Future<void> Function()? onReleaseCamera;
  final Future<void> Function()? onCleanupRenderer;
  final Rect? fromRect;
  const RoomWaitingScreen({
    super.key,
    this.createOnEnter = false,
    this.sharedRenderer,
    this.onReleaseCamera,
    this.onCleanupRenderer,
    this.fromRect,
  });

  @override
  ConsumerState<RoomWaitingScreen> createState() => _RoomWaitingScreenState();
}

class _RoomWaitingScreenState extends ConsumerState<RoomWaitingScreen>
    with TickerProviderStateMixin {
  /// 静态回调：供 _InvitePanel 点击"扫描对方的回应码"时调用
  static void Function()? _scanAnswerQr;

  /// 倒计时刷新（每秒一次，用于 UI 更新）
  Timer? _uiTickTimer;

  /// createOnEnter 模式下是否已启动创建流程
  bool _createStarted = false;

  /// createOnEnter 模式下房间是否创建成功
  bool _roomCreated = false;

  String? _offerSdp;
  String? _answerSdp;
  Timer? _sdpPollTimer;

  /// 省略号动画控制器（2 秒一个循环）
  late AnimationController _dotsController;

  /// 光韵呼吸动画（3 秒周期）
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  /// ─── 入场/退场缩放动画 ───
  /// 摄像头从 CallTab 卡片位置缩放到全屏（或反向）
  late AnimationController _enterController;
  late Animation<double> _enterAnimation;
  bool _enterComplete = false; // 入场动画是否完成
  bool _isExiting = false; // 是否正在执行退场动画

  @override
  void initState() {
    super.initState();

    // 省略号动画：2 秒周期，循环往复
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // 光韵呼吸动画：3 秒周期
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // 入场缩放动画：350ms, easeInOut
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _enterAnimation = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeInOut,
    );

    // UI 定时刷新（每秒，用于倒计时 + 光韵）
    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final callState = ref.read(callProvider);
      if (callState.phase == CallPhase.waiting && callState.roomCreatedAt != null) {
        final elapsed = DateTime.now().difference(callState.roomCreatedAt!).inSeconds;
        if (elapsed >= roomTimeout.inSeconds) {
          _uiTickTimer?.cancel();
          _onTimeout();
          return;
        }
      }
      setState(() {});
    });

    // 第一帧后：启动入场动画 + 创建房间/初始化 QR
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 有卡片位置 → 启动缩放动画
      if (widget.fromRect != null) {
        _enterController.forward().then((_) {
          if (mounted) setState(() => _enterComplete = true);
        });
      } else {
        // 无位置信息 → 跳过动画，直接标记完成
        if (mounted) setState(() => _enterComplete = true);
      }

      _tryCreateRoom();
      _initQrFlow();
    });
  }

  @override
  void dispose() {
    _uiTickTimer?.cancel();
    _sdpPollTimer?.cancel();
    _dotsController.dispose();
    _glowController.dispose();
    _enterController.dispose();
    super.dispose();
  }

  /// 如果 widget.createOnEnter 为 true，则在页面内创建房间
  ///
  /// 流程：等待入场动画完成 → 释放共享摄像头（保留帧）→ createRoom()
  /// → 成功后清理共享渲染器。入场动画期间复用 CallTab 预览，画面连续。
  Future<void> _tryCreateRoom() async {
    if (!widget.createOnEnter || _createStarted) return;

    _createStarted = true;

    // 等待入场缩放动画完成（摄像头从卡片位置放大到全屏）
    if (widget.fromRect != null && _enterController.isAnimating) {
      await _enterController.forward();
      if (mounted) setState(() => _enterComplete = true);
    }

    // 释放共享摄像头硬件（保留渲染器最后一帧，避免黑屏）
    if (widget.onReleaseCamera != null) {
      await widget.onReleaseCamera!();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;

    try {
      await ref.read(callProvider.notifier).createRoom();
      if (mounted) {
        setState(() => _roomCreated = true);
        setState(() => _enterComplete = true);
      }
      // WebRTC 已就绪 → 清理共享渲染器
      await Future.delayed(const Duration(milliseconds: 150));
      await widget.onCleanupRenderer?.call();
    } catch (_) {
      // 创建失败 → 状态中有 errorMessage，UI 会检测并自动返回
    } finally {
      if (mounted) setState(() => _createStarted = false);
    }
  }

  /// 倒计时归零 → 强制关闭房间并返回首页
  void _onTimeout() {
    try {
      ref.read(callProvider.notifier).cancelWaiting();
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// 初始化 QR 流程：创建方生成 Offer，加入方轮询 Answer
  Future<void> _initQrFlow() async {
    final signaling = ref.read(signalingProvider);
    if (signaling is! QrSignaling) return;

    // 检查是否是加入方（已经有 Answer 或即将有）
    if (signaling.offerSdpForQr == null) {
      // 加入方：轮询等待 Answer SDP 生成
      _sdpPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) {
          _sdpPollTimer?.cancel();
          return;
        }
        final answer = signaling.answerSdpForQr;
        if (answer != null && _answerSdp == null) {
          setState(() => _answerSdp = answer);
          _sdpPollTimer?.cancel();
        }
      });
      return;
    }

    // 创建方：Offer 已准备好，直接使用
    try {
      await ref.read(callProvider.notifier).prepareQrOffer();
      if (!mounted) return;
      setState(() {
        _offerSdp = signaling.offerSdpForQr;
      });
    } catch (e) {
      debugPrint('QR Offer 准备失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);

    // 通话已开始 → 跳转
    if (callState.phase == CallPhase.inCall) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CallScreen()),
          );
        }
      });
      return const SizedBox.shrink();
    }

    // 正在创建房间 → 加载中
    if (callState.phase == CallPhase.connecting) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colorAccent),
              SizedBox(height: 20),
              Text('正在创建房间...',
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // createOnEnter 模式：已停预览但 createRoom 尚未返回 → 过渡加载
    if (_createStarted && callState.phase == CallPhase.idle) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colorAccent),
              SizedBox(height: 20),
              Text('正在准备摄像头...',
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // 退场动画进行中不触发 shouldPop（由 _handleBack 控制弹出时机）
    final shouldPop = !_isExiting &&
        (callState.phase == CallPhase.ended ||
            callState.phase == CallPhase.idle) &&
        (widget.createOnEnter
            ? (_roomCreated || callState.errorMessage != null)
            : true);

    if (shouldPop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        if (callState.errorMessage != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(callState.errorMessage!),
              backgroundColor: colorDanger,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
      return const SizedBox.shrink();
    }

    final roomId = callState.roomId ?? '------';
    final screenSize = MediaQuery.of(context).size;
    final webRtcRenderer = ref.read(callProvider.notifier).getLocalRenderer();
    final webRtcReady = callState.localRendererReady &&
        webRtcRenderer != null &&
        webRtcRenderer.srcObject != null;

    // 优先用 WebRTC 摄像头，未就绪时复用 CallTab 的共享预览
    final sharedReady = widget.sharedRenderer != null &&
        widget.sharedRenderer!.srcObject != null;
    final effectiveRenderer = webRtcReady ? webRtcRenderer : widget.sharedRenderer;
    final showCamera = webRtcReady || sharedReady;

    // 是否正在执行入场/退场动画
    final fromRect = widget.fromRect;
    final isAnimating = (fromRect != null && !_enterComplete) || _isExiting;

    return AnimatedBuilder(
      animation: _enterAnimation,
      builder: (context, _) {
        // 动画进度：正向 0→1（入场放大），反向 1→0（退场缩小）
        final t = _enterAnimation.value;

        // 背景透明度：入场 0→1，退场 1→0
        final bgOpacity = isAnimating ? t.clamp(0.0, 1.0) : 1.0;

        // 内容透明度：延迟 0.12，入场时 0.12→1.0 映射到 0→1，退场时对称
        final contentOpacity = isAnimating
            ? ((t - 0.12) / 0.88).clamp(0.0, 1.0)
            : 1.0;

        return PopScope(
          canPop: false, // 始终拦截 → 统一走 _handleBack 退场动画
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _handleBack();
          },
          child: Scaffold(
            backgroundColor: Colors.black.withAlpha(
                (255 * bgOpacity).round()),
            body: Stack(
              children: [
                // ─── 摄像头画面 ───
                if (isAnimating && fromRect != null)
                  _buildZoomingCamera(
                    t,
                    fromRect,
                    screenSize,
                    effectiveRenderer,
                    showCamera,
                  )
                else
                  _buildFullScreenCamera(effectiveRenderer, showCamera),

                // ─── 光韵白边（动画完成后才显示）───
                if (webRtcReady && !isAnimating) _buildGlowRing(),

                // ─── 内容层（淡入淡出）───
                Opacity(
                  opacity: contentOpacity,
                  child: Stack(
                    children: [
                      // 顶部渐变遮罩
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 160.0,
                        child: IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x99000000),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 底部渐变遮罩
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 260.0,
                        child: IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Color(0xCC000000),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 主内容
                      SafeArea(
                        child: Column(
                          children: [
                            const SizedBox(height: 8.0),
                            _buildHeader(),
                            const Spacer(),
                            _buildBottomOverlay(roomId),
                            const SizedBox(height: 24.0),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 顶部标题栏（含省略号动画 + 返回按钮）
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Row(
        children: [
          // 返回箭头 → 触发退场动画
          GestureDetector(
            onTap: _handleBack,
            child: Container(
              width: 36.0,
              height: 36.0,
              decoration: BoxDecoration(
                color: colorGlassBackground,
                borderRadius: BorderRadius.circular(18.0),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: colorTextPrimary,
                size: 20.0,
              ),
            ),
          ),
          const Spacer(),
          // "等待加入" + 动画省略号
          _buildAnimatedTitle(),
          const Spacer(),
          const SizedBox(width: 36.0),
        ],
      ),
    );
  }

  /// 退场动画 + 弹出路由
  ///
  /// 流程：反向播放缩放动画（摄像头从全屏缩小回卡片，画面保持连续）
  /// → pop。不取消房间、不清理渲染器 — 留给 CallTab 生命周期管理。
  Future<void> _handleBack() async {
    if (_isExiting || !_enterComplete) return;
    _isExiting = true;

    await _enterController.reverse();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 缩放动画中的摄像头：从 CallTab 卡片位置 → 全屏（或反向）
  ///
  /// [t] 动画进度：0=卡片位置，1=全屏
  /// 使用 Positioned 动态计算 left/top/width/height，
  /// RTCVideoView 的 objectFit: cover 保证画面始终填充容器。
  Widget _buildZoomingCamera(
    double t,
    Rect fromRect,
    Size screenSize,
    RTCVideoRenderer? renderer,
    bool ready,
  ) {
    // 线性插值（等价于 lerpDouble，避免 import 问题）
    double _l(double a, double b, double x) => a + (b - a) * x;
    final ct = t.clamp(0.0, 1.0);

    final left = _l(fromRect.left, 0, ct);
    final top = _l(fromRect.top, 0, ct);
    final width = _l(fromRect.width, screenSize.width, ct);
    final height = _l(fromRect.height, screenSize.height, ct);
    final radius = _l(24.0, 0.0, ct);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ready && renderer != null
            ? RTCVideoView(
                renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: true,
              )
            : Container(color: Colors.black),
      ),
    );
  }

  /// "等待加入" + 省略号动画
  ///
  /// 2 秒周期内："" → "." → ".." → "..." → "" → ...
  Widget _buildAnimatedTitle() {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, _) {
        // 将 2 秒分成 4 段，每段 0.5 秒
        final t = _dotsController.value; // 0.0 → 1.0
        String dots;
        if (t < 0.25) {
          dots = '';
        } else if (t < 0.5) {
          dots = '.';
        } else if (t < 0.75) {
          dots = '..';
        } else {
          dots = '...';
        }
        return Text(
          '等待加入$dots',
          style: styleTitle2.copyWith(color: colorTextPrimary),
        );
      },
    );
  }

  /// 全屏摄像头预览（填充整个屏幕作为背景）
  Widget _buildFullScreenCamera(RTCVideoRenderer? renderer, bool ready) {
    if (ready) {
      return RTCVideoView(
        renderer!,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: true, // 前置摄像头镜像
      );
    }

    // 摄像头未就绪时显示纯黑背景 + 摄像头图标
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_rounded,
              size: 48.0,
              color: Colors.white24,
            ),
            SizedBox(height: 12.0),
            Text(
              '摄像头准备中...',
              style: TextStyle(color: Colors.white38, fontSize: 14.0),
            ),
          ],
        ),
      ),
    );
  }

  /// 渐变光韵白边：边缘白 → 向内渐淡，约 30px 宽度，带呼吸动画
  ///
  /// 使用 RadialGradient 叠加：中心透明，越靠近边缘越白。
  /// stops 控制渐变范围，使得白色区域集中在边缘约 30px。
  Widget _buildGlowRing() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, _) {
        final strength = _glowAnimation.value; // 0.4 ~ 1.0
        return IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Colors.white.withAlpha((15 * strength).round()),
                  Colors.white.withAlpha((40 * strength).round()),
                  Colors.white.withAlpha((90 * strength).round()),
                ],
                stops: const [0.0, 0.78, 0.87, 0.94, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 计算真实剩余秒数（基于 roomCreatedAt）
  int get _remainingSeconds {
    final callState = ref.read(callProvider);
    final createdAt = callState.roomCreatedAt;
    if (createdAt == null) return roomTimeout.inSeconds;
    final elapsed = DateTime.now().difference(createdAt).inSeconds;
    final remaining = roomTimeout.inSeconds - elapsed;
    return remaining < 0 ? 0 : remaining;
  }

  /// 底部覆盖层：倒计时 + 超时提示 + 操作按钮
  Widget _buildBottomOverlay(String roomId) {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeString =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final isUrgent = _remainingSeconds < 60;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 倒计时
        Text(
          timeString,
          style: styleTitle3.copyWith(
            color: isUrgent ? colorDanger : Colors.white,
            fontWeight: isUrgent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),

        // 超时提醒（最后 60 秒显示）
        if (isUrgent)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              '房间即将超时关闭',
              style: styleSmall.copyWith(color: colorDanger),
            ),
          ),

        const SizedBox(height: 16.0),

        // 操作按钮
        _buildBottomActions(roomId),

        const SizedBox(height: 8.0),
      ],
    );
  }

  /// 底部按钮：邀请好友 + 退出房间
  Widget _buildBottomActions(String roomId) {
    final sdp = _offerSdp ?? _answerSdp;
    final isAnswer = _answerSdp != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Row(
        children: [
          // 邀请/分享按钮 → 弹出面板
          Expanded(
            flex: 3,
            child: GlassButton(
              label: isAnswer ? '分享回应码' : '邀请好友',
              icon: isAnswer ? Icons.qr_code_rounded : Icons.person_add_rounded,
              type: GlassButtonType.accent,
              onPressed: () => _showInvitePanel(roomId, offerSdp: sdp),
            ),
          ),
          const SizedBox(width: 12.0),
          // 退出房间
          Expanded(
            flex: 2,
            child: GlassButton(
              label: '退出房间',
              icon: Icons.call_end_rounded,
              type: GlassButtonType.danger,
              onPressed: () => _confirmExit(),
            ),
          ),
        ],
      ),
    );
  }

  /// 邀请面板：底部弹出，包含房间号 + 二维码
  void _showInvitePanel(String roomId, {String? offerSdp}) {
    showGlassBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _InvitePanel(
        roomId: roomId,
        offerSdp: offerSdp,
      ),
    );
  }

  Future<void> _confirmExit() async {
    final confirmed = await Dialogs.confirmExitRoom(context);
    if (confirmed) {
      ref.read(callProvider.notifier).cancelWaiting();
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 邀请面板（独立组件，toast 渲染在面板内部最上层）
// ═══════════════════════════════════════════════════════════

class _InvitePanel extends StatefulWidget {
  final String roomId;
  final String? offerSdp;

  const _InvitePanel({required this.roomId, this.offerSdp});

  @override
  State<_InvitePanel> createState() => _InvitePanelState();
}

class _InvitePanelState extends State<_InvitePanel> {
  bool _showToast = false;
  String _toastMessage = '';

  void _triggerToast(String message) {
    setState(() {
      _showToast = true;
      _toastMessage = message;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final roomId = widget.roomId;
    final formatted = roomId.length == 6
        ? '${roomId.substring(0, 3)} ${roomId.substring(3, 6)}'
        : roomId;

    // 确定 QR 数据：有 Offer SDP 就用 SDP 交换码（含房间号 + Offer）
    final qrData = widget.offerSdp != null
        ? 'clearcall://qr/${widget.roomId}/${_base64Encode(widget.offerSdp!)}'
        : 'clearcall://room/$roomId';
    final isSdpMode = widget.offerSdp != null;

    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: colorGlassBackground,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(radiusCard)),
          ),
          padding: EdgeInsets.only(
            left: paddingHorizontal,
            right: paddingHorizontal,
            top: paddingHorizontal,
            bottom:
                MediaQuery.of(context).viewInsets.bottom + paddingHorizontal,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽条
              Center(
                child: Container(
                  width: 36.0,
                  height: 4.0,
                  decoration: BoxDecoration(
                    color: colorNeutral.withAlpha(77),
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
              ),
              const SizedBox(height: 20.0),

              // 标题
              const Text('邀请好友加入', style: styleTitle2),
              const SizedBox(height: 4.0),
              Text(
                isSdpMode ? '让对方扫描此二维码即可建立连接' : '将以下信息分享给好友即可加入房间',
                style: styleSmall.copyWith(color: colorNeutral),
              ),
              const SizedBox(height: 24.0),

              // 房间号（大号 + 可复制）
              Text(
                '房间号',
                style: styleCaption.copyWith(color: colorNeutral),
              ),
              const SizedBox(height: 4.0),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: roomId));
                  _triggerToast('房间号已复制');
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatted,
                      style: styleLargeTitle.copyWith(
                        fontSize: 40.0,
                        letterSpacing: 6.0,
                        color: colorTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    const Icon(Icons.copy_rounded,
                        size: 18.0, color: colorNeutral),
                  ],
                ),
              ),
              const SizedBox(height: 20.0),

              // 二维码
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 180.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.circle,
                      color: colorTextPrimary,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: colorTextPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8.0),
              Text(
                isSdpMode ? '扫码交换 SDP 建立 P2P 连接' : '扫描二维码即可加入房间',
                style: styleSmall.copyWith(color: colorNeutral),
              ),
              const SizedBox(height: 20.0),

              // 复制房间号按钮
              SizedBox(
                width: double.infinity,
                child: GlassButton(
                  label: '复制房间号',
                  icon: Icons.copy_rounded,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: roomId));
                    _triggerToast('房间号已复制到剪贴板');
                  },
                ),
              ),

              // 如果 SDP 模式，显示提示
              if (isSdpMode) ...[
                const SizedBox(height: 12.0),
                SizedBox(
                  width: double.infinity,
                  child: GlassButton(
                    label: '扫描对方的回应码',
                    icon: Icons.qr_code_scanner_rounded,
                    type: GlassButtonType.accent,
                    onPressed: () {
                      Navigator.of(context).pop(); // 关闭面板
                      _RoomWaitingScreenState._scanAnswerQr?.call();
                    },
                  ),
                ),
              ],

              const SizedBox(height: 12.0),

              // 关闭按钮
              SizedBox(
                width: double.infinity,
                child: GlassButton(
                  label: '关闭',
                  icon: Icons.close_rounded,
                  type: GlassButtonType.normal,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 8.0),
            ],
          ),
        ),

        // ─── 顶部 toast（层级最高的复制确认）─────────────────
        if (_showToast)
          Positioned(
            top: 16.0,
            left: 24.0,
            right: 24.0,
            child: AnimatedOpacity(
              opacity: _showToast ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 12.0),
                decoration: BoxDecoration(
                  color: colorAccent.withAlpha(235),
                  borderRadius: BorderRadius.circular(radiusPill),
                  boxShadow: [
                    BoxShadow(
                      color: colorAccent.withAlpha(77),
                      blurRadius: 12.0,
                      offset: const Offset(0, 4.0),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 20.0),
                    const SizedBox(width: 8.0),
                    Flexible(
                      child: Text(
                        _toastMessage,
                        style: styleBody.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _base64Encode(String data) {
    // 使用 base64url 编码，避免 QR 码中出现特殊字符
    return base64Url.encode(utf8.encode(data));
  }
}
