import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'glass_card.dart';

/// 统一状态组件集合
///
/// 提供三种标准状态组件：
/// - LoadingState：加载中（旋转指示器 + 文字）
/// - ErrorState：错误状态（图标 + 错误信息 + 重试按钮）
/// - EmptyState：空状态（图标 + 引导文案 + 可选操作按钮）

/// 加载状态组件
///
/// 居中显示 CircularProgressIndicator + 可选文字说明。
class LoadingState extends StatelessWidget {
  /// 加载提示文字
  final String? message;

  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36.0,
              height: 36.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colorAccent,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 16.0),
              Text(
                message!,
                style: styleCaption.copyWith(color: colorNeutral),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误状态组件
///
/// 居中显示错误图标 + 错误信息 + 可选重试按钮。
class ErrorState extends StatelessWidget {
  /// 错误信息
  final String message;

  /// 重试回调（为 null 时不显示重试按钮）
  final VoidCallback? onRetry;

  /// 自定义图标
  final IconData icon;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64.0, horizontal: paddingHorizontal),
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48.0, color: colorDanger.withAlpha(150)),
                const SizedBox(height: 16.0),
                Text(
                  message,
                  style: styleCaption.copyWith(color: colorTextPrimary),
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 24.0),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 20.0),
                    label: const Text('重试'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空状态组件
///
/// 居中显示图标 + 标题 + 引导文案 + 可选操作按钮。
class EmptyState extends StatelessWidget {
  /// 空状态图标
  final IconData icon;

  /// 标题文字（如"还没有好友"）
  final String title;

  /// 引导文案（如"扫码或点击 + 按钮添加好友"）
  final String subtitle;

  /// 操作按钮文字（为 null 时不显示按钮）
  final String? actionLabel;

  /// 操作按钮图标
  final IconData? actionIcon;

  /// 操作按钮回调
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64.0, horizontal: 24.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48.0, color: colorNeutral.withAlpha(100)),
                const SizedBox(height: 16.0),
                Text(title, style: styleCaption.copyWith(color: colorTextPrimary)),
                const SizedBox(height: 8.0),
                Text(
                  subtitle,
                  style: styleSmall,
                  textAlign: TextAlign.center,
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 24.0),
                  TextButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon ?? Icons.add_rounded, size: 20.0),
                    label: Text(actionLabel!),
                    style: TextButton.styleFrom(
                      foregroundColor: colorAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
