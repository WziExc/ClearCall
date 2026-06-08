import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/call_provider.dart';
import '../utils/constants.dart';

/// 网络连接状态 Provider
///
/// 监听网络连接状态变化，用于自动重连提示。
final connectivityBannerProvider =
    StateNotifierProvider<ConnectivityBannerNotifier, ConnectivityBannerState>(
  (ref) => ConnectivityBannerNotifier(),
);

/// 连接状态
enum ConnectionStatus {
  /// 已连接
  connected,

  /// 连接中断
  disconnected,

  /// 正在重连
  reconnecting,
}

/// 连接状态数据
class ConnectivityBannerState {
  final ConnectionStatus status;
  final Timer? _reconnectTimer;

  const ConnectivityBannerState({
    this.status = ConnectionStatus.connected,
    Timer? reconnectTimer,
  }) : _reconnectTimer = reconnectTimer;

  bool get isDisconnected => status != ConnectionStatus.connected;

  ConnectivityBannerState copyWith({ConnectionStatus? status, Timer? reconnectTimer}) {
    return ConnectivityBannerState(
      status: status ?? this.status,
      reconnectTimer: reconnectTimer ?? _reconnectTimer,
    );
  }
}

/// 网络连接状态管理器
class ConnectivityBannerNotifier extends StateNotifier<ConnectivityBannerState> {
  ConnectivityBannerNotifier() : super(const ConnectivityBannerState());

  /// 标记为断开连接
  void markDisconnected() {
    if (state.status == ConnectionStatus.connected) {
      // 先标记为断连，5 秒后检查是否恢复
      final timer = Timer(const Duration(seconds: 5), () {
        if (mounted && state.status == ConnectionStatus.disconnected) {
          state = state.copyWith(status: ConnectionStatus.reconnecting);
        }
      });
      state = state.copyWith(status: ConnectionStatus.disconnected, reconnectTimer: timer);
    }
  }

  /// 标记为已连接
  void markConnected() {
    state._reconnectTimer?.cancel();
    state = const ConnectivityBannerState(status: ConnectionStatus.connected);
  }

  @override
  void dispose() {
    state._reconnectTimer?.cancel();
    super.dispose();
  }
}

/// 网络中断自动重连提示横幅
///
/// 在通话中检测到网络中断时，在顶部显示提示横幅。
/// 非通话状态下不显示。
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannerState = ref.watch(connectivityBannerProvider);
    final callState = ref.watch(callProvider);

    // 仅在通话中且网络异常时显示
    final isInCall = callState.phase == CallPhase.inCall ||
        callState.phase == CallPhase.waiting ||
        callState.phase == CallPhase.ringing;

    if (!isInCall || !bannerState.isDisconnected) {
      return const SizedBox.shrink();
    }

    final isReconnecting = bannerState.status == ConnectionStatus.reconnecting;
    final message = isReconnecting ? '网络连接中断，正在尝试重连...' : '网络连接不稳定';
    final bgColor = isReconnecting ? colorWarning.withAlpha(200) : colorDanger.withAlpha(200);

    return Positioned(
      left: paddingHorizontal,
      right: paddingHorizontal,
      top: MediaQuery.of(context).padding.top + 4.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isReconnecting
                ? const SizedBox(
                    width: 14.0,
                    height: 14.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: colorWhite,
                    ),
                  )
                : const Icon(Icons.wifi_off_rounded, color: colorWhite, size: 16.0),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                message,
                style: styleTiny.copyWith(color: colorWhite),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
