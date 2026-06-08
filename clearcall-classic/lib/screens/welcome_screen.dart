import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../utils/constants.dart';
import '../utils/id_generator.dart';

/// 首次启动欢迎页
///
/// 流程：
/// 1. 显示 App 名称和 Logo（磨砂背景）
/// 2. 自动生成唯一 ID
/// 3. 输入昵称（可跳过）
/// 4. 保存设置 → AppRoot 自动切换到主界面"""
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  final _nicknameController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onGetStarted() {
    // 生成唯一 ID（如果还没有）
    final settings = ref.read(settingsProvider);
    if (settings.localId.isEmpty) {
      final localId = IdGenerator.generate();
      ref.read(settingsProvider.notifier).saveLocalId(localId);
    }

    // 保存昵称（如果输入了）
    final nickname = _nicknameController.text.trim();
    if (nickname.isNotEmpty) {
      ref.read(settingsProvider.notifier).updateNickname(nickname);
    }

    // 标记完成首次启动
    // 设置变更后 AppRoot 会自动重建并切换到 HomeScreen
    ref.read(settingsProvider.notifier).completeFirstLaunch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorBackground,
              Color(0xFFE8E8ED),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // App 图标（磨砂大圆形）
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32.0),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 120.0,
                        height: 120.0,
                        decoration: BoxDecoration(
                          color: colorGlassBackground,
                          borderRadius: BorderRadius.circular(32.0),
                          border: Border.all(color: colorGlassBorder),
                        ),
                        child: const Icon(
                          Icons.videocam_rounded,
                          size: 56.0,
                          color: colorAccent,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32.0),

                  // App 名称
                  const Text('ClearCall', style: styleLargeTitle),
                  const SizedBox(height: 8.0),
                  const Text(
                    '极简视频通话',
                    style: styleCaption,
                  ),

                  const SizedBox(height: 64.0),

                  // 昵称输入区
                  ClipRRect(
                    borderRadius: BorderRadius.circular(radiusCard),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 4.0,
                        ),
                        decoration: BoxDecoration(
                          color: colorGlassBackground,
                          borderRadius: BorderRadius.circular(radiusCard),
                          border: Border.all(color: colorGlassBorder),
                        ),
                        child: TextField(
                          controller: _nicknameController,
                          style: styleBody,
                          decoration: const InputDecoration(
                            hintText: '输入你的昵称（可跳过）',
                            hintStyle: styleCaption,
                            border: InputBorder.none,
                            icon: Icon(Icons.person_outline,
                                color: colorAccent, size: 24.0),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _onGetStarted(),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // 开始使用按钮
                  SizedBox(
                    width: double.infinity,
                    child: _GlassAccentButton(
                      label: '开始使用',
                      onPressed: _onGetStarted,
                    ),
                  ),

                  const SizedBox(height: 48.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 欢迎页专用磨砂强调按钮
class _GlassAccentButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _GlassAccentButton({
    required this.label,
    required this.onPressed,
  });

  @override
  State<_GlassAccentButton> createState() => _GlassAccentButtonState();
}

class _GlassAccentButtonState extends State<_GlassAccentButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radiusPill),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: buttonHeight,
              decoration: BoxDecoration(
                color: _isPressed
                    ? colorAccent.withAlpha(220)
                    : colorAccent,
                borderRadius: BorderRadius.circular(radiusPill),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                style: styleBody.copyWith(
                  color: colorWhite,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
