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
/// 1. 加载本地设置（SharedPreferences）
/// 2. 判断是否首次启动 → 显示欢迎页或主界面
/// 3. 初始化 Firebase 信令服务（异步）
/// 4. 初始化好友系统（异步）
/// 5. 监听应用生命周期以管理在线状态
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 加载设置
  final settings = await SettingsNotifier.loadFromPrefs();

  runApp(
    ProviderScope(
      overrides: [
        // 用加载的设置覆盖默认 Provider
        settingsProvider.overrideWith((ref) {
          return SettingsNotifier(settings);
        }),
      ],
      child: ClearCallApp(
        // 首次启动或没有本地 ID → 欢迎页
        // 已有 ID → 直接进入主界面
        // AppRoot 包裹子页面以处理生命周期和来电监听
        home: AppRoot(
          child: settings.isFirstLaunch || settings.localId.isEmpty
              ? const WelcomeScreen()
              : const HomeScreen(),
        ),
      ),
    ),
  );
}

/// 应用根组件 — 负责任命周期监听和来电监听
///
/// 包裹 HomeScreen/WelcomeScreen，监听：
/// - App 生命周期（前后台切换）→ 同步在线状态
/// - 来电事件 → 弹出 IncomingCallScreen
class AppRoot extends ConsumerStatefulWidget {
  /// 子页面（欢迎页或主界面）
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

    // 延迟初始化服务（等首次 build 完成）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 应用生命周期变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // 回到前台 → 设置在线
        ref.read(friendProvider.notifier).setOnline();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // 进入后台 → 设置离线
        ref.read(friendProvider.notifier).setOffline();
      default:
        break;
    }
  }

  /// 初始化信令和好友服务
  Future<void> _initializeServices() async {
    final settings = ref.read(settingsProvider);
    if (settings.localId.isEmpty) return; // 还未生成 ID，跳过

    try {
      // 1. 初始化 Firebase 信令（匿名认证 + RTDB 连接）
      final signaling = ref.read(signalingProvider);
      await signaling.initialize();
      ref.read(signalingInitializedProvider.notifier).state = true;

      // 2. 初始化通话系统（创建 CallManager + 绑定回调）
      await ref.read(callProvider.notifier).initialize();

      // 3. 初始化好友系统（创建用户节点 + onDisconnect + 加载好友 + 监听申请）
      await ref.read(friendProvider.notifier).initialize();

      // 4. 启动来电监听
      _startIncomingCallListener();
    } catch (e) {
      debugPrint('服务初始化失败: $e');
    }
  }

  /// 监听来电事件
  void _startIncomingCallListener() {
    ref.listen<CallState2>(callProvider, (previous, next) {
      // 当有来电时，弹出来电界面
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
