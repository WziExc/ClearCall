import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/call_provider.dart';
import 'providers/friend_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/signaling_provider.dart';
import 'screens/home_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/welcome_screen.dart';

/// ClearCall 入口
///
/// 初始化流程：
/// 1. 用默认设置立即启动（不等待任何 I/O）
/// 2. 如果是首次启动 → 欢迎页；否则 → 主界面
/// 3. 后台异步加载 SharedPreferences 并更新 Provider
/// 4. 延迟初始化 Firebase 信令 + 好友系统
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 用空 ID 的默认设置先启动（永远显示欢迎页）
  // 真实设置会在启动后异步加载
  runApp(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier(AppSettings.defaults(localId: '')),
        ),
      ],
      child: const ClearCallApp(
        home: AppRoot(child: WelcomeScreen()),
      ),
    ),
  );
}

/// 应用根组件 — 负责任命周期监听和来电监听
///
/// 包裹子页面，监听：
/// - App 生命周期（前后台切换）→ 同步在线状态
/// - 来电事件 → 弹出 IncomingCallScreen
class AppRoot extends ConsumerStatefulWidget {
  final Widget child;

  const AppRoot({super.key, required this.child});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 第一帧后：加载设置 + 初始化服务
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettingsInBackground();
      _initializeServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(friendProvider.notifier).setOnline();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        ref.read(friendProvider.notifier).setOffline();
      default:
        break;
    }
  }

  /// 后台加载 SharedPreferences 设置
  ///
  /// 如果加载成功且用户之前已完成首次启动 → 跳转到主界面
  Future<void> _loadSettingsInBackground() async {
    try {
      final saved = await SettingsNotifier.loadFromPrefs();
      if (!mounted) return;

      // 更新 Provider 中的设置
      ref.read(settingsProvider.notifier).updateAll(saved);

      // 如果之前已完成首次启动 → 替换为 HomeScreen
      if (!saved.isFirstLaunch && saved.localId.isNotEmpty) {
        _navigateToHome();
      }
    } catch (_) {
      // 加载失败也不影响使用，停留在欢迎页
    }
  }

  /// 跳转到主界面
  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// 初始化信令和好友服务
  Future<void> _initializeServices() async {
    final settings = ref.read(settingsProvider);
    if (settings.localId.isEmpty) return;

    try {
      final signaling = ref.read(signalingProvider);
      await signaling.initialize();
      ref.read(signalingInitializedProvider.notifier).state = true;

      await ref.read(callProvider.notifier).initialize();
      await ref.read(friendProvider.notifier).initialize();

      _startIncomingCallListener();
    } catch (e) {
      debugPrint('服务初始化失败: $e');
    }
  }

  /// 监听来电事件
  void _startIncomingCallListener() {
    ref.listen<CallState2>(callProvider, (previous, next) {
      if (next.hasIncomingCall &&
          next.phase == CallPhase.ringing &&
          (previous == null || !previous.hasIncomingCall)) {
        _showIncomingCallScreen(next.incomingCallerName ?? '未知来电');
      }
    });
  }

  /// 显示来电接听界面
  void _showIncomingCallScreen(String callerName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const IncomingCallScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
