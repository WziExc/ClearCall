import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 磨砂 Scaffold 容器
///
/// 提供统一的 iOS 风格磨砂背景页面框架。
/// 背景使用系统灰白色（#F2F2F7），自动处理安全区域。
///
/// 使用示例：
/// ```dart
/// GlassScaffold(
///   title: 'ClearCall',
///   body: MyWidget(),
/// )
/// ```
class GlassScaffold extends StatelessWidget {
  /// 页面标题
  final String? title;

  /// 页面主体
  final Widget body;

  /// 标题栏右侧操作按钮（可选）
  final Widget? action;

  /// 底部导航栏（可选，用于 Tab 切换）
  final Widget? bottomNavigationBar;

  /// 是否显示返回按钮（默认 false）
  final bool showBackButton;

  /// 背景色（默认系统灰白）
  final Color backgroundColor;

  const GlassScaffold({
    super.key,
    this.title,
    required this.body,
    this.action,
    this.bottomNavigationBar,
    this.showBackButton = false,
    this.backgroundColor = colorBackground,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: title != null || action != null || showBackButton
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              leading: showBackButton
                  ? IconButton(
                      icon: const Icon(Icons.chevron_left, color: colorAccent, size: 32.0),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
              title: title != null
                  ? Text(title!, style: styleLargeTitle)
                  : null,
              actions: action != null ? [action!] : null,
            )
          : null,
      body: SafeArea(
        child: body,
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
