import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/call_provider.dart';
import '../utils/constants.dart';

/// 通话调试面板（开发者工具）
///
/// 在通话界面左上角显示实时技术指标：
/// - 通话阶段
/// - 参与者数量
/// - 房间号
/// - 通话时长
/// - 网络 RTT
/// - 媒体状态（静音/摄像头/扬声器）
///
/// 通过"我"Tab 设置页的"调试面板"开关控制显示。
class DebugPanel extends ConsumerWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callProvider);

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: colorBlack.withAlpha(200),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: colorWarning.withAlpha(100), width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('阶段', callState.phase.name),
          _row('参与者', '${callState.participants.length}'),
          if (callState.roomId != null) _row('房间', callState.roomId!),
          _row('时长', callState.formattedDuration),
          _row('麦克风', callState.isMuted ? '🔇 静音' : '🎤 开启'),
          _row('摄像头', callState.isCameraOn ? '📷 开启' : '📷 关闭'),
          _row('补光', callState.isFlashOn ? '💡 开启' : '💡 关闭'),
          _row('扬声器', callState.isSpeakerOn ? '🔊 外放' : '📱 听筒'),
          _row('镜头', callState.isFrontCamera ? '🤳 前置' : '📸 后置'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48.0,
            child: Text(
              label,
              style: styleTiny.copyWith(color: colorWarning),
            ),
          ),
          Text(
            value,
            style: styleTiny.copyWith(color: colorWhite),
          ),
        ],
      ),
    );
  }
}
