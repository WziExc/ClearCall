import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/call_record.dart';
import '../providers/call_history_provider.dart';
import '../providers/call_provider.dart';
import '../providers/settings_provider.dart';
import '../services/connectivity_service.dart';
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
          _buildCallHistorySection(context, ref),
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
              // 流量警告：首次移动数据通话弹出提示
              if (!await _checkDataWarning(context, ref)) return;
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

  /// 流量警告检测：首次移动数据通话弹出提示
  ///
  /// 返回 true 表示可以继续，false 表示用户取消。
  Future<bool> _checkDataWarning(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    if (settings.mobileWarningShown) return true;

    final isMobile = await ConnectivityService.isOnMobileData();
    if (!isMobile) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () async {
              await ref
                  .read(settingsProvider.notifier)
                  .saveAllSettings(settings.copyWith(mobileWarningShown: true));
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: const Text('继续，不再提醒'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 通话记录区块（从 sqflite 数据库加载）
  Widget _buildCallHistorySection(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(callHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('通话记录', style: styleTitle2),
        const SizedBox(height: 12.0),
        historyAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48.0),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => _buildEmptyState(),
          data: (records) {
            if (records.isEmpty) return _buildEmptyState();
            return _buildRecordList(context, ref, records);
          },
        ),
      ],
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return GlassCard(
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
              const Text('暂无通话记录', style: styleCaption),
              const SizedBox(height: 4.0),
              const Text(
                '创建或加入一个房间开始通话',
                style: styleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 通话记录列表
  Widget _buildRecordList(BuildContext context, WidgetRef ref, List<CallRecord> records) {
    return Column(
      children: records.map((record) {
        return GestureDetector(
          onLongPress: () => _confirmDeleteRecord(context, ref, record),
          child: GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // 方向图标
                  Container(
                    width: 40.0,
                    height: 40.0,
                    decoration: BoxDecoration(
                      color: record.answered
                          ? colorSuccess.withAlpha(30)
                          : colorDanger.withAlpha(30),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Icon(
                      record.direction == 'outgoing'
                          ? Icons.call_made_rounded
                          : Icons.call_received_rounded,
                      color: record.answered ? colorSuccess : colorDanger,
                      size: 20.0,
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.targetName,
                          style: styleCaption.copyWith(
                            color: colorTextPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          _formatRecordTime(record.startTime),
                          style: styleTiny.copyWith(color: colorNeutral),
                        ),
                      ],
                    ),
                  ),
                  // 时长
                  Text(
                    record.formattedDuration,
                    style: styleCaption.copyWith(color: colorNeutral),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 确认删除弹窗
  void _confirmDeleteRecord(BuildContext context, WidgetRef ref, CallRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条通话记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref
                  .read(callHistoryProvider.notifier)
                  .deleteRecord(record.id!);
            },
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 格式化时间显示
  String _formatRecordTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
