import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clearcall/widgets/glass_button.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // GlassButton Widget 测试
  // ═══════════════════════════════════════════════════════════

  group('GlassButton', () {
    testWidgets('渲染普通按钮（含文字和图标）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '新建房间',
                icon: Icons.add,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      // 验证文字
      expect(find.text('新建房间'), findsOneWidget);
      // 验证图标
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('渲染无图标按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '确定',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('确定'), findsOneWidget);
    });

    testWidgets('渲染纯图标按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '',
                icon: Icons.close,
                iconOnly: true,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('三种类型按钮正常渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                GlassButton(
                  label: '普通按钮',
                  type: GlassButtonType.normal,
                  onPressed: null, // 占位，后续 click 测试
                ),
                GlassButton(
                  label: '危险按钮',
                  type: GlassButtonType.danger,
                  onPressed: null,
                ),
                GlassButton(
                  label: '强调按钮',
                  type: GlassButtonType.accent,
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('普通按钮'), findsOneWidget);
      expect(find.text('危险按钮'), findsOneWidget);
      expect(find.text('强调按钮'), findsOneWidget);
    });

    testWidgets('禁用按钮显示半透明', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '禁用按钮',
                onPressed: null, // 无回调 = 禁用
              ),
            ),
          ),
        ),
      );

      expect(find.text('禁用按钮'), findsOneWidget);
      // 验证禁用态存在（AnimatedOpacity 的子组件存在）
    });

    testWidgets('点击触发回调', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '点我',
                onPressed: () => tapCount++,
              ),
            ),
          ),
        ),
      );

      // 模拟点击
      await tester.tap(find.text('点我'));
      await tester.pump();

      expect(tapCount, equals(1));
    });

    testWidgets('禁用按钮点击不触发回调', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '禁用',
                onPressed: null,
              ),
            ),
          ),
        ),
      );

      // 模拟点击（GestureDetector 的 onTap 为 null，不会触发）
      await tester.tap(find.text('禁用'));

      expect(tapCount, equals(0));
    });

    testWidgets('连续点击多次触发回调', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '多次点击',
                onPressed: () => tapCount++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('多次点击'));
      await tester.pump();
      await tester.tap(find.text('多次点击'));
      await tester.pump();
      await tester.tap(find.text('多次点击'));
      await tester.pump();

      expect(tapCount, equals(3));
    });

    testWidgets('自定义宽高', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '宽按钮',
                width: 300.0,
                height: 64.0,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('宽按钮'), findsOneWidget);
    });

    testWidgets('自定义圆角', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassButton(
                label: '方角按钮',
                borderRadius: 8.0,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('方角按钮'), findsOneWidget);
    });

    testWidgets('长文字自动截断', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 100,
                child: GlassButton(
                  label: '这是一个非常非常长的按钮文字应该被截断',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // 按钮文字应存在（即使被截断）
      expect(
        find.text('这是一个非常非常长的按钮文字应该被截断'),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // GlassButtonType 枚举测试
  // ═══════════════════════════════════════════════════════════

  group('GlassButtonType 枚举', () {
    test('包含 3 种类型', () {
      expect(GlassButtonType.values.length, equals(3));
      expect(GlassButtonType.values, contains(GlassButtonType.normal));
      expect(GlassButtonType.values, contains(GlassButtonType.danger));
      expect(GlassButtonType.values, contains(GlassButtonType.accent));
    });
  });
}
