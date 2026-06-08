import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/call_provider.dart';
import '../utils/constants.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'call_screen.dart';

/// 房间等待页面
///
/// 创建或加入房间后显示。展示：
/// - 大号房间号码（6 位）
/// - 二维码（可扫码加入）
/// - 等待动画
/// - 分享房间号按钮
/// - 取消按钮
class RoomWaitingScreen extends ConsumerStatefulWidget {
  const RoomWaitingScreen({super.key});

  @override
  ConsumerState<RoomWaitingScreen> createState() => _RoomWaitingScreenState();
}

class _RoomWaitingScreenState extends ConsumerState<RoomWaitingScreen> {
  /// 剩余超时秒数
  late Timer _countdownTimer;

  /// 剩余秒数
  int _remainingSeconds = roomTimeout.inSeconds;

  @override
  void initState() {
    super.initState();
    // 启动倒计时（每秒更新一次）
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        }
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

    // 如果通话已开始 → 跳转到通话界面
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

    // 如果已结束或出错，返回上一页
    if (callState.phase == CallPhase.ended ||
        callState.phase == CallPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
          if (callState.errorMessage != null) {
            _showErrorSnackBar(callState.errorMessage!);
          }
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
            const SizedBox(height: 16.0),

            // 顶部标题 + 取消按钮
            _buildHeader(),

            const Spacer(),

            // 房间号 + 二维码
            _buildRoomInfo(roomId),

            const SizedBox(height: spacingStandard),

            // 等待指示 + 倒计时
            _buildWaitingIndicator(),

            const Spacer(),

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
    return Row(
      children: [
        const SizedBox(width: paddingHorizontal),
        GestureDetector(
          onTap: () => _confirmCancel(),
          child: Container(
            width: 36.0,
            height: 36.0,
            decoration: BoxDecoration(
              color: colorGlassBackground,
              borderRadius: BorderRadius.circular(18.0),
            ),
            child: const Icon(
              Icons.close_rounded,
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
        // 对称占位
        const SizedBox(width: paddingHorizontal + 36.0),
      ],
    );
  }

  /// 房间号和二维码
  Widget _buildRoomInfo(String roomId) {
    return Column(
      children: [
        // 房间号标题
        Text(
          '房间号',
          style: styleCaption.copyWith(color: colorNeutral),
        ),
        const SizedBox(height: spacingCompact),
        Text(
          _formatRoomCode(roomId),
          style: styleLargeTitle.copyWith(
            fontSize: 48.0,
            letterSpacing: 8.0,
            color: colorTextPrimary,
          ),
        ),
        const SizedBox(height: 24.0),

        // 二维码
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: QrImageView(
              data: 'clearcall://room/$roomId',
              version: QrVersions.auto,
              size: 180.0,
              backgroundColor: Colors.white,
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
      ],
    );
  }

  /// 等待动画 + 倒计时
  Widget _buildWaitingIndicator() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeString =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    // 最后 60 秒变红警告
    final isUrgent = _remainingSeconds < 60;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PulsingDot(isUrgent: isUrgent),
        const SizedBox(width: spacingCompact),
        Text(
          '等待好友加入...',
          style: styleBody.copyWith(color: colorTextSecondary),
        ),
        const SizedBox(width: 4.0),
        Text(
          timeString,
          style: styleCaption.copyWith(
            color: isUrgent ? colorDanger : colorNeutral,
            fontWeight: isUrgent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  /// 底部按钮
  Widget _buildBottomActions(String roomId) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Row(
        children: [
          // 分享按钮
          Expanded(
            child: GlassButton(
              label: '分享房间号',
              icon: Icons.share_rounded,
              type: GlassButtonType.normal,
              onPressed: () {
                // TODO(阶段3): 分享房间号（系统分享面板）
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('房间号已复制到剪贴板'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12.0),
          // 取消按钮
          Expanded(
            child: GlassButton(
              label: '取消等待',
              icon: Icons.call_end_rounded,
              type: GlassButtonType.danger,
              onPressed: () => _confirmCancel(),
            ),
          ),
        ],
      ),
    );
  }

  /// 确认取消弹窗
  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消等待'),
        content: const Text('确定要取消等待并关闭房间吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('继续等待'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(callProvider.notifier).cancelWaiting();
            },
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 显示错误提示
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colorDanger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 格式化房间号（每 3 位加空格）
  String _formatRoomCode(String code) {
    if (code.length != 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3, 6)}';
  }
}

/// 脉动圆点动画（等待指示器）
class _PulsingDot extends StatefulWidget {
  final bool isUrgent;
  const _PulsingDot({this.isUrgent = false});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
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
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 10.0,
        height: 10.0,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isUrgent ? colorDanger : colorAccent,
        ),
      ),
    );
  }
}
