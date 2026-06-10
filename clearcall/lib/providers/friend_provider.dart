import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend.dart';
import '../services/friend_manager.dart';
import '../services/signaling/signaling_service.dart';
import 'settings_provider.dart';
import 'signaling_provider.dart';

/// 好友系统状态
class FriendState {
  /// 好友列表
  final List<Friend> friends;

  /// 待处理的好友申请
  final List<FriendRequest> pendingRequests;

  /// 是否正在加载
  final bool isLoading;

  /// 搜索关键词
  final String searchQuery;

  /// 错误信息
  final String? errorMessage;

  const FriendState({
    this.friends = const [],
    this.pendingRequests = const [],
    this.isLoading = false,
    this.searchQuery = '',
    this.errorMessage,
  });

  /// 根据搜索关键词过滤后的好友列表
  List<Friend> get filteredFriends {
    if (searchQuery.isEmpty) return friends;
    final lowerQuery = searchQuery.toLowerCase();
    return friends.where((f) {
      return f.nickname.toLowerCase().contains(lowerQuery) ||
          f.uid.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// 待处理申请数量
  int get pendingCount => pendingRequests.length;

  FriendState copyWith({
    List<Friend>? friends,
    List<FriendRequest>? pendingRequests,
    bool? isLoading,
    String? searchQuery,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FriendState(
      friends: friends ?? this.friends,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 好友系统状态管理器
///
/// 封装 FriendManager，通过 Riverpod 提供响应式状态。
class FriendNotifier extends StateNotifier<FriendState> {
  final SignalingService _signaling;
  final String _localUid;
  final String _localNickname;

  /// 好友系统管理器
  late final FriendManager _friendManager;

  /// 是否已初始化
  bool _initialized = false;

  FriendNotifier({
    required SignalingService signaling,
    required String localUid,
    required String localNickname,
  })  : _signaling = signaling,
        _localUid = localUid,
        _localNickname = localNickname,
        super(const FriendState());

  /// 初始化用户节点并加载好友数据
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      state = state.copyWith(isLoading: true);

      _friendManager = FriendManager(
        signaling: _signaling,
        localUid: _localUid,
        localNickname: _localNickname,
      );

      // 绑定回调
      _friendManager.onFriendsChanged = (friends) {
        state = state.copyWith(friends: friends);
      };

      _friendManager.onFriendRequestsChanged = (requests) {
        state = state.copyWith(pendingRequests: requests);
      };

      // 初始化用户节点（创建 /users/{uid}/ + onDisconnect）
      await _friendManager.initializeUserNode();

      // 启动好友申请监听
      _friendManager.startListeningFriendRequests();

      // 加载好友列表
      await _friendManager.loadFriends();

      _initialized = true;
    } catch (e) {
      state = state.copyWith(errorMessage: '好友系统初始化失败: $e');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 确保已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('好友系统尚未初始化');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 好友申请操作
  // ═══════════════════════════════════════════════════════════

  /// 发送好友申请
  Future<void> sendFriendRequest(String targetUid, String nickname, String token) async {
    _ensureInitialized();
    try {
      await _friendManager.sendFriendRequest(targetUid, nickname, token);
    } catch (e) {
      state = state.copyWith(errorMessage: '发送好友申请失败: $e');
    }
  }

  /// 同意好友申请
  Future<void> acceptFriendRequest(String fromUid) async {
    _ensureInitialized();
    try {
      await _friendManager.acceptFriendRequest(fromUid);
    } catch (e) {
      state = state.copyWith(errorMessage: '同意好友申请失败: $e');
    }
  }

  /// 拒绝好友申请
  Future<void> rejectFriendRequest(String fromUid) async {
    _ensureInitialized();
    try {
      await _friendManager.rejectFriendRequest(fromUid);
    } catch (e) {
      state = state.copyWith(errorMessage: '拒绝好友申请失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 好友列表操作
  // ═══════════════════════════════════════════════════════════

  /// 删除好友
  Future<void> removeFriend(String friendUid) async {
    _ensureInitialized();
    try {
      await _friendManager.removeFriend(friendUid);
    } catch (e) {
      state = state.copyWith(errorMessage: '删除好友失败: $e');
    }
  }

  /// 更新搜索关键词
  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  // ═══════════════════════════════════════════════════════════
  // 在线状态操作
  // ═══════════════════════════════════════════════════════════

  /// 设置在线
  Future<void> setOnline() async {
    if (!_initialized) return;
    await _friendManager.setOnline();
  }

  /// 设置离线
  Future<void> setOffline() async {
    if (!_initialized) return;
    await _friendManager.setOffline();
  }

  /// 设置通话中
  Future<void> setInCall() async {
    if (!_initialized) return;
    await _friendManager.setInCall();
  }

  /// 更新本地昵称（同步到 Firebase）
  Future<void> updateNickname(String newNickname) async {
    if (!_initialized) return;
    await _friendManager.updateNickname(newNickname);
  }

  /// 获取 FriendManager 实例（供外部使用）
  FriendManager get friendManager {
    _ensureInitialized();
    return _friendManager;
  }

  @override
  void dispose() {
    _friendManager.dispose();
    super.dispose();
  }
}

/// 好友 Provider
///
/// 持有 FriendNotifier 实例，管理好友列表和申请状态。
final friendProvider =
    StateNotifierProvider<FriendNotifier, FriendState>((ref) {
  final settings = ref.read(settingsProvider);
  final signaling = ref.read(signalingProvider);

  final notifier = FriendNotifier(
    signaling: signaling,
    localUid: settings.localId,
    localNickname: settings.nickname,
  );

  // 初始化由 AppRoot._initializeServices() 统一控制时序
  return notifier;
});
