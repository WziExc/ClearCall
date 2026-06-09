import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 模糊背景弹窗 — 替代 AlertDialog
///
/// 内置 BackdropFilter 磨砂模糊效果，用法与 AlertDialog 完全一致。
/// 所有 showDialog 场景统一使用此组件。
class GlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;
  final Color? backgroundColor;
  final double? elevation;
  final ShapeBorder? shape;

  const GlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.contentPadding,
    this.actionsPadding,
    this.backgroundColor,
    this.elevation,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
      child: AlertDialog(
        title: title,
        content: content,
        actions: actions,
        contentPadding: contentPadding ??
            const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 24.0),
        actionsPadding: actionsPadding ?? EdgeInsets.zero,
        backgroundColor: backgroundColor ??
            colorGlassBackground.withAlpha(230),
        elevation: elevation ?? 0,
        shape: shape ??
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusCard),
            ),
      ),
    );
  }
}

/// 模糊底部弹出面板 — 替代 showModalBottomSheet
///
/// 内置 BackdropFilter 磨砂模糊效果，用法与 showModalBottomSheet 完全一致。
/// builder 返回的内容自动包裹在模糊层中。
Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    builder: (ctx) => BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
      child: builder(ctx),
    ),
  );
}
