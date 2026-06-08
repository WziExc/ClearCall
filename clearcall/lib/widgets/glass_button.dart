import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 磨砂按钮类型
enum GlassButtonType {
  /// 默认磨砂按钮（白色半透明背景）
  normal,

  /// 危险操作按钮（红色背景）
  danger,

  /// 强调按钮（蓝色背景）
  accent,
}

/// 磨砂按钮组件
///
/// iOS 风格胶囊形磨砂按钮，支持三种类型：
/// - normal：白色磨砂背景（默认）
/// - danger：红色背景（挂断、删除）
/// - accent：蓝色背景（接通、确认）
///
/// 按压时有 scale 0.95 缩放反馈。
///
/// 使用示例：
/// ```dart
/// GlassButton(
///   label: '新建房间',
///   icon: Icons.add,
///   onPressed: () => createRoom(),
/// )
/// ```
class GlassButton extends StatefulWidget {
  /// 按钮文字
  final String label;

  /// 按钮图标（可选）
  final IconData? icon;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 按钮类型
  final GlassButtonType type;

  /// 按钮宽度（null = 自适应内容）
  final double? width;

  /// 按钮高度（默认 56dp）
  final double height;

  /// 圆角半径（默认 50dp 胶囊形）
  final double borderRadius;

  /// 是否仅显示图标（无文字）
  final bool iconOnly;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.type = GlassButtonType.normal,
    this.width,
    this.height = buttonHeight,
    this.borderRadius = radiusPill,
    this.iconOnly = false,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _isPressed = false;

  Color get _backgroundColor {
    return switch (widget.type) {
      GlassButtonType.normal => colorGlassBackground,
      GlassButtonType.danger => colorDanger,
      GlassButtonType.accent => colorAccent,
    };
  }

  Color get _textColor {
    return switch (widget.type) {
      GlassButtonType.normal => colorTextPrimary,
      GlassButtonType.danger || GlassButtonType.accent => colorWhite,
    };
  }

  Color get _iconColor => _textColor;

  @override
  Widget build(BuildContext context) {
    // 按钮是否被禁用
    final isDisabled = widget.onPressed == null;

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => setState(() => _isPressed = true),
      onTapUp: isDisabled
          ? null
          : (_) {
              setState(() => _isPressed = false);
              widget.onPressed?.call();
            },
      onTapCancel: isDisabled ? null : () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          opacity: isDisabled ? 0.4 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurStrength / 2,
                sigmaY: blurStrength / 2,
              ),
              child: Container(
                width: widget.iconOnly ? widget.height : widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color: _isPressed
                      ? _backgroundColor.withAlpha(242) // ~0.95 opacity
                      : _backgroundColor,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: widget.type == GlassButtonType.normal
                      ? Border.all(color: colorGlassBorder, width: 1.0)
                      : null,
                ),
                child: widget.iconOnly
                    ? Icon(widget.icon, color: _iconColor, size: 28.0)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, color: _iconColor, size: 24.0),
                            const SizedBox(width: 8.0),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              style: styleBody.copyWith(
                                color: _textColor,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
