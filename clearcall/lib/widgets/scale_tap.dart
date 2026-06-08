import 'package:flutter/material.dart';

/// 点击缩放反馈包装器
///
/// 包装任意子组件，点击时提供 scale 0.95 缩放反馈（100ms）。
/// 符合 UI 规范：按钮按压缩放反馈。
///
/// 使用示例：
/// ```dart
/// ScaleTap(
///   onTap: () => doSomething(),
///   child: Icon(Icons.add),
/// )
/// ```
class ScaleTap extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 点击回调
  final VoidCallback? onTap;

  /// 缩放比例（默认 0.95）
  final double scale;

  /// 动画时长（默认 100ms）
  final Duration duration;

  const ScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.95,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _isPressed = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _isPressed = false);
              widget.onTap?.call();
            },
      onTapCancel:
          widget.onTap == null ? null : () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? widget.scale : 1.0,
        duration: widget.duration,
        child: widget.child,
      ),
    );
  }
}
