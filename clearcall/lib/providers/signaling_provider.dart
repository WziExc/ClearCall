import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/signaling/qr_signaling.dart';
import '../services/signaling/signaling_service.dart';

/// 共享的信令服务 Provider
///
/// ClearCall 使用扫码 SDP 交换方案：无需服务器，双方扫描 QR 码交换 SDP。
final signalingProvider = Provider<SignalingService>((ref) {
  return QrSignaling();
});

/// 信令服务是否已初始化
final signalingInitializedProvider = StateProvider<bool>((ref) => false);
