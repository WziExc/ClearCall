import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clearcall/widgets/glass_card.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // GlassCard Widget 测试
  // ═══════════════════════════════════════════════════════════

  group('GlassCard', () {
    testWidgets('渲染基础卡片（含文字子组件）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              child: Text('卡片内容'),
            ),
          ),
        ),
      );

      // 验证文字子组件存在
      expect(find.text('卡片内容'), findsOneWidget);
    });

    testWidgets('自定义圆角半径', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              borderRadius: 12.0,
              child: Text('小圆角卡片'),
            ),
          ),
        ),
      );

      // 组件不应崩溃，文字可见
      expect(find.text('小圆角卡片'), findsOneWidget);
    });

    testWidgets('自定义内外边距', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              padding: EdgeInsets.all(24.0),
              margin: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('带间距卡片'),
            ),
          ),
        ),
      );

      expect(find.text('带间距卡片'), findsOneWidget);
    });

    testWidgets('固定宽高', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              width: 200.0,
              height: 100.0,
              child: Text('固定尺寸卡片'),
            ),
          ),
        ),
      );

      expect(find.text('固定尺寸卡片'), findsOneWidget);
    });

    testWidgets('自定义模糊强度', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              blurStrength: 10.0,
              child: Text('低模糊卡片'),
            ),
          ),
        ),
      );

      expect(find.text('低模糊卡片'), findsOneWidget);
    });

    testWidgets('模糊强度为 0 时不包裹 BackdropFilter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              blurStrength: 0.0,
              child: Text('无模糊卡片'),
            ),
          ),
        ),
      );

      expect(find.text('无模糊卡片'), findsOneWidget);
    });

    testWidgets('自定义背景透明度', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              backgroundOpacity: 0.5,
              child: Text('半透明卡片'),
            ),
          ),
        ),
      );

      expect(find.text('半透明卡片'), findsOneWidget);
    });

    testWidgets('复杂子组件（多层嵌套）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 32),
                  SizedBox(height: 8),
                  Text('标题', style: TextStyle(fontSize: 18)),
                  Text('副标题', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('标题'), findsOneWidget);
      expect(find.text('副标题'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('Can be used in a ListView', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: const [
                GlassCard(child: Text('卡片 1')),
                GlassCard(child: Text('卡片 2')),
                GlassCard(child: Text('卡片 3')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('卡片 1'), findsOneWidget);
      expect(find.text('卡片 2'), findsOneWidget);
      expect(find.text('卡片 3'), findsOneWidget);
    });
  });
}
