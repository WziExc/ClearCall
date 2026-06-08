import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/signaling/signaling_service.dart';
import '../services/signaling/firebase_signaling.dart';
import '../services/signaling/leancloud_signaling.dart';
import '../services/signaling/websocket_signaling.dart';
import '../services/signaling/qr_signaling.dart';
import '../utils/constants.dart';
import 'settings_provider.dart';

/// 共享的信令服务 Provider
///
/// 根据 [AppSettings.signalingService] 返回对应的信令服务实现：
/// - webSocket：自建 WebSocket 中继（国内推荐）
/// - qrCode：扫码 SDP 交换（无需服务器，应急后备）
/// - firebase：Firebase RTDB（海外用户）
/// - leancloud：Leancloud REST API（当前不可注册，保留）
///
/// 注意：切换信令服务后需要重启 App 才能生效。
final signalingProvider = Provider<SignalingService>((ref) {
  final serviceType = ref.watch(settingsProvider).signalingService;

  switch (serviceType) {
    case SignalingServiceType.webSocket:
      return WebSocketSignaling();
    case SignalingServiceType.qrCode:
      return QrSignaling();
    case SignalingServiceType.firebase:
      return FirebaseSignaling();
    case SignalingServiceType.leancloud:
      return LeancloudSignaling();
  }
});

/// 信令服务是否已初始化
final signalingInitializedProvider = StateProvider<bool>((ref) => false);
