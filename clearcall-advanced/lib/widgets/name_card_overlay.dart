import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 通话中名片条
///
/// 通过菜单或轻触对方画面触发，从底部控制栏上方滑入。
/// 3 秒后自动消失（对齐 03-ui-design-spec.md 5.7 节）。
///
/// 显示：头像 + 昵称 + 在线时长。
/// 非好友时显示"添加好友"按钮。
class NameCardBar extends StatefulWidget {
  /// 显示名称
  final String name;

  /// 头像颜色（ColorAvatar 生成的颜色）
  final Color avatarColor;

  /// 头像文字（取昵称首字符）
  final String avatarText;

  /// 是否为好友（非好友显示添加按钮）
  final bool isFriend;

  /// 通话时长文本（如 "02:34"）
  final String durationText;

  /// 添加好友回调
  final VoidCallback? onAddFriend;

  /// 名片消失回调
  final VoidCallback? onDismiss;

  const NameCardBar({
    super.key,
    required this.name,
    required this.avatarColor,
    required this.avatarText,
    this.isFriend = false,
    this.durationText = '',
    this.onAddFriend,
    this.onDismiss,
  });

  @override
  State<NameCardBar> createState() => _NameCardBarState();
}

class _NameCardBarState extends State<NameCardBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();

    // 3 秒后自动消失
    _autoDismissTimer = Timer(nameCardDuration, () {
      if (mounted) _dismiss();
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _controller.reverse();
    if (mounted) widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: GestureDetector(
        onTap: () {}, // 阻止穿透
        child: Container(
          margin: const EdgeInsets.only(bottom: 84.0),
          padding: const EdgeInsets.symmetric(
            horizontal: paddingHorizontal,
            vertical: 12.0,
          ),
          decoration: BoxDecoration(
            color: colorGlassBackground.withAlpha(200),
            border: const Border(
              top: BorderSide(color: colorGlassBorder, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // 头像
              Container(
                width: 40.0,
                height: 40.0,
                decoration: BoxDecoration(
                  color: widget.avatarColor,
                  borderRadius: BorderRadius.circular(radiusAvatarList),
                ),
                child: Center(
                  child: Text(
                    widget.avatarText,
                    style: styleTitle3.copyWith(
                      color: colorWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12.0),
              // 名称 + 时长
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.name,
                      style: styleBody.copyWith(
                        color: colorTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.durationText.isNotEmpty)
                      Text(
                        widget.durationText,
                        style: styleSmall.copyWith(color: colorNeutral),
                      ),
                  ],
                ),
              ),
              // 添加好友按钮（非好友时显示）
              if (!widget.isFriend)
                GestureDetector(
                  onTap: widget.onAddFriend,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: colorAccent,
                      borderRadius: BorderRadius.circular(radiusPill),
                    ),
                    child: Text(
                      '添加好友',
                      style: styleSmall.copyWith(
                        color: colorWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
