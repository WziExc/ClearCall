import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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

    // 设置扫码回调（创建方扫描加入方的回应码）
    _scanAnswerQr = _handleScanAnswerQr;

    // 第一帧后：启动入场动画 + 创建房间（QR 流程由 _tryCreateRoom 内部触发）
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
      // 非创建方（加入方/MobileScanner 跳转）：直接启动 QR 轮询
      if (!widget.createOnEnter) {
        _initQrFlow();
      }
    });
  }

  /// 扫描对方回应码（创建方扫描加入方的 Answer QR）
  void _handleScanAnswerQr() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AnswerQrScanner(
          onScanned: (sdp) {
            final signaling = ref.read(signalingProvider);
            if (signaling is QrSignaling) {
              signaling.injectRemoteAnswer(sdp);
            }
          },
        ),
      ),
    );
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
  /// 流程：等待入场动画完成 → 预检服务器（WebSocket 模式）→
  /// 释放共享摄像头 → createRoom() → 成功后清理共享渲染器。
  /// 服务器不可达时不释放摄像头，直接返回 CallTab。
  Future<void> _tryCreateRoom() async {
    if (!widget.createOnEnter || _createStarted) return;

    _createStarted = true;

    // 等待入场缩放动画完成
    if (widget.fromRect != null && _enterController.isAnimating) {
      await _enterController.forward();
      if (mounted) setState(() => _enterComplete = true);
    }

    // 🔑 预检：WebSocket 模式下先确认服务器可达（2 秒超时，不释放摄像头）
    final signaling = ref.read(signalingProvider);
    if (signaling is! QrSignaling) {
      final available = await signaling.isAvailable();
      if (!mounted) return;
      if (!available) {
        setState(() => _createStarted = false);
        // 显示提示后返回 CallTab（摄像头未曾释放，预览完好）
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('信令服务器不可达，请切换到「QR 扫码」模式\n（设置 → 其他 → 信令服务 → QR 扫码）'),
              backgroundColor: colorDanger,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    // 服务器可达 → 释放共享摄像头硬件（保留渲染器最后一帧）
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

      // 🔑 QR 模式：createRoom 后生成 Offer SDP 供 QR 编码
      if (ref.read(signalingProvider) is QrSignaling) {
        await ref.read(callProvider.notifier).prepareQrOffer();
        if (mounted) {
          final qr = ref.read(signalingProvider);
          if (qr is QrSignaling && qr.offerSdpForQr != null) {
            setState(() => _offerSdp = qr.offerSdpForQr);
          }
          // 创建方 QR 流程初始化（Offer 已就绪 → 设置轮询等待对方 Answer）
          _initQrFlow();
        }
      }

      // WebRTC 已就绪 → 清理共享渲染器
      await Future.delayed(const Duration(milliseconds: 150));
      await widget.onCleanupRenderer?.call();
    } catch (_) {
      // 创建失败 → 返回 CallTab
      // 先清除 errorMessage（防止 shouldPop 再次触发 popUntil），设 _isExiting 抑制退场逻辑
      if (mounted) {
        ref.read(callProvider.notifier).dismissEndReport();
        _isExiting = true;
        Navigator.of(context).pop();
      }
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

  /// 初始化 QR 流程：创建方已生成 Offer，加入方轮询 Answer
  Future<void> _initQrFlow() async {
    final signaling = ref.read(signalingProvider);
    if (signaling is! QrSignaling) return;

    // 创建方：Offer SDP 已在 _tryCreateRoom 中生成
    if (signaling.offerSdpForQr != null) {
      if (_offerSdp == null && mounted) {
        setState(() => _offerSdp = signaling.offerSdpForQr);
      }
      // 同时启动轮询，等待对方扫码后生成的 Answer
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

    // 加入方：轮询等待 Answer SDP 生成（由 injectRemoteOffer 触发）
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
          // 摄像头切换按钮（有多个摄像头时显示）
          _buildCameraSwitchButton(),
        ],
      ),
    );
  }

  /// 摄像头切换按钮（可用摄像头 > 1 时显示）
  Widget _buildCameraSwitchButton() {
    final callState = ref.watch(callProvider);
    final cameras = callState.availableCameras;

    if (cameras.length <= 1) return const SizedBox(width: 36.0);

    return GestureDetector(
      onTap: () => _showCameraPicker(context),
      child: Container(
        width: 36.0,
        height: 36.0,
        decoration: BoxDecoration(
          color: colorGlassBackground,
          borderRadius: BorderRadius.circular(18.0),
        ),
        child: const Icon(
          Icons.cameraswitch_rounded,
          color: colorTextPrimary,
          size: 20.0,
        ),
      ),
    );
  }

  /// 弹出摄像头选择列表
  void _showCameraPicker(BuildContext context) {
    final callState = ref.read(callProvider);
    final cameras = callState.availableCameras;
    final selectedId = callState.selectedCameraId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: colorGlassBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCard)),
        ),
        padding: const EdgeInsets.all(paddingHorizontal),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 16.0),
            const Text('选择摄像头', style: styleTitle2),
            const SizedBox(height: 12.0),
            ...cameras.map((c) => ListTile(
                  leading: Icon(
                    c.isFront ? Icons.camera_front_rounded : Icons.camera_rear_rounded,
                    color: c.deviceId == selectedId ? colorAccent : colorNeutral,
                  ),
                  title: Text(c.displayLabel, style: styleBody),
                  trailing: c.deviceId == selectedId
                      ? const Icon(Icons.check_circle_rounded, color: colorAccent, size: 20.0)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ref.read(callProvider.notifier).switchToCamera(c.deviceId);
                  },
                )),
            const SizedBox(height: 16.0),
          ],
        ),
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
  ///
  /// [ready] 时显示摄像头画面，[cameraError] 时显示异常提示+重试，
  /// 未就绪时显示纯黑背景（极简，无文字）。
  Widget _buildFullScreenCamera(RTCVideoRenderer? renderer, bool ready) {
    final callState = ref.watch(callProvider);
    final isDenied = callState.cameraStatus == CameraStatus.permissionDenied;

    if (ready) {
      return RTCVideoView(
        renderer!,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: true,
      );
    }

    // 权限拒绝 → 提示去设置
    if (isDenied) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_rounded, size: 48.0, color: Colors.white24),
              const SizedBox(height: 12.0),
              const Text('摄像头权限未授予', style: TextStyle(color: Colors.white38, fontSize: 14.0)),
              const SizedBox(height: 16.0),
              GestureDetector(
                onTap: () {
                  // 重试摄像头
                  if (widget.createOnEnter) {
                    setState(() {
                      _createStarted = false;
                      _roomCreated = false;
                    });
                    _tryCreateRoom();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: colorAccent.withAlpha(60),
                    borderRadius: BorderRadius.circular(radiusPill),
                  ),
                  child: const Text('重试', style: TextStyle(color: colorWhite, fontSize: 14.0)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 异常或初始化中 → 纯黑（极致简洁）
    return Container(color: Colors.black);
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

// ═══════════════════════════════════════════════════════════
// Answer QR 扫描器 — 创建方扫描加入方的回应码
// ═══════════════════════════════════════════════════════════

class _AnswerQrScanner extends StatelessWidget {
  final ValueChanged<String> onScanned;
  const _AnswerQrScanner({required this.onScanned});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: colorWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('扫描对方的回应码', style: TextStyle(color: colorWhite)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull;
                if (barcode != null && barcode.rawValue != null) {
                  final raw = barcode.rawValue!;
                  if (raw.startsWith('clearcall://qr/')) {
                    // 静音扫描音（不需要）
                    try {
                      final uri = Uri.parse(raw);
                      final sdpBase64 = uri.pathSegments[2];
                      final sdp = utf8.decode(base64Url.decode(sdpBase64));
                      Navigator.of(context).pop();
                      onScanned(sdp);
                    } catch (_) {}
                  }
                }
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Text(
              '将对方屏幕上的二维码放入框内',
              style: TextStyle(color: colorNeutral, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
