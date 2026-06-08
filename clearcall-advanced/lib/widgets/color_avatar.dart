import 'dart:convert';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 自动生成彩色头像组件
///
/// 根据昵称的哈希值从预设 12 色调色板中选择背景色，
/// 显示昵称首字母大写。
///
/// 使用示例：
/// ```dart
/// ColorAvatar(nickname: '张三', size: 48)
/// ```
class ColorAvatar extends StatelessWidget {
  /// 用户昵称
  final String nickname;

  /// 头像直径
  final double size;

  /// 圆角（默认正圆 = size / 2）
  final double? borderRadius;

  /// 首字母字体大小（null = 自动根据 size 计算）
  final double? fontSize;

  const ColorAvatar({
    super.key,
    required this.nickname,
    this.size = 48.0,
    this.borderRadius,
    this.fontSize,
  });

  /// 根据昵称哈希值选取背景色
  Color _getBackgroundColor() {
    if (nickname.isEmpty) {
      return colorNeutral;
    }
    final bytes = utf8.encode(nickname);
    final hash = bytes.fold<int>(0, (prev, b) => prev + b);
    return avatarColorPalette[hash % avatarColorPalette.length];
  }

  /// 获取昵称首字母（大写）
  String _getInitial() {
    if (nickname.isEmpty) return '?';
    return nickname.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (size / 2);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        _getInitial(),
        style: TextStyle(
          color: colorWhite,
          fontSize: fontSize ?? (size * 0.42),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
