import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/constants.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';

/// 通话 Tab
///
/// 包含：本地摄像头预览占位、新建房间/加入房间按钮、通话记录列表（空状态）。
/// 阶段 1 为静态界面，实际功能在阶段 2 实现。
class CallTab extends ConsumerWidget {
  const CallTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8.0),

          // 摄像头预览占位区
          _buildCameraPreviewPlaceholder(),
          const SizedBox(height: 24.0),

          // 新建房间 / 加入房间 按钮组
          _buildRoomButtons(),
          const SizedBox(height: 32.0),

          // 通话记录区块
          _buildCallHistorySection(),
        ],
      ),
    );
  }

  /// 摄像头预览占位
  Widget _buildCameraPreviewPlaceholder() {
    return Center(
      child: Container(
        width: 160.0,
        height: 160.0,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorGlassBackground,
          border: Border.all(color: colorGlassBorder, width: 1.0),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_rounded,
              size: 48.0,
              color: colorNeutral.withAlpha(150),
            ),
            const SizedBox(height: 8.0),
            Text(
              '摄像头预览',
              style: styleSmall.copyWith(color: colorNeutral),
            ),
          ],
        ),
      ),
    );
  }

  /// 新建/加入房间按钮
  Widget _buildRoomButtons() {
    return Row(
      children: [
        Expanded(
          child: GlassButton(
            label: '新建房间',
            icon: Icons.add_rounded,
            onPressed: () {
              // TODO(阶段2): 实现新建房间逻辑
            },
          ),
        ),
        const SizedBox(width: 12.0),
        Expanded(
          child: GlassButton(
            label: '加入房间',
            icon: Icons.login_rounded,
            onPressed: () {
              // TODO(阶段2): 实现加入房间逻辑
            },
          ),
        ),
      ],
    );
  }

  /// 通话记录区块
  Widget _buildCallHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('通话记录', style: styleTitle2),
        const SizedBox(height: 12.0),

        // 空状态：无通话记录
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48.0),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 40.0,
                    color: colorNeutral.withAlpha(100),
                  ),
                  const SizedBox(height: 12.0),
                  const Text(
                    '暂无通话记录',
                    style: styleCaption,
                  ),
                  const SizedBox(height: 4.0),
                  const Text(
                    '创建或加入一个房间开始通话',
                    style: styleSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
