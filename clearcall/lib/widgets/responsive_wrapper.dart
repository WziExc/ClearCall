import 'package:flutter/material.dart';

/// 响应式布局包装器
///
/// 适配不同屏幕尺寸（小屏手机到平板）：
/// - 手机（< 600dp 宽）：全宽布局
/// - 平板（>= 600dp 宽）：居中最大宽度 500dp，两侧留白
///
/// 所有页面应使用此组件包裹内容。
///
/// 使用示例：
/// ```dart
/// ResponsiveWrapper(
///   child: MyPageContent(),
/// )
/// ```
class ResponsiveWrapper extends StatelessWidget {
  /// 子组件
  final Widget child;

  /// 平板模式最大宽度（默认 500dp）
  final double maxWidth;

  /// 是否仅在平板模式下限制宽度
  final bool onlyOnTablet;

  const ResponsiveWrapper({
    super.key,
    required this.child,
    this.maxWidth = 500.0,
    this.onlyOnTablet = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        // 手机屏幕：全宽
        if (onlyOnTablet && screenWidth < 600.0) {
          return child;
        }

        // 平板或宽屏：居中限制最大宽度
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

/// 响应式尺寸辅助类
///
/// 根据屏幕宽度计算合适的尺寸值。
class ResponsiveSize {
  final double screenWidth;

  const ResponsiveSize(this.screenWidth);

  /// 是否为大屏（平板）
  bool get isTablet => screenWidth >= 600.0;

  /// 是否为小屏手机（< 360dp）
  bool get isSmallPhone => screenWidth < 360.0;

  /// 根据屏幕宽度缩放值
  ///
  /// [base] 基准值（360dp 宽度下的值）
  /// 返回按比例缩放后的值，但不小于 [min]，不大于 [max]。
  double scale(double base, {double? min, double? max}) {
    final ratio = screenWidth / 360.0;
    final clampedRatio = ratio.clamp(
      (min ?? 0.8),
      (max ?? 1.5),
    );
    return base * clampedRatio;
  }
}
