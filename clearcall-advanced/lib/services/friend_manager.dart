import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';

import '../models/friend.dart';
import 'signaling/signaling_service.dart';

/// 好友系统管理器
///
/// 管理好友相关的所有业务逻辑：
/// - 用户节点创建和维护
/// - 在线状态同步（前台/后台/断连）
/// - 好友申请发送/同意/拒绝
/// - 好友列表获取
/// - 好友删除（双向）
class FriendManager {
  final Logger _log = Logger('FriendManager');

  /// 信令服务
  final SignalingService _signaling;

  /// 当前用户 ID
  final String _localUid;

  /// 当前用户昵称
  String _localNickname;

  /// 在线状态变化回调（用于 UI 更新）
  void Function(OnlineStatus status)? onStatusChanged;

  /// 好友申请变化回调
  void Function(List<FriendRequest> requests)? onFriendRequestsChanged;

  /// 好友列表变化回调
  void Function(List<Friend> friends)? onFriendsChanged;

  /// 当前好友列表（内存缓存）
  List<Friend> _friends = [];

  /// 当前待处理好友申请
  final List<FriendRequest> _pendingRequests = [];

  /// 好友状态监听订阅
  StreamSubscription? _statusSubscription;

  /// 好友申请监听订阅
  StreamSubscription? _requestSubscription;

  FriendManager({
    required SignalingService signaling,
    required String localUid,
    required String localNickname,
  })  : _signaling = signaling,
        _localUid = localUid,
        _localNickname = localNickname;

  // ═══════════════════════════════════════════════════════════
  // 公共属性
  // ═══════════════════════════════════════════════════════════

  List<Friend> get friends => List.unmodifiable(_friends);
  List<FriendRequest> get pendingRequests =>
      List.unmodifiable(_pendingRequests);

  // ═══════════════════════════════════════════════════════════
  // 用户节点管理（3.1）
  // ═══════════════════════════════════════════════════════════

  /// 初始化用户节点并设置在线状态
  ///
  /// 在 Firebase 初始化完成后调用。
  /// - 创建或更新 /users/{uid}/ 节点
  /// - 设置 onDisconnect 自动标记离线
  /// - 标记在线状态
  Future<void> initializeUserNode() async {
    try {
      // 1. 设置断连保护（onDisconnect 是最重要的，必须在设置在线之前配好）
      await _signaling.setDisconnectCleanup(_localUid);

      // 2. 设置在线状态（同时写入昵称）
      await _signaling.setOnlineStatus(_localUid, OnlineStatus.online);

      // 3. 确保用户节点有昵称（首次或昵称变更后更新）
      _log.info('用户节点初始化完成: $_localUid');
    } catch (e) {
      _log.severe('用户节点初始化失败', e);
    }
  }

  /// 更新本地昵称（同步到 Firebase）
  Future<void> updateNickname(String newNickname) async {
    _localNickname = newNickname;
    try {
      await _signaling.setOnlineStatus(_localUid, OnlineStatus.online);
      _log.info('昵称更新: $newNickname');
    } catch (e) {
      _log.severe('昵称同步失败', e);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 在线状态管理（3.2）
  // ═══════════════════════════════════════════════════════════

  /// 设置前台在线
  Future<void> setOnline() async {
    try {
      await _signaling.setOnlineStatus(_localUid, OnlineStatus.online);
      _log.info('状态: 在线');
    } catch (e) {
      _log.severe('设置在线状态失败', e);
    }
  }

  /// 设置离线
  Future<void> setOffline() async {
    try {
      await _signaling.setOnlineStatus(_localUid, OnlineStatus.offline);
      _log.info('状态: 离线');
    } catch (e) {
      _log.severe('设置离线状态失败', e);
    }
  }

  /// 设置通话中
  Future<void> setInCall() async {
    try {
      await _signaling.setOnlineStatus(_localUid, OnlineStatus.inCall);
      _log.info('状态: 通话中');
    } catch (e) {
      _log.severe('设置通话中状态失败', e);
    }
  }

  /// 开始监听好友在线状态变化
  void startListeningFriendStatus() {
    _stopListeningFriendStatus();

    final friendUids = _friends.map((f) => f.uid).toList();
    if (friendUids.isEmpty) return;

    _statusSubscription = _signaling
        .onFriendsStatusChange(friendUids)
        .listen((statusMap) {
      var changed = false;
      for (final entry in statusMap.entries) {
        final index = _friends.indexWhere((f) => f.uid == entry.key);
        if (index >= 0) {
          _friends[index] = _friends[index].copyWith(status: entry.value);
          changed = true;
        }
      }
      if (changed) {
        onFriendsChanged?.call(_friends);
      }
    });
  }

  void _stopListeningFriendStatus() {
    _statusSubscription?.cancel();
    _statusSubscription = null;
  }

  // ═══════════════════════════════════════════════════════════
  // 好友列表（3.7）
  // ═══════════════════════════════════════════════════════════

  /// 加载好友列表
  Future<void> loadFriends() async {
    try {
      _friends = await _signaling.getFriends(_localUid);
      onFriendsChanged?.call(_friends);

      // 加载后开启状态监听
      startListeningFriendStatus();
      _log.info('好友列表加载完成: ${_friends.length} 人');
    } catch (e) {
      _log.severe('加载好友列表失败', e);
    }
  }

  /// 搜索过滤好友
  List<Friend> searchFriends(String query) {
    if (query.isEmpty) return _friends;
    final lowerQuery = query.toLowerCase();
    return _friends.where((f) {
      return f.nickname.toLowerCase().contains(lowerQuery) ||
          f.uid.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 好友申请（3.3）
  // ═══════════════════════════════════════════════════════════

  /// 生成 8 位十六进制验证 token
  static String generateToken() {
    final random = Random.secure();
    return List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  /// 发送好友申请
  Future<void> sendFriendRequest(String targetUid, String targetToken) async {
    try {
      final token = generateToken();
      await _signaling.sendFriendRequest(
        _localUid,
        targetUid,
        _localNickname,
        token,
      );
      _log.info('好友申请已发送: $_localUid -> $targetUid');
    } catch (e) {
      _log.severe('发送好友申请失败', e);
      rethrow;
    }
  }

  /// 开始监听好友申请
  void startListeningFriendRequests() {
    _stopListeningFriendRequests();

    _requestSubscription =
        _signaling.onFriendRequest(_localUid).listen((request) {
      // 只处理 pending 状态的请求
      if (request.status == FriendRequestStatus.pending) {
        final exists =
            _pendingRequests.any((r) => r.fromUid == request.fromUid);
        if (!exists) {
          _pendingRequests.add(request);
          onFriendRequestsChanged?.call(_pendingRequests);
          _log.info('收到好友申请: ${request.nickname} (${request.fromUid})');
        }
      }
    });
  }

  void _stopListeningFriendRequests() {
    _requestSubscription?.cancel();
    _requestSubscription = null;
  }

  /// 同意好友申请
  Future<void> acceptFriendRequest(String fromUid) async {
    try {
      await _signaling.acceptFriendRequest(fromUid, _localUid);

      // 从待处理列表中移除
      _pendingRequests.removeWhere((r) => r.fromUid == fromUid);
      onFriendRequestsChanged?.call(_pendingRequests);

      // 重新加载好友列表
      await loadFriends();
      _log.info('好友申请已同意: $fromUid');
    } catch (e) {
      _log.severe('同意好友申请失败', e);
      rethrow;
    }
  }

  /// 拒绝好友申请
  Future<void> rejectFriendRequest(String fromUid) async {
    try {
      await _signaling.rejectFriendRequest(fromUid, _localUid);

      // 从待处理列表中移除
      _pendingRequests.removeWhere((r) => r.fromUid == fromUid);
      onFriendRequestsChanged?.call(_pendingRequests);
      _log.info('好友申请已拒绝: $fromUid');
    } catch (e) {
      _log.severe('拒绝好友申请失败', e);
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 好友删除（3.8）
  // ═══════════════════════════════════════════════════════════

  /// 删除好友（双向清理）
  Future<void> removeFriend(String friendUid) async {
    try {
      await _signaling.removeFriend(_localUid, friendUid);

      // 从本地列表移除
      _friends.removeWhere((f) => f.uid == friendUid);
      onFriendsChanged?.call(_friends);
      _log.info('好友已删除: $friendUid');
    } catch (e) {
      _log.severe('删除好友失败', e);
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 生命周期管理
  // ═══════════════════════════════════════════════════════════

  /// 检查好友是否在线
  bool isFriendOnline(String friendUid) {
    final friend = _friends.firstWhere(
      (f) => f.uid == friendUid,
      orElse: () => Friend(uid: friendUid, nickname: '未知'),
    );
    return friend.isOnline;
  }

  /// 清理资源
  void dispose() {
    _stopListeningFriendStatus();
    _stopListeningFriendRequests();
    _log.info('FriendManager 已清理');
  }
}
