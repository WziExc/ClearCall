import 'package:flutter/material.dart';

import 'utils/constants.dart';

/// ClearCall MaterialApp 配置
///
/// 全局主题、路由、字体等初始化。
/// 主题完全对齐 03-ui-design-spec.md 的色彩系统。
class ClearCallApp extends StatelessWidget {
  /// 根据设置状态决定显示欢迎页或主界面
  final Widget home;

  const ClearCallApp({
    super.key,
    required this.home,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClearCall',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: home,
      // 不在阶段 1 配置路由，导航采用 Navigator.push 直接跳转
    );
  }

  /// 构建全局主题
  ThemeData _buildTheme() {
    return ThemeData(
      // 色彩
      primaryColor: colorAccent,
      scaffoldBackgroundColor: colorBackground,
      colorScheme: const ColorScheme.light(
        primary: colorAccent,
        secondary: colorAccent,
        surface: colorBackground,
        error: colorDanger,
      ),

      // 字体
      fontFamily: 'System', // 使用系统默认无衬线字体（对齐 iOS 风格）
      textTheme: const TextTheme(
        headlineLarge: styleLargeTitle,
        headlineMedium: styleTitle1,
        titleLarge: styleTitle2,
        titleMedium: styleTitle3,
        bodyLarge: styleBody,
        bodyMedium: styleCaption,
        bodySmall: styleSmall,
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: styleLargeTitle,
        iconTheme: IconThemeData(color: colorAccent),
      ),

      // 底部导航栏
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: colorGlassBackground,
        selectedItemColor: colorAccent,
        unselectedItemColor: colorNeutral,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // 卡片
      cardTheme: CardThemeData(
        color: colorGlassBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),

      // 分割线
      dividerTheme: const DividerThemeData(
        color: colorDivider,
        thickness: 1.0,
        space: 0,
      ),

      // 图标
      iconTheme: const IconThemeData(
        color: colorAccent,
        size: 24.0,
      ),
    );
  }
}
