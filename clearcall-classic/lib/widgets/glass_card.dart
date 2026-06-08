import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 磨砂卡片组件
///
/// iOS 风格半透明磨砂效果卡片。
/// 使用 BackdropFilter 实现高斯模糊 + 半透明白色背景。
///
/// 使用示例：
/// ```dart
/// GlassCard(
///   child: Padding(
///     padding: const EdgeInsets.all(16.0),
///     child: Text('卡片内容'),
///   ),
/// )
/// ```
class GlassCard extends StatelessWidget {
  /// 卡片子组件
  final Widget child;

  /// 圆角半径（默认 16dp）
  final double borderRadius;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 外边距
  final EdgeInsetsGeometry? margin;

  /// 卡片宽度（可选）
  final double? width;

  /// 卡片高度（可选）
  final double? height;

  /// 模糊强度（默认 20px）
  final double blurStrength;

  /// 背景透明度（0.0 ~ 1.0，默认 0.8）
  final double backgroundOpacity;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = radiusCard,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.blurStrength = 20.0,
    this.backgroundOpacity = 0.8,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: colorGlassBackground.withAlpha((255 * backgroundOpacity).round()),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: colorGlassBorder,
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    // 有模糊强度 → 包裹 BackdropFilter
    if (blurStrength > 0) {
      final blurred = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurStrength / 2,
            sigmaY: blurStrength / 2,
          ),
          child: card,
        ),
      );

      if (margin != null) {
        return Padding(padding: margin!, child: blurred);
      }
      return blurred;
    }

    if (margin != null) {
      return Padding(padding: margin!, child: card);
    }
    return card;
  }
}
