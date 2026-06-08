import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/constants.dart';
import '../widgets/glass_card.dart';

/// 好友 Tab
///
/// 包含：搜索栏、添加按钮、好友列表（空状态引导）。
/// 阶段 1 为静态界面，实际功能在阶段 3 实现。
class FriendsTab extends ConsumerWidget {
  const FriendsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 搜索栏 + 添加按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(
              paddingHorizontal, 8.0, paddingHorizontal, 0),
          child: _buildSearchBar(),
        ),
        const SizedBox(height: 16.0),

        // 好友列表
        Expanded(child: _buildFriendList()),
      ],
    );
  }

  /// 搜索栏
  Widget _buildSearchBar() {
    return Row(
      children: [
        // 搜索框
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: Container(
              height: 44.0,
              decoration: BoxDecoration(
                color: colorGlassBackground,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: colorGlassBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded,
                      size: 20.0, color: colorNeutral),
                  SizedBox(width: 8.0),
                  Text(
                    '搜索好友',
                    style: styleCaption,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 12.0),

        // 添加好友按钮
        Container(
          width: 44.0,
          height: 44.0,
          decoration: BoxDecoration(
            color: colorAccent,
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: const Icon(Icons.add_rounded, color: colorWhite, size: 24.0),
        ),
      ],
    );
  }

  /// 好友列表（空状态）
  Widget _buildFriendList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: GlassCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 64.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 48.0,
                  color: colorNeutral.withAlpha(100),
                ),
                const SizedBox(height: 16.0),
                const Text(
                  '还没有好友',
                  style: styleCaption,
                ),
                const SizedBox(height: 8.0),
                const Text(
                  '扫码或分享链接添加好友\n即可开始视频通话',
                  style: styleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24.0),
                // 占位：好友列表为空时的引导说明
                Text(
                  '点击右上角 + 添加好友',
                  style: styleSmall.copyWith(color: colorAccent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
