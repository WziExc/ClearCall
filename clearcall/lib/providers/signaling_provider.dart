import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/signaling/leancloud_signaling.dart';
import '../services/signaling/firebase_signaling.dart';
import '../services/signaling/signaling_service.dart';
import '../utils/constants.dart';
import 'settings_provider.dart';

/// 共享的信令服务 Provider
///
/// 根据 [AppSettings.signalingService] 返回对应的信令服务实现。
/// 支持 Firebase 和 Leancloud，默认使用 Leancloud（国内网络环境）。
///
/// 注意：切换信令服务后需要重启 App 才能生效。
final signalingProvider = Provider<SignalingService>((ref) {
  final serviceType = ref.watch(settingsProvider).signalingService;

  switch (serviceType) {
    case SignalingServiceType.leancloud:
      return LeancloudSignaling();
    case SignalingServiceType.firebase:
      return FirebaseSignaling();
  }
});

/// 信令服务是否已初始化
final signalingInitializedProvider = StateProvider<bool>((ref) => false);
