import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/signaling/firebase_signaling.dart';

/// 共享的信令服务 Provider
///
/// 整个 App 共享同一个 FirebaseSignaling 实例，
/// CallNotifier 和 FriendNotifier 都通过此 Provider 获取。
/// 确保 Firebase 只初始化一次，匿名认证只有一个。
final signalingProvider = Provider<FirebaseSignaling>((ref) {
  final signaling = FirebaseSignaling();
  // 异步初始化在各自的 Notifier 中调用
  return signaling;
});

/// 信令服务是否已初始化
final signalingInitializedProvider = StateProvider<bool>((ref) => false);
