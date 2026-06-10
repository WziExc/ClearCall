import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/signaling/qr_signaling.dart';
import '../services/signaling/signaling_service.dart';
import '../services/signaling/websocket_signaling.dart';
import '../utils/constants.dart';
import 'settings_provider.dart';

/// 共享的信令服务 Provider
///
/// 根据用户设置自动选择 WebSocket 中继 或 QR 扫码。
/// 默认使用 WebSocket 中继（远程通话），QR 为后备。
final signalingProvider = Provider<SignalingService>((ref) {
  final settings = ref.watch(settingsProvider);
  switch (settings.signalingService) {
    case SignalingServiceType.webSocket:
      return WebSocketSignaling(serverUrl: signalingServerUrl);
    case SignalingServiceType.qrCode:
      return QrSignaling();
  }
});

/// 信令服务是否已初始化
final signalingInitializedProvider = StateProvider<bool>((ref) => false);
