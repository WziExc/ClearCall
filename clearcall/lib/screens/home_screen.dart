import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../widgets/responsive_wrapper.dart';
import 'call_tab.dart';
import 'friends_tab.dart';
import 'profile_tab.dart';

/// 主界面 — Tab 导航框架
///
/// 底部 3 个 Tab：通话 / 好友 / 我
/// 磨砂风格底部导航栏，选中项蓝色高亮。
/// Tab 切换使用淡入淡出 + 滑动过渡动效（250ms ease-out）。
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

  /// 三个 Tab 页面
  final List<Widget> _tabs = const [
    CallTab(),
    FriendsTab(),
    ProfileTab(),
  ];

  /// 三个 Tab 标题
  static const List<String> _tabTitles = ['通话', '好友', '我'];

  /// 三个 Tab 图标
  static const List<IconData> _tabIcons = [
    Icons.videocam_rounded,
    Icons.people_rounded,
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
    // 初始状态即完全显示
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
              child: IndexedStack(
                index: _currentIndex,
                children: _tabs,
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// 磨砂风格底部导航栏
  Widget _buildBottomNav() {
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabChanged,
        type: BottomNavigationBarType.fixed,
        backgroundColor: colorGlassBackground,
        selectedItemColor: colorAccent,
        unselectedItemColor: colorNeutral,
        selectedFontSize: 13.0,
        unselectedFontSize: 13.0,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
        elevation: 0,
        items: List.generate(3, (i) {
          return BottomNavigationBarItem(
            icon: Icon(_tabIcons[i], size: 24.0),
            activeIcon: Icon(_tabIcons[i], size: 24.0),
            label: _tabTitles[i],
          );
        }),
      ),
    );
  }
}
