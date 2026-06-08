import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/call_provider.dart';
import '../utils/constants.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import 'join_room_screen.dart';
import 'room_waiting_screen.dart';

/// 通话 Tab
///
/// 包含：摄像头预览占位、新建房间/加入房间按钮、通话记录列表（空状态）。
class CallTab extends ConsumerWidget {
  const CallTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callProvider);

    // 如果正在 waiting 或 inCall → 显示通话状态（不显示 Tab 内容）
    if (callState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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
          _buildRoomButtons(context, ref),
          const SizedBox(height: 32.0),

          // 错误提示
          if (callState.errorMessage != null)
            _buildErrorBanner(callState.errorMessage!),

          const SizedBox(height: 16.0),

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
  Widget _buildRoomButtons(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: GlassButton(
            label: '新建房间',
            icon: Icons.add_rounded,
            onPressed: () async {
              // 创建房间并跳转到等待页
              await ref.read(callProvider.notifier).createRoom();
              final state = ref.read(callProvider);
              if (state.phase == CallPhase.waiting && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RoomWaitingScreen(),
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 12.0),
        Expanded(
          child: GlassButton(
            label: '加入房间',
            icon: Icons.login_rounded,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const JoinRoomScreen(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 错误提示
  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: colorDanger.withAlpha(25),
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colorDanger.withAlpha(77)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: colorDanger, size: 20.0),
          const SizedBox(width: spacingCompact),
          Expanded(
            child: Text(
              message,
              style: styleCaption.copyWith(color: colorDanger),
            ),
          ),
        ],
      ),
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
