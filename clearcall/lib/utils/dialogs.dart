import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../widgets/glass_dialog.dart';

/// 共享对话框工具
///
/// 消除 call_tab.dart 和 room_waiting_screen.dart 中的重复对话框代码。
class Dialogs {
  /// 退出房间确认弹窗
  static Future<bool> confirmExitRoom(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => GlassDialog(
        title: const Text('退出房间'),
        content: const Text('确定要关闭房间吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 流量提醒弹窗
  /// 返回 null = 取消, true = 继续, 'dont_ask' = 继续且不再提醒
  static Future<dynamic> showDataWarning(BuildContext context) async {
    return showDialog<dynamic>(
      context: context,
      builder: (ctx) => GlassDialog(
        title: const Text('流量提醒'),
        content: const Text(
          '您当前正在使用移动数据通话，可能会消耗较多流量。\n\n'
          '• 10 分钟通话约消耗 120 MB\n'
          '• 建议在 Wi-Fi 环境下使用以获得最佳体验',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续通话'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('dont_ask'),
            child: const Text('继续，不再提醒'),
          ),
        ],
      ),
    );
  }
}
