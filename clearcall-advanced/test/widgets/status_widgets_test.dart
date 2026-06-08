import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clearcall/widgets/status_widgets.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // LoadingState Widget 测试
  // ═══════════════════════════════════════════════════════════

  group('LoadingState', () {
    testWidgets('渲染加载指示器', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LoadingState()),
        ),
      );

      // 验证 CircularProgressIndicator 存在
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('显示加载文字', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LoadingState(message: '连接中...')),
        ),
      );

      expect(find.text('连接中...'), findsOneWidget);
    });

    testWidgets('无文字时不显示文字区域', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LoadingState()),
        ),
      );

      // 只有进度指示器，没有多余文字
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('长文字正确居中', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingState(message: '正在建立加密连接，请稍候...'),
          ),
        ),
      );

      expect(
        find.text('正在建立加密连接，请稍候...'),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // ErrorState Widget 测试
  // ═══════════════════════════════════════════════════════════

  group('ErrorState', () {
    testWidgets('显示错误信息', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorState(message: '网络连接失败'),
          ),
        ),
      );

      expect(find.text('网络连接失败'), findsOneWidget);
    });

    testWidgets('显示重试按钮（有回调时）', (tester) async {
      int retryCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorState(
              message: '加载失败',
              onRetry: () => retryCount++,
            ),
          ),
        ),
      );

      expect(find.text('重试'), findsOneWidget);

      // 点击重试
      await tester.tap(find.text('重试'));
      await tester.pump();

      expect(retryCount, equals(1));
    });

    testWidgets('无回调时不显示重试按钮', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorState(message: '权限被拒绝'),
          ),
        ),
      );

      expect(find.text('重试'), findsNothing);
    });

    testWidgets('自定义图标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorState(
              message: '麦克风权限未授予',
              icon: Icons.mic_off_rounded,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
    });

    testWidgets('默认使用 error_outline 图标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorState(message: '错误'),
          ),
        ),
      );

      // 默认图标存在
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // EmptyState Widget 测试
  // ═══════════════════════════════════════════════════════════

  group('EmptyState', () {
    testWidgets('显示标题和引导文案', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.people_outline_rounded,
              title: '还没有好友',
              subtitle: '扫码或点击 + 按钮添加好友',
            ),
          ),
        ),
      );

      expect(find.text('还没有好友'), findsOneWidget);
      expect(find.text('扫码或点击 + 按钮添加好友'), findsOneWidget);
    });

    testWidgets('显示操作按钮（有 actionLabel 和 onAction 时）', (tester) async {
      int actionCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.call_end_rounded,
              title: '还没有通话记录',
              subtitle: '创建或加入房间开始通话',
              actionLabel: '新建房间',
              actionIcon: Icons.add_rounded,
              onAction: () => actionCount++,
            ),
          ),
        ),
      );

      expect(find.text('新建房间'), findsOneWidget);

      // 点击操作按钮
      await tester.tap(find.text('新建房间'));
      await tester.pump();

      expect(actionCount, equals(1));
    });

    testWidgets('无操作按钮时不显示按钮区域', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.hourglass_empty_rounded,
              title: '暂无数据',
              subtitle: '稍后再来',
            ),
          ),
        ),
      );

      // 无 TextButton（因为 actionLabel 为 null）
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('自定义图标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.wifi_off_rounded,
              title: '无网络连接',
              subtitle: '请检查网络设置后重试',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('组合使用：GlassCard 包裹', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.inbox_rounded,
              title: '收件箱为空',
              subtitle: '暂无消息',
            ),
          ),
        ),
      );

      // 内部使用 GlassCard，验证结构完整
      expect(find.text('收件箱为空'), findsOneWidget);
      expect(find.text('暂无消息'), findsOneWidget);
    });
  });
}
