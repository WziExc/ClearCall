import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend.dart';
import '../providers/call_provider.dart';
import '../providers/friend_provider.dart';
import '../providers/settings_provider.dart';
import '../services/connectivity_service.dart';
import '../utils/constants.dart';
import '../widgets/color_avatar.dart';
import '../widgets/glass_card.dart';
import 'add_friend_screen.dart';

/// 好友 Tab
///
/// 包含：搜索栏、添加按钮、好友请求提示、好友列表。
/// 点击在线好友可发起通话，长按可删除。
class FriendsTab extends ConsumerWidget {
  const FriendsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendState = ref.watch(friendProvider);
    final callState = ref.watch(callProvider);

    // 如果正在通话中，不显示完整好友列表
    if (callState.phase == CallPhase.inCall ||
        callState.phase == CallPhase.waiting ||
        callState.phase == CallPhase.ringing) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 搜索栏 + 添加按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(
              paddingHorizontal, 8.0, paddingHorizontal, 0),
          child: _buildSearchBar(ref),
        ),
        const SizedBox(height: spacingCompact),

        // 好友请求提示
        if (friendState.pendingCount > 0)
          _buildFriendRequestBanner(context, ref, friendState.pendingRequests),

        // 好友列表
        Expanded(
          child: friendState.isLoading
              ? _buildLoadingState()
              : friendState.filteredFriends.isEmpty
                  ? _buildEmptyState(friendState.searchQuery.isNotEmpty)
                  : _buildFriendList(context, ref, friendState),
        ),
      ],
    );
  }

  /// 搜索栏
  Widget _buildSearchBar(WidgetRef ref) {
    final query = ref.watch(friendProvider).searchQuery;
    final controller = TextEditingController(text: query);

    return Row(
      children: [
        // 搜索框
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radiusListItem),
            child: Container(
              height: 44.0,
              decoration: BoxDecoration(
                color: colorGlassBackground,
                borderRadius: BorderRadius.circular(radiusListItem),
                border: Border.all(color: colorGlassBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 20.0, color: colorNeutral),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      style: styleCaption,
                      decoration: const InputDecoration(
                        hintText: '搜索好友',
                        hintStyle: styleCaption,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (value) {
                        ref
                            .read(friendProvider.notifier)
                            .updateSearchQuery(value);
                      },
                    ),
                  ),
                  if (query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        ref
                            .read(friendProvider.notifier)
                            .updateSearchQuery('');
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 18.0, color: colorNeutral),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12.0),
        // 添加好友按钮
        Builder(
          builder: (context) => GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AddFriendScreen(),
                ),
              );
            },
            child: Container(
              width: 44.0,
              height: 44.0,
              decoration: BoxDecoration(
                color: colorAccent,
                borderRadius: BorderRadius.circular(radiusListItem),
              ),
              child: const Icon(Icons.person_add_rounded,
                  color: colorWhite, size: 22.0),
            ),
          ),
        ),
      ],
    );
  }

  /// 好友请求横幅
  Widget _buildFriendRequestBanner(
    BuildContext context,
    WidgetRef ref,
    List<FriendRequest> requests,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          paddingHorizontal, 4.0, paddingHorizontal, 0),
      child: GestureDetector(
        onTap: () => _showFriendRequestsSheet(context, ref, requests),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: colorAccent.withAlpha(25),
            borderRadius: BorderRadius.circular(radiusListItem),
            border: Border.all(color: colorAccent.withAlpha(77)),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_add_rounded,
                  color: colorAccent, size: 20.0),
              const SizedBox(width: spacingCompact),
              Text(
                '${requests.length} 个待处理的好友申请',
                style: styleCaption.copyWith(color: colorAccent),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  color: colorAccent, size: 20.0),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部弹出好友申请列表
  void _showFriendRequestsSheet(
    BuildContext context,
    WidgetRef ref,
    List<FriendRequest> requests,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: colorGlassBackground,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusCard)),
        ),
        padding: const EdgeInsets.all(paddingHorizontal),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽条
            Center(
              child: Container(
                width: 36.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: colorNeutral.withAlpha(77),
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            const Text('好友申请', style: styleTitle2),
            const SizedBox(height: 12.0),
            ...requests.map((req) => _buildRequestItem(ctx, ref, req)),
            const SizedBox(height: 16.0),
          ],
        ),
      ),
    );
  }

  /// 单个好友申请项
  Widget _buildRequestItem(
    BuildContext ctx,
    WidgetRef ref,
    FriendRequest request,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: colorGlassBackground,
        borderRadius: BorderRadius.circular(radiusListItem),
        border: Border.all(color: colorGlassBorder),
      ),
      child: Row(
        children: [
          ColorAvatar(nickname: request.nickname, size: 44.0),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.nickname, style: styleCaption),
                const SizedBox(height: 2.0),
                Text(
                  'ID: ${request.fromUid.substring(0, 8)}...',
                  style: styleSmall,
                ),
              ],
            ),
          ),
          // 拒绝按钮
          TextButton(
            onPressed: () {
              ref
                  .read(friendProvider.notifier)
                  .rejectFriendRequest(request.fromUid);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('拒绝'),
          ),
          const SizedBox(width: 8.0),
          // 同意按钮
          TextButton(
            onPressed: () {
              ref
                  .read(friendProvider.notifier)
                  .acceptFriendRequest(request.fromUid);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: colorAccent),
            child: const Text('同意'),
          ),
        ],
      ),
    );
  }

  /// 好友列表
  Widget _buildFriendList(
    BuildContext context,
    WidgetRef ref,
    FriendState friendState,
  ) {
    final friends = friendState.filteredFriends;

    // 排序：在线/通话中排在前面
    final sortedFriends = List<Friend>.from(friends)
      ..sort((a, b) {
        final aScore = a.status == OnlineStatus.online
            ? 0
            : a.status == OnlineStatus.inCall
                ? 1
                : 2;
        final bScore = b.status == OnlineStatus.online
            ? 0
            : b.status == OnlineStatus.inCall
                ? 1
                : 2;
        return aScore.compareTo(bScore);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      itemCount: sortedFriends.length,
      itemBuilder: (context, index) {
        final friend = sortedFriends[index];
        return _buildFriendItem(context, ref, friend);
      },
    );
  }

  /// 单个好友项
  Widget _buildFriendItem(
    BuildContext context,
    WidgetRef ref,
    Friend friend,
  ) {
    final isOffline = friend.status == OnlineStatus.offline;

    return GestureDetector(
      onTap: () {
        // 在线好友可呼叫
        if (friend.isOnline && !friend.isInCall) {
          _callFriend(context, ref, friend);
        } else if (friend.isInCall) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('对方正在通话中')),
          );
        }
      },
      onLongPress: () => _confirmDeleteFriend(context, ref, friend),
      child: Opacity(
        opacity: isOffline ? 0.5 : 1.0,
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // 在线状态 + 头像
                Stack(
                  children: [
                    ColorAvatar(
                      nickname: friend.nickname,
                      size: 48.0,
                      borderRadius: radiusAvatarList,
                    ),
                    // 在线状态小圆点
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: indicatorDiameter,
                        height: indicatorDiameter,
                        decoration: BoxDecoration(
                          color: friend.isInCall
                              ? colorWarning
                              : friend.isOnline
                                  ? colorSuccess
                                  : colorNeutral,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: colorWhite, width: 2.0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12.0),
                // 昵称 + 状态
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friend.nickname,
                        style: styleBody.copyWith(
                          color: colorTextPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        friend.isInCall
                            ? '通话中'
                            : friend.isOnline
                                ? '在线'
                                : '离线',
                        style: styleTiny.copyWith(
                          color: friend.isInCall
                              ? colorWarning
                              : friend.isOnline
                                  ? colorSuccess
                                  : colorNeutral,
                        ),
                      ),
                    ],
                  ),
                ),
                // 通话按钮
                if (friend.isOnline && !friend.isInCall)
                  IconButton(
                    icon: const Icon(Icons.videocam_rounded,
                        color: colorAccent, size: 24.0),
                    onPressed: () => _callFriend(context, ref, friend),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 呼叫好友
  Future<void> _callFriend(
    BuildContext context,
    WidgetRef ref,
    Friend friend,
  ) async {
    // 流量警告
    final settings = ref.read(settingsProvider);
    if (!settings.mobileWarningShown) {
      final isMobile = await ConnectivityService.isOnMobileData();
      if (isMobile && context.mounted) {
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
                  await ref.read(settingsProvider.notifier).saveAllSettings(
                      settings.copyWith(mobileWarningShown: true));
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                },
                child: const Text('继续，不再提醒'),
              ),
            ],
          ),
        );
        if (result != true) return;
      }
    }

    // 发起好友呼叫
    if (context.mounted) {
      try {
        await ref.read(callProvider.notifier).startFriendCall(
              friend.uid,
              friend.nickname,
            );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('发起呼叫失败: $e'),
              backgroundColor: colorDanger,
            ),
          );
        }
      }
    }
  }

  /// 确认删除好友
  void _confirmDeleteFriend(
    BuildContext context,
    WidgetRef ref,
    Friend friend,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定要删除"${friend.nickname}"吗？\n删除后双方将从好友列表中移除对方。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(friendProvider.notifier).removeFriend(friend.uid);
            },
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 加载中
  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 64.0),
        child: CircularProgressIndicator(),
      ),
    );
  }

  /// 空状态（无好友 或 搜索无结果）
  Widget _buildEmptyState(bool isSearching) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSearching
                      ? Icons.search_off_rounded
                      : Icons.people_outline_rounded,
                  size: 48.0,
                  color: colorNeutral.withAlpha(100),
                ),
                const SizedBox(height: 16.0),
                Text(
                  isSearching ? '未找到匹配的好友' : '还没有好友',
                  style: styleCaption,
                ),
                const SizedBox(height: 8.0),
                Text(
                  isSearching
                      ? '试试其他关键词'
                      : '扫码或点击 + 按钮添加好友\n即可开始视频通话',
                  style: styleSmall,
                  textAlign: TextAlign.center,
                ),
                if (!isSearching) ...[
                  const SizedBox(height: 24.0),
                  Text(
                    '点击右上角 + 添加好友',
                    style: styleSmall.copyWith(color: colorAccent),
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
