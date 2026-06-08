import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';

/// ClearCall 入口
///
/// 初始化流程：
/// 1. 加载本地设置（SharedPreferences）
/// 2. 判断是否首次启动 → 显示欢迎页或主界面
/// 3. 所有后续操作通过 Riverpod 管理状态
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
        home: settings.isFirstLaunch || settings.localId.isEmpty
            ? const WelcomeScreen()
            : const HomeScreen(),
      ),
    ),
  );
}
