import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/call_provider.dart';
import '../utils/constants.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'call_screen.dart';

/// 房间等待页面
///
/// 创建或加入房间后显示。精简设计：
/// - 大号等待动画（脉动圆点）
/// - 倒计时
/// - "邀请好友"按钮 → 弹出二维码 + 房间号
/// - "退出房间"按钮
///
/// 按返回键 = 回到首页（房间保持活跃，可从首页横幅返回）
class RoomWaitingScreen extends ConsumerStatefulWidget {
  const RoomWaitingScreen({super.key});

  @override
  ConsumerState<RoomWaitingScreen> createState() => _RoomWaitingScreenState();
}

class _RoomWaitingScreenState extends ConsumerState<RoomWaitingScreen> {
  late Timer _countdownTimer;
  int _remainingSeconds = roomTimeout.inSeconds;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) _remainingSeconds--;
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer.cancel();
    super.dispose();
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

    return Scaffold(
      backgroundColor: colorBackground,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8.0),

            // 顶部：返回 + 标题
            _buildHeader(),

            const Spacer(flex: 2),

            // 中心：大号等待动画
            _buildWaitingCenter(),

            const Spacer(flex: 2),

            // 底部按钮
            _buildBottomActions(roomId),
            const SizedBox(height: 32.0),
          ],
        ),
      ),
    );
  }

  /// 顶部标题栏
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
          Text(
            '等待加入',
            style: styleTitle2.copyWith(color: colorTextPrimary),
          ),
          const Spacer(),
          const SizedBox(width: 36.0), // 对称占位
        ],
      ),
    );
  }

  /// 中心等待区：脉动圆点 + 倒计时
  Widget _buildWaitingCenter() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeString =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final isUrgent = _remainingSeconds < 60;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 大号脉动圆点
        _LargePulsingDot(isUrgent: isUrgent),
        const SizedBox(height: 24.0),
        Text(
          '等待好友加入...',
          style: styleTitle2.copyWith(color: colorTextPrimary),
        ),
        const SizedBox(height: 8.0),
        Text(
          timeString,
          style: styleCaption.copyWith(
            color: isUrgent ? colorDanger : colorNeutral,
            fontWeight: isUrgent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        if (isUrgent)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              '房间即将超时关闭',
              style: styleSmall.copyWith(color: colorDanger),
            ),
          ),
      ],
    );
  }

  /// 底部按钮：邀请好友 + 退出房间
  Widget _buildBottomActions(String roomId) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Row(
        children: [
          // 邀请好友 → 弹出面板
          Expanded(
            flex: 3,
            child: GlassButton(
              label: '邀请好友',
              icon: Icons.person_add_rounded,
              type: GlassButtonType.accent,
              onPressed: () => _showInvitePanel(roomId),
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
  void _showInvitePanel(String roomId) {
    final formatted = roomId.length == 6
        ? '${roomId.substring(0, 3)} ${roomId.substring(3, 6)}'
        : roomId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: colorGlassBackground,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusCard)),
        ),
        padding: EdgeInsets.only(
          left: paddingHorizontal,
          right: paddingHorizontal,
          top: paddingHorizontal,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + paddingHorizontal,
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
              '将以下信息分享给好友即可加入房间',
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('房间号已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
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
                  data: 'clearcall://room/$roomId',
                  version: QrVersions.auto,
                  size: 180.0,
                  backgroundColor: Colors.white,
                  foregroundColor: colorTextPrimary,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              '扫描二维码即可加入房间',
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('房间号已复制到剪贴板'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12.0),

            // 关闭按钮
            SizedBox(
              width: double.infinity,
              child: GlassButton(
                label: '关闭',
                icon: Icons.close_rounded,
                type: GlassButtonType.normal,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            const SizedBox(height: 8.0),
          ],
        ),
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

/// 大号脉动圆点动画
class _LargePulsingDot extends StatefulWidget {
  final bool isUrgent;
  const _LargePulsingDot({this.isUrgent = false});

  @override
  State<_LargePulsingDot> createState() => _LargePulsingDotState();
}

class _LargePulsingDotState extends State<_LargePulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.isUrgent ? colorDanger : colorAccent;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: 80.0,
            height: 80.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor.withAlpha((_pulseAnimation.value * 40).toInt()),
              border: Border.all(
                color: dotColor.withAlpha((_pulseAnimation.value * 100).toInt()),
                width: 3.0,
              ),
            ),
            child: Center(
              child: Container(
                width: 24.0,
                height: 24.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor.withAlpha(200),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
