import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'call_tab.dart';
import 'friends_tab.dart';
import 'profile_tab.dart';

/// 主界面 — Tab 导航框架
///
/// 底部 3 个 Tab：通话 / 好友 / 我
/// 磨砂风格底部导航栏，选中项蓝色高亮。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorBackground,
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _tabs,
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
        onTap: (index) => setState(() => _currentIndex = index),
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
