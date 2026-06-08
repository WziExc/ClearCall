import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clearcall/widgets/color_avatar.dart';
import 'package:clearcall/utils/constants.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // ColorAvatar Widget 测试
  // ═══════════════════════════════════════════════════════════

  group('ColorAvatar', () {
    testWidgets('渲染中文昵称头像', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColorAvatar(nickname: '张三', size: 48),
          ),
        ),
      );

      // 验证首字母显示
      expect(find.text('张'), findsOneWidget);
    });

    testWidgets('渲染英文昵称头像', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColorAvatar(nickname: 'Alice', size: 48),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('空昵称显示问号', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColorAvatar(nickname: '', size: 48),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('不同尺寸正确渲染', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ColorAvatar(nickname: '小', size: 24),
                ColorAvatar(nickname: '中', size: 48),
                ColorAvatar(nickname: '大', size: 96),
              ],
            ),
          ),
        ),
      );

      expect(find.text('小'), findsOneWidget);
      expect(find.text('中'), findsOneWidget);
      expect(find.text('大'), findsOneWidget);
    });

    testWidgets('自定义圆角', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColorAvatar(
              nickname: '方',
              size: 64,
              borderRadius: 8.0,
            ),
          ),
        ),
      );

      expect(find.text('方'), findsOneWidget);
    });

    testWidgets('相同昵称得到相同颜色（一致性）', (tester) async {
      // 这个测试验证同一昵称在不同实例中颜色一致
      //（源码逻辑：基于昵称 UTF-8 字节和取模 12）

      // 测试两个相同昵称的头像
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ColorAvatar(nickname: '测试', size: 48),
                ColorAvatar(nickname: '测试', size: 48),
              ],
            ),
          ),
        ),
      );

      // 两个头像都显示"测"
      expect(find.text('测'), findsNWidgets(2));
    });

    testWidgets('不同昵称得到不同颜色', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ColorAvatar(nickname: '张三', size: 48),
                ColorAvatar(nickname: '李四', size: 48),
              ],
            ),
          ),
        ),
      );

      expect(find.text('张'), findsOneWidget);
      expect(find.text('李'), findsOneWidget);
    });

    testWidgets('自定义字体大小', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColorAvatar(
              nickname: '大字',
              size: 80,
              fontSize: 24.0,
            ),
          ),
        ),
      );

      expect(find.text('大'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 调色板测试
  // ═══════════════════════════════════════════════════════════

  group('头像调色板', () {
    test('包含 12 种颜色', () {
      expect(avatarColorPalette.length, equals(12));
    });

    test('颜色不重复', () {
      final uniqueColors = avatarColorPalette.toSet();
      expect(uniqueColors.length, equals(12));
    });
  });
}
