import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../widgets/responsive_wrapper.dart';
import 'call_tab.dart';
import 'profile_tab.dart';

/// 主界面 — Tab 导航框架
///
/// 底部 2 个 Tab：通话 / 我。
/// 胶囊形毛玻璃底部导航栏，模糊边缘。
/// Tab 切换使用淡入淡出 + 滑动过渡动效（250ms ease-out）。
/// 好友功能已合并到通话 Tab 左上角抽屉中。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  /// Tab 切换动画
  late final AnimationController _tabAnimController;
  late final Animation<double> _tabFadeAnimation;
  late final Animation<Offset> _tabSlideAnimation;

  /// 两个 Tab 页面
  final List<Widget> _tabs = const [
    CallTab(),
    ProfileTab(),
  ];

  /// 两个 Tab 标题
  static const List<String> _tabTitles = ['通话', '我'];

  /// 两个 Tab 图标
  static const List<IconData> _tabIcons = [
    Icons.videocam_rounded,
    Icons.person_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _tabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _tabFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _tabAnimController, curve: Curves.easeOut),
    );
    _tabSlideAnimation =
        Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _tabAnimController, curve: Curves.easeOut),
    );
    _tabAnimController.value = 1.0;
  }

  @override
  void dispose() {
    _tabAnimController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _tabAnimController.forward(from: 0.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorBackground,
      body: SafeArea(
        child: ResponsiveWrapper(
          child: FadeTransition(
            opacity: _tabFadeAnimation,
            child: SlideTransition(
              position: _tabSlideAnimation,
              child: _tabs[_currentIndex],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// 胶囊形毛玻璃底部导航栏
  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 12.0),
      height: 64.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32.0),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            decoration: BoxDecoration(
              color: colorGlassBackground,
              borderRadius: BorderRadius.circular(32.0),
              border: Border.all(
                color: Colors.white.withAlpha(80),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 20.0,
                  spreadRadius: 2.0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(2, (i) {
                final isSelected = i == _currentIndex;
                return _buildNavItem(
                  icon: _tabIcons[i],
                  label: _tabTitles[i],
                  isSelected: isSelected,
                  onTap: () => _onTabChanged(i),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  /// 单个导航项
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding:
            const EdgeInsets.symmetric(horizontal: 28.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isSelected
              ? colorAccent.withAlpha(25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22.0,
              color: isSelected ? colorAccent : colorNeutral,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8.0),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.0,
                  fontWeight: FontWeight.w600,
                  color: colorAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
