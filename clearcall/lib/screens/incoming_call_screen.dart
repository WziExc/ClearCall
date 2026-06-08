import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/call_provider.dart';
import '../services/ringtone_service.dart';
import '../utils/constants.dart';
import '../widgets/color_avatar.dart';
import 'call_screen.dart';

/// 来电接听界面
///
/// 全屏显示，包含：
/// - 磨砂背景 + 来电者头像和昵称
/// - 绿色的接听按钮（滑动接听）
/// - 红色的挂断按钮
/// - 铃声音效播放
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() =>
      _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // 播放铃声音效
    RingtoneService.startRinging();

    // 动画控制器
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    );

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final callerName = callState.incomingCallerName ?? '未知来电';

    // 如果来电状态已清除，自动返回
    if (!callState.hasIncomingCall) {
      // 延迟 pop 以避免在 build 中直接操作导航
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1C1C1E),
              Color(0xFF2C2C2E),
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    50 * (1 - _slideAnimation.value),
                  ),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // 来电标签
                const Text(
                  '视频来电',
                  style: TextStyle(
                    fontSize: 17.0,
                    color: colorNeutral,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 32.0),

                // 来电者头像
                ColorAvatar(
                  nickname: callerName,
                  size: 100.0,
                  borderRadius: 40.0,
                ),
                const SizedBox(height: 24.0),

                // 来电者昵称
                Text(
                  callerName,
                  style: const TextStyle(
                    fontSize: 28.0,
                    fontWeight: FontWeight.w700,
                    color: colorWhite,
                  ),
                ),
                const SizedBox(height: 8.0),
                const Text(
                  'ClearCall 视频通话',
                  style: TextStyle(
                    fontSize: 15.0,
                    color: colorNeutral,
                  ),
                ),

                const Spacer(flex: 2),

                // 操作按钮组
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: paddingHorizontal),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 挂断按钮
                      _buildActionButton(
                        icon: Icons.call_end_rounded,
                        label: '拒绝',
                        color: colorDanger,
                        onPressed: _onReject,
                      ),
                      const SizedBox(width: 48.0),
                      // 接听按钮
                      _buildActionButton(
                        icon: Icons.videocam_rounded,
                        label: '接听',
                        color: colorSuccess,
                        onPressed: _onAccept,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 64.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 72.0,
            height: 72.0,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(77),
                  blurRadius: 16.0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: colorWhite, size: 36.0),
          ),
        ),
        const SizedBox(height: 8.0),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.0,
            color: colorNeutral,
          ),
        ),
      ],
    );
  }

  /// 接听
  void _onAccept() async {
    RingtoneService.stopRinging();
    try {
      await ref.read(callProvider.notifier).answerIncomingCall();

      if (mounted) {
        // 关闭来电界面，打开通话界面
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const CallScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('接听失败: $e'),
            backgroundColor: colorDanger,
          ),
        );
      }
    }
  }

  /// 拒绝
  void _onReject() async {
    RingtoneService.stopRinging();
    RingtoneService.playHangupSound();
    try {
      await ref.read(callProvider.notifier).rejectIncomingCall();
    } catch (_) {
      // 无论成功与否都关闭界面
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
