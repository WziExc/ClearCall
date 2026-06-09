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
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'call_screen.dart';

/// 房间等待页面
///
/// 创建或加入房间后显示。精简设计：
/// - 顶部标题 "等待加入" + 省略号循环动画（2 秒周期）
/// - 底部显示本地摄像头预览
/// - 底部显示倒计时 + 超时提示
/// - "邀请好友" / "退出房间" 按钮
///
/// 超时后自动回到首页并关闭房间。
class RoomWaitingScreen extends ConsumerStatefulWidget {
  const RoomWaitingScreen({super.key});

  @override
  ConsumerState<RoomWaitingScreen> createState() => _RoomWaitingScreenState();
}

class _RoomWaitingScreenState extends ConsumerState<RoomWaitingScreen>
    with TickerProviderStateMixin {
  /// 静态回调：供 _InvitePanel 点击"扫描对方的回应码"时调用
  static void Function()? _scanAnswerQr;

  late Timer _countdownTimer;
  int _remainingSeconds = roomTimeout.inSeconds;

  String? _offerSdp;
  String? _answerSdp;
  Timer? _sdpPollTimer;

  /// 省略号动画控制器（2 秒一个循环）
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();

    // 省略号动画：2 秒周期，循环往复
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // 倒计时
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          // 倒计时归零 → 强制关闭房间并返回首页
          _countdownTimer.cancel();
          _onTimeout();
        }
      });
    });

    // 扫码模式下主动准备 Offer SDP 供 QR 码展示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initQrFlow();
    });
  }

  @override
  void dispose() {
    _countdownTimer.cancel();
    _sdpPollTimer?.cancel();
    _dotsController.dispose();
    super.dispose();
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

    // 房间已结束 → 返回首页
    if (callState.phase == CallPhase.ended ||
        callState.phase == CallPhase.idle) {
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
    final localRenderer =
        ref.read(callProvider.notifier).getLocalRenderer();

    return Scaffold(
      backgroundColor: colorBackground,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8.0),

            // 顶部：返回 + 标题（省略号动画）
            _buildHeader(),

            const Spacer(),

            // 底部区域：摄像头预览 + 倒计时 + 按钮
            _buildBottomSection(roomId, localRenderer),

            const SizedBox(height: 24.0),
          ],
        ),
      ),
    );
  }

  /// 顶部标题栏（含省略号动画）
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Row(
        children: [
          // 返回箭头（回首页，保留房间）
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
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
          const SizedBox(width: 36.0), // 对称占位
        ],
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

  /// 底部区域：摄像头预览 + 倒计时 + 超时提示 + 操作按钮
  Widget _buildBottomSection(String roomId, RTCVideoRenderer? localRenderer) {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeString =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final isUrgent = _remainingSeconds < 60;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 摄像头预览（本地画面）
        _buildCameraPreview(localRenderer),

        const SizedBox(height: 12.0),

        // 倒计时
        Text(
          timeString,
          style: styleTitle3.copyWith(
            color: isUrgent ? colorDanger : colorTextPrimary,
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

  /// 摄像头预览（本地画面，圆角卡片样式）
  Widget _buildCameraPreview(RTCVideoRenderer? renderer) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radiusCard),
        child: Container(
          width: double.infinity,
          height: 180.0,
          decoration: BoxDecoration(
            color: colorBlack.withAlpha(20),
            borderRadius: BorderRadius.circular(radiusCard),
            border: Border.all(
              color: colorGlassBorder,
              width: 1.0,
            ),
          ),
          child: renderer != null && renderer.srcObject != null
              ? RTCVideoView(
                  renderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: true, // 前置摄像头镜像
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_rounded,
                        size: 40.0,
                        color: colorNeutral.withAlpha(100),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        '摄像头预览',
                        style: styleCaption.copyWith(color: colorNeutral),
                      ),
                    ],
                  ),
                ),
        ),
      ),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _InvitePanel(
        roomId: roomId,
        offerSdp: offerSdp,
      ),
    );
  }

  /// 确认退出弹窗
  void _confirmExit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出房间'),
        content: const Text('确定要关闭房间吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(callProvider.notifier).cancelWaiting();
            },
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('退出'),
          ),
        ],
      ),
    );
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
            bottom: MediaQuery.of(context).viewInsets.bottom + paddingHorizontal,
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
                    Icon(Icons.copy_rounded, size: 18.0, color: colorNeutral),
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
