import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/call_provider.dart';
import 'providers/friend_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/signaling_provider.dart';
import 'services/signaling/firebase_signaling.dart';
import 'screens/home_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/welcome_screen.dart';

/// ClearCall 入口
///
/// 初始化流程：
/// 1. 用默认设置立即启动（不等待任何 I/O）
/// 2. AppRoot 根据设置状态显示欢迎页或主界面
/// 3. 后台异步加载 SharedPreferences 并更新 Provider
/// 4. 进入主界面后延迟初始化 Firebase 信令 + 好友系统
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 用空 ID 的默认设置先启动（始终从欢迎页开始）
  // 真实设置会在启动后异步加载
  runApp(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier(AppSettings.defaults(localId: '')),
        ),
      ],
      child: const ClearCallApp(home: AppRoot()),
    ),
  );
}

/// 应用根组件 — 负责页面切换 + 生命周期监听 + 来电监听
///
/// 根据 [AppSettings.isFirstLaunch] 自动切换：
/// - 首次启动 → WelcomeScreen（输入昵称、生成 ID）
/// - 已完成启动 → HomeScreen（主界面）
///
/// 同时监听：
/// - App 生命周期（前后台切换）→ 同步在线状态
/// - 来电事件 → 弹出 IncomingCallScreen
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot>
    with WidgetsBindingObserver {
  bool _servicesInitialized = false;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 第一帧后：后台加载已保存的设置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettingsInBackground();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 服务未初始化时不处理生命周期事件
    if (!_servicesInitialized) return;

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
  /// 只在用户尚未操作时更新设置（避免覆盖用户输入）。
  /// 加载完成后，若已非首次启动，设置变更会自动触发 rebuild 切换状态。
  Future<void> _loadSettingsInBackground() async {
    try {
      final saved = await SettingsNotifier.loadFromPrefs();
      if (!mounted) return;

      // 只在用户尚未操作时同步已保存的设置
      final current = ref.read(settingsProvider);
      if (current.isFirstLaunch && current.localId.isEmpty) {
        ref.read(settingsProvider.notifier).updateAll(saved);
      }
    } catch (_) {
      // 加载失败也不影响使用，停留在欢迎页
    }
  }

  /// 初始化信令服务 + 好友系统
  ///
  /// 根据设置自动选择 Firebase 或 Leancloud 初始化流程。
  /// - Firebase：先初始化 Firebase Platform，再匿名登录，最后初始化通话/好友服务
  /// - Leancloud：直接匿名登录 Leancloud，跳过 Firebase 和 FCM
  ///
  /// 完成后 setState 触发 rebuild 显示 HomeScreen。
  Future<void> _initializeServices() async {
    if (_initializing || _servicesInitialized) return;
    _initializing = true;

    final settings = ref.read(settingsProvider);
    if (settings.localId.isEmpty) {
      _initializing = false;
      return;
    }

    try {
      final signaling = ref.read(signalingProvider);
      final isFirebase = signaling is FirebaseSignaling;

      if (isFirebase) {
        // Firebase 模式：需要先初始化 Firebase Platform
        // （AndroidManifest 禁用了 FirebaseInitProvider，必须显式调用）
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
      }

      // 初始化信令服务（匿名登录）
      await signaling.initialize();
      ref.read(signalingInitializedProvider.notifier).state = true;

      // 初始化通话和好友服务
      await ref.read(callProvider.notifier).initialize();
      await ref.read(friendProvider.notifier).initialize();

      _servicesInitialized = true;
    } catch (e) {
      debugPrint('服务初始化失败: $e');
    } finally {
      _initializing = false;
    }

    if (mounted) setState(() {});
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
    final settings = ref.watch(settingsProvider);

    // 监听来电事件（必须在 build 内调用 ref.listen）
    ref.listen<CallState2>(callProvider, (previous, next) {
      if (next.hasIncomingCall &&
          next.phase == CallPhase.ringing &&
          (previous == null || !previous.hasIncomingCall)) {
        _showIncomingCallScreen(next.incomingCallerName ?? '未知来电');
      }
    });

    // 已完成首次启动且有 ID → 需要先初始化服务再显示主界面
    if (!settings.isFirstLaunch && settings.localId.isNotEmpty) {
      if (_servicesInitialized) {
        return const HomeScreen();
      }
      // 触发初始化
      if (!_initializing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _initializeServices();
        });
      }
      // 初始化中 → 显示加载指示器
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 首次启动 → 欢迎页
    return const WelcomeScreen();
  }
}
