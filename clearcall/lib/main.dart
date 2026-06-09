import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/call_provider.dart';
import 'providers/friend_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/signaling_provider.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';

/// ClearCall 入口
///
/// 初始化流程：
/// 1. 用默认设置立即启动（不等待任何 I/O）
/// 2. AppRoot 根据设置状态显示欢迎页或主界面
/// 3. 后台异步加载 SharedPreferences 并更新 Provider
/// 4. 进入主界面后延迟初始化信令 + 好友系统
void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

/// 应用根组件 — 根据 [AppSettings.isFirstLaunch] 自动切换页面
///
/// - 首次启动 → WelcomeScreen（输入昵称、生成 ID）
/// - 已完成启动 → HomeScreen（主界面）
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

  Future<void> _loadSettingsInBackground() async {
    try {
      final saved = await SettingsNotifier.loadFromPrefs();
      if (!mounted) return;

      final current = ref.read(settingsProvider);
      if (current.isFirstLaunch && current.localId.isEmpty) {
        ref.read(settingsProvider.notifier).updateAll(saved);
      }
    } catch (_) {
      // 加载失败不影响使用
    }
  }

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
      await signaling.initialize();
      ref.read(signalingInitializedProvider.notifier).state = true;

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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    if (!settings.isFirstLaunch && settings.localId.isNotEmpty) {
      if (_servicesInitialized) {
        return const HomeScreen();
      }
      if (!_initializing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _initializeServices();
        });
      }
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return const WelcomeScreen();
  }
}
