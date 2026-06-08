import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/friend.dart';
import '../providers/call_provider.dart';
import '../providers/friend_provider.dart';
import '../providers/settings_provider.dart';
import '../services/connectivity_service.dart';
import '../utils/constants.dart';
import '../widgets/color_avatar.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_widgets.dart';
import 'add_friend_screen.dart';
import 'join_room_screen.dart';
import 'room_waiting_screen.dart';

/// 通话 Tab
///
/// 包含：实时摄像头预览（居中圆角矩形毛玻璃）、好友抽屉（左上角）、
/// 新建/加入房间按钮、活跃房间横幅、通话记录列表（间隙 + 右滑删除）。
class CallTab extends ConsumerStatefulWidget {
  const CallTab({super.key});

  @override
  ConsumerState<CallTab> createState() => _CallTabState();
}

class _CallTabState extends ConsumerState<CallTab> {
  /// 预览专用渲染器（独立于 WebRTCService，避免冲突）
  RTCVideoRenderer? _previewRenderer;
  MediaStream? _previewStream;
  bool _previewReady = false;
  bool _previewStarted = false;

  @override
  void initState() {
    super.initState();
    // 第一帧后启动预览，避免阻塞首帧渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startPreview();
    });
  }

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  /// 启动摄像头预览（低分辨率，节省资源）
  Future<void> _startPreview() async {
    if (_previewStarted) return;
    _previewStarted = true;

    try {
      _previewRenderer = RTCVideoRenderer();
      await _previewRenderer!.initialize();

      _previewStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': 480,
          'height': 640,
          'frameRate': 30,
        },
      });

      _previewRenderer!.srcObject = _previewStream;
      if (mounted) setState(() => _previewReady = true);
    } catch (_) {
      // 权限被拒绝或摄像头不可用 → 显示占位符
      _previewReady = false;
      _previewStarted = false;
      if (mounted) setState(() {});
    }
  }

  /// 停止预览并释放摄像头
  Future<void> _stopPreview() async {
    if (!_previewStarted) return;
    _previewStarted = false;
    _previewReady = false;

    // 先解除绑定，防止渲染器访问已释放的流
    if (_previewRenderer != null) {
      _previewRenderer!.srcObject = null;
    }

    if (_previewStream != null) {
      for (final track in _previewStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await _previewStream!.dispose();
      } catch (_) {}
      _previewStream = null;
    }

    if (_previewRenderer != null) {
      try {
        await _previewRenderer!.dispose();
      } catch (_) {}
      _previewRenderer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);

    if (callState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 活跃房间等待中
    final hasActiveRoom =
        callState.phase == CallPhase.waiting && callState.roomId != null;

    // 通话需要摄像头 → 停止预览
    final needsCamera = callState.phase == CallPhase.inCall ||
        callState.phase == CallPhase.ringing ||
        callState.phase == CallPhase.connecting;

    if (needsCamera && _previewStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _stopPreview());
    }

    // 空闲/结束/等待时 → 可显示预览（常驻）
    final canShowPreview =
        (callState.phase == CallPhase.idle ||
            callState.phase == CallPhase.ended ||
            hasActiveRoom) &&
        callState.errorMessage == null;

    // 自动恢复预览（退出房间后重新启动）
    if (canShowPreview && !_previewStarted && !needsCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startPreview();
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8.0),

          // 顶部栏：好友抽屉按钮
          _buildTopBar(context, ref),

          const SizedBox(height: 12.0),

          // 实时摄像头预览（居中，圆角矩形，毛玻璃）
          if (canShowPreview) _buildCameraPreview(),

          const SizedBox(height: 20.0),

          // 活跃房间横幅 或 房间按钮
          if (hasActiveRoom)
            _buildActiveRoomBanner(context, ref, callState)
          else if (callState.phase == CallPhase.idle ||
              callState.phase == CallPhase.ended)
            _buildRoomButtons(context, ref),

          const SizedBox(height: 8.0),

          // 错误提示
          if (callState.errorMessage != null)
            _buildErrorBanner(callState.errorMessage!),

          const SizedBox(height: 24.0),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 顶部栏
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTopBar(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        // 好友抽屉按钮
        _buildFriendsDrawerButton(context, ref),
        const Spacer(),
      ],
    );
  }

  /// 好友抽屉按钮（左上角）
  Widget _buildFriendsDrawerButton(BuildContext context, WidgetRef ref) {
    final friendState = ref.watch(friendProvider);
    final pendingCount = friendState.pendingCount;

    return GestureDetector(
      onTap: () => _showFriendsDrawer(context, ref),
      child: Container(
        height: 40.0,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        decoration: BoxDecoration(
          color: colorGlassBackground,
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(color: colorGlassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_rounded, size: 18.0, color: colorAccent),
            const SizedBox(width: 6.0),
            Text(
              '联系人',
              style: styleSmall.copyWith(
                color: colorTextPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (pendingCount > 0) ...[
              const SizedBox(width: 6.0),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: colorDanger,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Text(
                  '$pendingCount',
                  style: styleTiny.copyWith(color: colorWhite),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 好友抽屉（底部弹出面板）
  void _showFriendsDrawer(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _FriendsDrawerContent(ref: ref),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 摄像头预览（居中，圆角矩形，毛玻璃效果）
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCameraPreview() {
    const double previewSize = 280.0;
    const double borderRadius = 24.0;

    return Center(
      child: Container(
        width: previewSize,
        height: previewSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: colorAccent.withAlpha(30),
              blurRadius: 24.0,
              spreadRadius: 1.0,
            ),
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 40.0,
              spreadRadius: 2.0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 底层：摄像头视频流
              if (_previewReady && _previewRenderer != null)
                RTCVideoView(
                  _previewRenderer!,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: true,
                ),

              // 摄像头不可用时：占位符
              if (!_previewReady)
                Container(
                  color: colorGlassBackground,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam_rounded,
                        size: 48.0,
                        color: colorNeutral.withAlpha(150),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        '摄像头预览',
                        style: styleSmall.copyWith(color: colorNeutral),
                      ),
                    ],
                  ),
                ),

              // 毛玻璃渐变叠加层（越靠近边缘越不透明）
              if (_previewReady)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(borderRadius),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(borderRadius),
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 1.0,
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              Colors.white.withAlpha(15),
                              Colors.white.withAlpha(60),
                              Colors.white.withAlpha(120),
                            ],
                            stops: const [0.0, 0.4, 0.7, 0.88, 1.0],
                          ),
                          border: Border.all(
                            color: Colors.white.withAlpha(60),
                            width: 2.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 活跃房间横幅
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildActiveRoomBanner(
      BuildContext context, WidgetRef ref, CallState2 callState) {
    final roomId = callState.roomId ?? '------';
    final formatted = roomId.length == 6
        ? '${roomId.substring(0, 3)} ${roomId.substring(3, 6)}'
        : roomId;

    return Column(
      children: [
        // 大号脉动圆点
        const _PulsingDot(size: 48.0, dotSize: 16.0),
        const SizedBox(height: 16.0),
        Text(
          '正在等待好友加入',
          style: styleTitle2.copyWith(color: colorTextPrimary),
        ),
        const SizedBox(height: 6.0),
        Text(
          '房间 $formatted',
          style: styleTitle3.copyWith(
            color: colorAccent,
            letterSpacing: 4.0,
          ),
        ),
        const SizedBox(height: 20.0),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                label: '回到房间',
                icon: Icons.arrow_forward_rounded,
                type: GlassButtonType.accent,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RoomWaitingScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: GlassButton(
                label: '退出房间',
                icon: Icons.call_end_rounded,
                type: GlassButtonType.danger,
                onPressed: () => _confirmCancelRoom(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16.0),
      ],
    );
  }

  /// 确认退出房间弹窗
  void _confirmCancelRoom() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出房间'),
        content: const Text('确定要关闭房间吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(callProvider.notifier).cancelWaiting();
            },
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 房间按钮
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRoomButtons(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: GlassButton(
            label: '新建房间',
            icon: Icons.add_rounded,
            onPressed: () async {
              await _stopPreview();

              if (!await _checkDataWarning(context, ref)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _startPreview();
                });
                return;
              }

              await ref.read(callProvider.notifier).createRoom();
              final state = ref.read(callProvider);
              if (state.phase == CallPhase.waiting && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RoomWaitingScreen(),
                  ),
                );
              } else {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _startPreview();
                });
              }
            },
          ),
        ),
        const SizedBox(width: 12.0),
        Expanded(
          child: GlassButton(
            label: '加入房间',
            icon: Icons.login_rounded,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const JoinRoomScreen(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 错误提示
  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: colorDanger.withAlpha(25),
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colorDanger.withAlpha(77)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: colorDanger, size: 20.0),
          const SizedBox(width: spacingCompact),
          Expanded(
            child: Text(
              message,
              style: styleCaption.copyWith(color: colorDanger),
            ),
          ),
        ],
      ),
    );
  }

  /// 流量警告检测
  Future<bool> _checkDataWarning(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    if (settings.mobileWarningShown) return true;

    final isMobile = await ConnectivityService.isOnMobileData();
    if (!isMobile) return true;

    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('流量提醒'),
        content: const Text(
          '您当前正在使用移动数据通话，可能会消耗较多流量。\n\n'
          '• 10 分钟通话约消耗 120 MB\n'
          '• 建议在 Wi-Fi 环境下使用以获得最佳体验',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续通话'),
          ),
          TextButton(
            onPressed: () async {
              await ref
                  .read(settingsProvider.notifier)
                  .saveAllSettings(settings.copyWith(mobileWarningShown: true));
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: const Text('继续，不再提醒'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

}

// ═══════════════════════════════════════════════════════════════════════
// 好友抽屉内容（底部弹出面板）
// ═══════════════════════════════════════════════════════════════════════

class _FriendsDrawerContent extends ConsumerWidget {
  final WidgetRef ref;
  const _FriendsDrawerContent({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendState = ref.watch(friendProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: colorGlassBackground,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(radiusCard)),
      ),
      child: Column(
        children: [
          // 拖拽条
          Padding(
            padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
            child: Center(
              child: Container(
                width: 36.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: colorNeutral.withAlpha(77),
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
          ),

          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: paddingHorizontal, vertical: 8.0),
            child: Row(
              children: [
                const Text('联系人', style: styleTitle2),
                const Spacer(),
                // 添加好友按钮
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AddFriendScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: 36.0,
                    height: 36.0,
                    decoration: BoxDecoration(
                      color: colorAccent,
                      borderRadius: BorderRadius.circular(18.0),
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: colorWhite, size: 18.0),
                  ),
                ),
              ],
            ),
          ),

          // 好友请求提示
          if (friendState.pendingCount > 0)
            _buildRequestBanner(context, ref, friendState.pendingRequests),

          // 好友列表
          Expanded(
            child: friendState.isLoading
                ? const LoadingState(message: '加载联系人...')
                : friendState.filteredFriends.isEmpty
                    ? const EmptyState(
                        icon: Icons.people_outline_rounded,
                        title: '还没有联系人',
                        subtitle: '点击 + 按钮添加好友',
                      )
                    : _buildFriendList(context, ref, friendState),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestBanner(
    BuildContext context,
    WidgetRef ref,
    List<FriendRequest> requests,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: paddingHorizontal, vertical: 4.0),
      child: GestureDetector(
        onTap: () => _showFriendRequestsSheet(context, ref, requests),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: colorAccent.withAlpha(25),
            borderRadius: BorderRadius.circular(radiusListItem),
            border: Border.all(color: colorAccent.withAlpha(77)),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_add_rounded,
                  color: colorAccent, size: 18.0),
              const SizedBox(width: spacingCompact),
              Text(
                '${requests.length} 个待处理的好友申请',
                style: styleCaption.copyWith(color: colorAccent),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  color: colorAccent, size: 20.0),
            ],
          ),
        ),
      ),
    );
  }

  void _showFriendRequestsSheet(
    BuildContext context,
    WidgetRef ref,
    List<FriendRequest> requests,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: colorGlassBackground,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusCard)),
        ),
        padding: const EdgeInsets.all(paddingHorizontal),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: colorNeutral.withAlpha(77),
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            const Text('好友申请', style: styleTitle2),
            const SizedBox(height: 12.0),
            ...requests.map((req) => _buildRequestItem(ctx, ref, req)),
            const SizedBox(height: 16.0),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestItem(
    BuildContext ctx,
    WidgetRef ref,
    FriendRequest request,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: colorGlassBackground,
        borderRadius: BorderRadius.circular(radiusListItem),
        border: Border.all(color: colorGlassBorder),
      ),
      child: Row(
        children: [
          ColorAvatar(nickname: request.nickname, size: 44.0),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.nickname, style: styleCaption),
                const SizedBox(height: 2.0),
                Text(
                  'ID: ${request.fromUid.substring(0, 8)}...',
                  style: styleSmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(friendProvider.notifier)
                  .rejectFriendRequest(request.fromUid);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('拒绝'),
          ),
          const SizedBox(width: 8.0),
          TextButton(
            onPressed: () {
              ref
                  .read(friendProvider.notifier)
                  .acceptFriendRequest(request.fromUid);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: colorAccent),
            child: const Text('同意'),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendList(
    BuildContext context,
    WidgetRef ref,
    dynamic friendState,
  ) {
    final friends = List<Friend>.from(friendState.filteredFriends)
      ..sort((a, b) {
        final aScore = a.status == OnlineStatus.online
            ? 0
            : a.status == OnlineStatus.inCall
                ? 1
                : 2;
        final bScore = b.status == OnlineStatus.online
            ? 0
            : b.status == OnlineStatus.inCall
                ? 1
                : 2;
        return aScore.compareTo(bScore);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
        return _buildFriendItem(context, ref, friend);
      },
    );
  }

  Widget _buildFriendItem(
    BuildContext context,
    WidgetRef ref,
    Friend friend,
  ) {
    final isOffline = friend.status == OnlineStatus.offline;

    return GestureDetector(
      onTap: () {
        // 点击好友 → 显示名片 + 通话记录
        Navigator.of(context).pop(); // 关闭好友抽屉
        _showFriendCard(context, ref, friend);
      },
      child: AnimatedOpacity(
        opacity: isOffline ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // 在线状态 + 头像
                Stack(
                  children: [
                    ColorAvatar(
                      nickname: friend.nickname,
                      size: 48.0,
                      borderRadius: radiusAvatarList,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: indicatorDiameter,
                        height: indicatorDiameter,
                        decoration: BoxDecoration(
                          color: friend.isInCall
                              ? colorWarning
                              : friend.isOnline
                                  ? colorSuccess
                                  : colorNeutral,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: colorWhite, width: 2.0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friend.nickname,
                        style: styleBody.copyWith(
                          color: colorTextPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        friend.isInCall
                            ? '通话中'
                            : friend.isOnline
                                ? '在线'
                                : '离线',
                        style: styleTiny.copyWith(
                          color: friend.isInCall
                              ? colorWarning
                              : friend.isOnline
                                  ? colorSuccess
                                  : colorNeutral,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: colorNeutral, size: 20.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 显示好友名片（底部面板：头像 + 昵称 + 状态 + 通话按钮 + 删除）
  void _showFriendCard(
      BuildContext context, WidgetRef ref, Friend friend) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _FriendCardSheet(friend: friend, ref: ref),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 好友名片面板
// ═══════════════════════════════════════════════════════════════════════

class _FriendCardSheet extends ConsumerWidget {
  final Friend friend;
  final WidgetRef ref;

  const _FriendCardSheet({required this.friend, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(paddingHorizontal),
      decoration: const BoxDecoration(
        color: colorGlassBackground,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(radiusCard)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽条
          Center(
            child: Container(
              width: 36.0,
              height: 4.0,
              margin: const EdgeInsets.only(bottom: 20.0),
              decoration: BoxDecoration(
                color: colorNeutral.withAlpha(77),
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),

          // 头像
          ColorAvatar(
            nickname: friend.nickname,
            size: 72.0,
            borderRadius: 32.0,
          ),
          const SizedBox(height: 12.0),

          // 昵称
          Text(friend.nickname, style: styleTitle2),
          const SizedBox(height: 4.0),

          // 状态 + ID
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8.0,
                height: 8.0,
                decoration: BoxDecoration(
                  color: friend.isInCall
                      ? colorWarning
                      : friend.isOnline
                          ? colorSuccess
                          : colorNeutral,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6.0),
              Text(
                friend.isInCall
                    ? '通话中'
                    : friend.isOnline
                        ? '在线'
                        : '离线',
                style: styleCaption.copyWith(
                  color: friend.isInCall
                      ? colorWarning
                      : friend.isOnline
                          ? colorSuccess
                          : colorNeutral,
                ),
              ),
              const SizedBox(width: 12.0),
              Text(
                'ID: ${friend.uid.substring(0, 8)}...',
                style: styleSmall.copyWith(color: colorNeutral),
              ),
            ],
          ),
          const SizedBox(height: 20.0),

          // 操作按钮
          if (friend.isOnline && !friend.isInCall) ...[
            SizedBox(
              width: double.infinity,
              child: GlassButton(
                label: '视频通话',
                icon: Icons.videocam_rounded,
                type: GlassButtonType.accent,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _callFriend(context, ref, friend);
                },
              ),
            ),
            const SizedBox(height: 12.0),
          ],
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: '删除好友',
              icon: Icons.delete_outline_rounded,
              type: GlassButtonType.danger,
              onPressed: () {
                Navigator.of(context).pop();
                _confirmDeleteFriend(context, ref, friend);
              },
            ),
          ),
          const SizedBox(height: 24.0),
        ],
      ),
    );
  }

  Future<void> _callFriend(
    BuildContext context,
    WidgetRef ref,
    Friend friend,
  ) async {
    final settings = ref.read(settingsProvider);
    if (!settings.mobileWarningShown) {
      final isMobile = await ConnectivityService.isOnMobileData();
      if (isMobile && context.mounted) {
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('流量提醒'),
            content: const Text(
              '您当前正在使用移动数据通话，可能会消耗较多流量。\n\n'
              '• 10 分钟通话约消耗 120 MB\n'
              '• 建议在 Wi-Fi 环境下使用以获得最佳体验',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('继续通话'),
              ),
              TextButton(
                onPressed: () async {
                  await ref.read(settingsProvider.notifier).saveAllSettings(
                      settings.copyWith(mobileWarningShown: true));
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                },
                child: const Text('继续，不再提醒'),
              ),
            ],
          ),
        );
        if (result != true) return;
      }
    }

    if (context.mounted) {
      try {
        await ref
            .read(callProvider.notifier)
            .startFriendCall(friend.uid, friend.nickname);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('发起呼叫失败: $e'),
              backgroundColor: colorDanger,
            ),
          );
        }
      }
    }
  }

  void _confirmDeleteFriend(
    BuildContext context,
    WidgetRef ref,
    Friend friend,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定要删除"${friend.nickname}"吗？\n删除后双方将从好友列表中移除对方。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(friendProvider.notifier).removeFriend(friend.uid);
            },
            style: TextButton.styleFrom(foregroundColor: colorDanger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 通用脉动圆点组件
// ═══════════════════════════════════════════════════════════════════════

class _PulsingDot extends StatefulWidget {
  final double size;
  final double dotSize;

  const _PulsingDot({
    this.size = 48.0,
    this.dotSize = 16.0,
  });

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorAccent.withAlpha(40),
          border:
              Border.all(color: colorAccent.withAlpha(80), width: 2.0),
        ),
        child: Center(
          child: Container(
            width: widget.dotSize,
            height: widget.dotSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: colorAccent,
            ),
          ),
        ),
      ),
    );
  }
}
