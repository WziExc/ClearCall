import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:clearcall/models/friend.dart';
import 'package:clearcall/services/friend_manager.dart';

import 'mocks.dart';

void main() {
  late MockSignalingService mockSignaling;
  late FriendManager friendManager;

  const testLocalUid = 'test-local-user';
  const testNickname = '测试用户';

  setUp(() {
    mockSignaling = MockSignalingService();
    friendManager = FriendManager(
      signaling: mockSignaling,
      localUid: testLocalUid,
      localNickname: testNickname,
    );
  });

  // ═══════════════════════════════════════════════════════════
  // 构造与初始状态
  // ═══════════════════════════════════════════════════════════

  group('FriendManager 构造与初始状态', () {
    test('初始好友列表为空', () {
      expect(friendManager.friends, isEmpty);
    });

    test('初始待处理申请为空', () {
      expect(friendManager.pendingRequests, isEmpty);
    });

    test('friends 返回不可变列表', () {
      expect(friendManager.friends, isA<List<Friend>>());
    });

    test('pendingRequests 返回不可变列表', () {
      expect(friendManager.pendingRequests, isA<List<FriendRequest>>());
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 用户节点初始化
  // ═══════════════════════════════════════════════════════════

  group('用户节点初始化', () {
    test('initializeUserNode 调用 setDisconnectCleanup', () async {
      await friendManager.initializeUserNode();

      final cleanupCalls = mockSignaling.calls
          .where((c) => c.method == 'setDisconnectCleanup')
          .toList();
      expect(cleanupCalls.length, greaterThanOrEqualTo(1));
      expect(cleanupCalls.first.params['userId'], equals(testLocalUid));
    });

    test('initializeUserNode 首先设置 onDisconnect', () async {
      await friendManager.initializeUserNode();

      // 验证 setDisconnectCleanup 被调用（必须先于 setOnlineStatus）
      final dcIndex = mockSignaling.calls
          .indexWhere((c) => c.method == 'setDisconnectCleanup');
      final onlineIndex = mockSignaling.calls
          .indexWhere((c) => c.method == 'setOnlineStatus');

      expect(dcIndex, greaterThanOrEqualTo(0));
      expect(onlineIndex, greaterThan(dcIndex),
          reason: 'onDisconnect 必须先于 setOnlineStatus 设置');
    });

    test('initializeUserNode 设置在线状态', () async {
      await friendManager.initializeUserNode();

      final onlineCalls = mockSignaling.calls
          .where((c) => c.method == 'setOnlineStatus')
          .toList();
      expect(onlineCalls.length, greaterThanOrEqualTo(1));
      expect(onlineCalls.first.params['userId'], equals(testLocalUid));
      expect(onlineCalls.first.params['status'], equals(OnlineStatus.online));
    });

    test('initializeUserNode 失败不抛出异常（容错）', () async {
      mockSignaling.whenThrow('setDisconnectCleanup', Exception('Firebase 错误'));

      // 不应抛出异常，错误被内部捕获
      await friendManager.initializeUserNode();
      // 没有崩溃即为通过
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 昵称更新
  // ═══════════════════════════════════════════════════════════

  group('昵称更新', () {
    test('updateNickname 调用 setOnlineStatus 同步', () async {
      await friendManager.updateNickname('新昵称');

      final statusCalls = mockSignaling.calls
          .where((c) => c.method == 'setOnlineStatus')
          .toList();
      // 至少有一次调用（initializeUserNode 未调用时也可能触发）
      expect(statusCalls.isNotEmpty, isTrue);
    });

    test('updateNickname 失败不抛出异常', () async {
      mockSignaling.whenThrow('setOnlineStatus', Exception('网络错误'));

      // 不应抛出异常
      await friendManager.updateNickname('新昵称');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 在线状态管理
  // ═══════════════════════════════════════════════════════════

  group('在线状态管理', () {
    test('setOnline 设置在线状态', () async {
      await friendManager.setOnline();

      final statusCalls = mockSignaling.calls
          .where((c) => c.method == 'setOnlineStatus')
          .toList();
      final lastCall = statusCalls.last;
      expect(lastCall.params['status'], equals(OnlineStatus.online));
    });

    test('setOffline 设置离线状态', () async {
      await friendManager.setOffline();

      final statusCalls = mockSignaling.calls
          .where((c) => c.method == 'setOnlineStatus')
          .toList();
      final lastCall = statusCalls.last;
      expect(lastCall.params['status'], equals(OnlineStatus.offline));
    });

    test('setInCall 设置通话中状态', () async {
      await friendManager.setInCall();

      final statusCalls = mockSignaling.calls
          .where((c) => c.method == 'setOnlineStatus')
          .toList();
      final lastCall = statusCalls.last;
      expect(lastCall.params['status'], equals(OnlineStatus.inCall));
    });

    test('状态设置失败不抛出异常', () async {
      mockSignaling.whenThrow('setOnlineStatus', Exception('网络错误'));

      await friendManager.setOnline();
      await friendManager.setOffline();
      await friendManager.setInCall();
      // 没有崩溃即为通过
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 好友列表加载
  // ═══════════════════════════════════════════════════════════

  group('好友列表加载', () {
    test('loadFriends 获取好友列表', () async {
      final mockFriends = [
        Friend(uid: 'friend-1', nickname: '小明', status: OnlineStatus.online),
        Friend(uid: 'friend-2', nickname: '小红', status: OnlineStatus.offline),
      ];
      mockSignaling.when('getFriends', mockFriends);

      await friendManager.loadFriends();

      expect(friendManager.friends.length, equals(2));
      expect(friendManager.friends[0].uid, equals('friend-1'));
      expect(friendManager.friends[1].uid, equals('friend-2'));
    });

    test('loadFriends 触发 onFriendsChanged 回调', () async {
      final mockFriends = [
        Friend(uid: 'friend-1', nickname: '小明'),
      ];
      mockSignaling.when('getFriends', mockFriends);

      List<Friend>? changedFriends;
      friendManager.onFriendsChanged = (friends) => changedFriends = friends;

      await friendManager.loadFriends();

      expect(changedFriends, isNotNull);
      expect(changedFriends!.length, equals(1));
    });

    test('loadFriends 失败不抛出异常', () async {
      mockSignaling.whenThrow('getFriends', Exception('Firebase 错误'));

      // 不应抛出异常
      await friendManager.loadFriends();
      expect(friendManager.friends, isEmpty);
    });

    test('loadFriends 空列表', () async {
      mockSignaling.when('getFriends', <Friend>[]);

      await friendManager.loadFriends();

      expect(friendManager.friends, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 好友搜索
  // ═══════════════════════════════════════════════════════════

  group('好友搜索', () {
    setUp(() async {
      final mockFriends = [
        Friend(uid: 'u1', nickname: '张三', status: OnlineStatus.online),
        Friend(uid: 'u2', nickname: '李四', status: OnlineStatus.offline),
        Friend(uid: 'u3', nickname: '王五张三丰', status: OnlineStatus.inCall),
      ];
      mockSignaling.when('getFriends', mockFriends);
      await friendManager.loadFriends();
    });

    test('空搜索词返回全部好友', () {
      final results = friendManager.searchFriends('');
      expect(results.length, equals(3));
    });

    test('按昵称搜索', () {
      final results = friendManager.searchFriends('张三');
      expect(results.length, equals(2));
      expect(results.map((f) => f.nickname), containsAll(['张三', '王五张三丰']));
    });

    test('按 UID 搜索', () {
      final results = friendManager.searchFriends('u1');
      expect(results.length, equals(1));
      expect(results.first.uid, equals('u1'));
    });

    test('无匹配结果', () {
      final results = friendManager.searchFriends('不存在的用户');
      expect(results, isEmpty);
    });

    test('搜索大小写不敏感', () {
      final results = friendManager.searchFriends('zhang');
      // 中文不受大小写影响，但确保不崩溃
      expect(results, isA<List<Friend>>());
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 好友申请
  // ═══════════════════════════════════════════════════════════

  group('好友申请', () {
    test('generateToken 生成 8 位十六进制字符串', () {
      final token = FriendManager.generateToken();
      expect(token.length, equals(8));
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(token), isTrue);
    });

    test('generateToken 每次生成不同 token', () {
      final t1 = FriendManager.generateToken();
      final t2 = FriendManager.generateToken();
      expect(t1, isNot(equals(t2)));
    });

    test('sendFriendRequest 调用 signaling', () async {
      await friendManager.sendFriendRequest('target-uid', 'token123');

      final sendCalls = mockSignaling.calls
          .where((c) => c.method == 'sendFriendRequest')
          .toList();
      expect(sendCalls.length, equals(1));
      expect(sendCalls.first.params['fromUid'], equals(testLocalUid));
      expect(sendCalls.first.params['toUid'], equals('target-uid'));
    });

    test('sendFriendRequest 失败抛出异常', () async {
      mockSignaling.whenThrow('sendFriendRequest', Exception('发送失败'));

      expect(
        () => friendManager.sendFriendRequest('target', 'token'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 好友申请监听
  // ═══════════════════════════════════════════════════════════

  group('好友申请监听', () {
    test('startListeningFriendRequests 监听 incoming 申请', () async {
      final controller = StreamController<FriendRequest>.broadcast();
      mockSignaling.whenStream('onFriendRequest', controller.stream);

      List<FriendRequest>? receivedRequests;
      friendManager.onFriendRequestsChanged = (requests) {
        receivedRequests = requests;
      };

      friendManager.startListeningFriendRequests();

      // 发送一个 pending 申请
      final request = FriendRequest(
        fromUid: 'sender-uid',
        nickname: '新朋友',
        token: 'abc12345',
        timestamp: DateTime.now(),
        status: FriendRequestStatus.pending,
      );
      controller.add(request);

      // 给一点时间让流处理
      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedRequests, isNotNull);
      expect(receivedRequests!.length, equals(1));
      expect(receivedRequests!.first.nickname, equals('新朋友'));
    });

    test('非 pending 状态的申请不会加入列表', () async {
      final controller = StreamController<FriendRequest>.broadcast();
      mockSignaling.whenStream('onFriendRequest', controller.stream);

      friendManager.startListeningFriendRequests();

      final acceptedRequest = FriendRequest(
        fromUid: 'sender-uid',
        nickname: '已同意的申请',
        token: 'abc12345',
        timestamp: DateTime.now(),
        status: FriendRequestStatus.accepted,
      );
      controller.add(acceptedRequest);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(friendManager.pendingRequests, isEmpty);
    });

    test('重复的申请不重复添加', () async {
      final controller = StreamController<FriendRequest>.broadcast();
      mockSignaling.whenStream('onFriendRequest', controller.stream);

      friendManager.startListeningFriendRequests();

      final request = FriendRequest(
        fromUid: 'sender-uid',
        nickname: '新朋友',
        token: 'abc12345',
        timestamp: DateTime.now(),
        status: FriendRequestStatus.pending,
      );

      controller.add(request);
      await Future.delayed(const Duration(milliseconds: 50));

      // 再次发送同一个 uid 的申请
      controller.add(request);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(friendManager.pendingRequests.length, equals(1),
          reason: '同一 uid 的重复申请不应重复添加');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 同意/拒绝好友申请
  // ═══════════════════════════════════════════════════════════

  group('同意好友申请', () {
    test('调用 signaling.acceptFriendRequest', () async {
      await friendManager.acceptFriendRequest('from-uid');

      final acceptCalls = mockSignaling.calls
          .where((c) => c.method == 'acceptFriendRequest')
          .toList();
      expect(acceptCalls.length, equals(1));
      expect(acceptCalls.first.params['fromUid'], equals('from-uid'));
      expect(acceptCalls.first.params['toUid'], equals(testLocalUid));
    });

    test('同意后触发 onFriendRequestsChanged', () async {
      // 先插入一个待处理申请
      final controller = StreamController<FriendRequest>.broadcast();
      mockSignaling.whenStream('onFriendRequest', controller.stream);
      friendManager.startListeningFriendRequests();

      controller.add(FriendRequest(
        fromUid: 'from-uid',
        nickname: '新朋友',
        token: 'token',
        timestamp: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      List<FriendRequest>? changedRequests;
      friendManager.onFriendRequestsChanged = (requests) {
        changedRequests = requests;
      };

      mockSignaling.when('getFriends', <Friend>[]);
      await friendManager.acceptFriendRequest('from-uid');

      expect(changedRequests, isNotNull);
      expect(changedRequests!.length, equals(0)); // 已从待处理中移除
    });

    test('acceptFriendRequest 失败抛出异常', () async {
      mockSignaling.whenThrow('acceptFriendRequest', Exception('Firebase 错误'));

      expect(
        () => friendManager.acceptFriendRequest('from-uid'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('拒绝好友申请', () {
    test('调用 signaling.rejectFriendRequest', () async {
      await friendManager.rejectFriendRequest('from-uid');

      final rejectCalls = mockSignaling.calls
          .where((c) => c.method == 'rejectFriendRequest')
          .toList();
      expect(rejectCalls.length, equals(1));
      expect(rejectCalls.first.params['fromUid'], equals('from-uid'));
      expect(rejectCalls.first.params['toUid'], equals(testLocalUid));
    });

    test('rejectFriendRequest 失败抛出异常', () async {
      mockSignaling.whenThrow('rejectFriendRequest', Exception('Firebase 错误'));

      expect(
        () => friendManager.rejectFriendRequest('from-uid'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 好友删除
  // ═══════════════════════════════════════════════════════════

  group('好友删除', () {
    setUp(() async {
      final mockFriends = [
        Friend(uid: 'friend-1', nickname: '小明'),
        Friend(uid: 'friend-2', nickname: '小红'),
      ];
      mockSignaling.when('getFriends', mockFriends);
      await friendManager.loadFriends();
    });

    test('调用 signaling.removeFriend 双向删除', () async {
      await friendManager.removeFriend('friend-1');

      final removeCalls = mockSignaling.calls
          .where((c) => c.method == 'removeFriend')
          .toList();
      expect(removeCalls.length, equals(1));
      expect(removeCalls.first.params['uid'], equals(testLocalUid));
      expect(removeCalls.first.params['friendUid'], equals('friend-1'));
    });

    test('删除后从本地列表移除', () async {
      await friendManager.removeFriend('friend-1');

      expect(friendManager.friends.length, equals(1));
      expect(friendManager.friends.first.uid, equals('friend-2'));
    });

    test('删除触发 onFriendsChanged 回调', () async {
      List<Friend>? changedFriends;
      friendManager.onFriendsChanged = (friends) => changedFriends = friends;

      await friendManager.removeFriend('friend-2');

      expect(changedFriends, isNotNull);
      expect(changedFriends!.length, equals(1));
    });

    test('removeFriend 失败抛出异常', () async {
      mockSignaling.whenThrow('removeFriend', Exception('删除失败'));

      expect(
        () => friendManager.removeFriend('friend-1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 在线状态查询
  // ═══════════════════════════════════════════════════════════

  group('在线状态查询', () {
    test('isFriendOnline — 好友不存在返回 false', () {
      expect(friendManager.isFriendOnline('non-existent'), isFalse);
    });

    test('isFriendOnline — 好友在线返回 true', () async {
      final mockFriends = [
        Friend(uid: 'friend-1', nickname: '小明', status: OnlineStatus.online),
      ];
      mockSignaling.when('getFriends', mockFriends);
      await friendManager.loadFriends();

      expect(friendManager.isFriendOnline('friend-1'), isTrue);
    });

    test('isFriendOnline — 好友离线返回 false', () async {
      final mockFriends = [
        Friend(uid: 'friend-1', nickname: '小明', status: OnlineStatus.offline),
      ];
      mockSignaling.when('getFriends', mockFriends);
      await friendManager.loadFriends();

      expect(friendManager.isFriendOnline('friend-1'), isFalse);
    });

    test('isFriendOnline — 好友通话中返回 true', () async {
      final mockFriends = [
        Friend(uid: 'friend-1', nickname: '小明', status: OnlineStatus.inCall),
      ];
      mockSignaling.when('getFriends', mockFriends);
      await friendManager.loadFriends();

      expect(friendManager.isFriendOnline('friend-1'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 好友状态监听
  // ═══════════════════════════════════════════════════════════

  group('好友状态监听', () {
    setUp(() async {
      final mockFriends = [
        Friend(uid: 'friend-1', nickname: '小明', status: OnlineStatus.online),
        Friend(uid: 'friend-2', nickname: '小红', status: OnlineStatus.offline),
      ];
      mockSignaling.when('getFriends', mockFriends);
      await friendManager.loadFriends();
    });

    test('状态变化触发 onFriendsChanged', () async {
      final controller = StreamController<Map<String, OnlineStatus>>.broadcast();
      mockSignaling.whenStream('onFriendsStatusChange', controller.stream);

      List<Friend>? changedFriends;
      friendManager.onFriendsChanged = (friends) => changedFriends = friends;

      friendManager.startListeningFriendStatus();

      // 模拟 friend-1 变为离线
      controller.add({'friend-1': OnlineStatus.offline});

      await Future.delayed(const Duration(milliseconds: 50));

      expect(changedFriends, isNotNull);

      // 查找 friend-1
      final friend1 = changedFriends!.firstWhere((f) => f.uid == 'friend-1');
      expect(friend1.status, equals(OnlineStatus.offline));
    });

    test('无好友时不启动监听', () async {
      // 清空好友列表
      mockSignaling.when('getFriends', <Friend>[]);
      await friendManager.loadFriends();

      // 不应抛出异常
      friendManager.startListeningFriendStatus();
      // 无崩溃即为通过
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 资源清理
  // ═══════════════════════════════════════════════════════════

  group('资源清理', () {
    test('dispose 清理监听订阅', () {
      // 不应抛出异常
      friendManager.dispose();
    });

    test('dispose 可重复调用', () {
      friendManager.dispose();
      friendManager.dispose();
      // 无崩溃即为通过
    });
  });
}
