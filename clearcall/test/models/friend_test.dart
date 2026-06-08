import 'package:flutter_test/flutter_test.dart';

import 'package:clearcall/models/friend.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // Friend 模型测试
  // ═══════════════════════════════════════════════════════════

  group('Friend 模型', () {
    test('构造基础 Friend 对象', () {
      final friend = Friend(uid: 'test-uid-123', nickname: '测试用户');

      expect(friend.uid, equals('test-uid-123'));
      expect(friend.nickname, equals('测试用户'));
      expect(friend.status, equals(OnlineStatus.offline)); // 默认离线
      expect(friend.lastSeen, isNull);
    });

    test('isOnline — 在线时应为 true', () {
      final friend = Friend(
        uid: 'u1',
        nickname: '小明',
        status: OnlineStatus.online,
      );
      expect(friend.isOnline, isTrue);
    });

    test('isOnline — 通话中时也应为 true', () {
      final friend = Friend(
        uid: 'u1',
        nickname: '小明',
        status: OnlineStatus.inCall,
      );
      expect(friend.isOnline, isTrue);
      expect(friend.isInCall, isTrue);
    });

    test('isOnline — 离线时应为 false', () {
      final friend = Friend(
        uid: 'u1',
        nickname: '小明',
        status: OnlineStatus.offline,
      );
      expect(friend.isOnline, isFalse);
      expect(friend.isInCall, isFalse);
    });

    test('initial — 返回昵称首字母大写', () {
      final friend = Friend(uid: 'u1', nickname: '小明');
      expect(friend.initial, equals('小'));
    });

    test('initial — 空昵称返回 ?', () {
      final friend = Friend(uid: 'u1', nickname: '');
      expect(friend.initial, equals('?'));
    });

    test('initial — 英文昵称返回首字母大写', () {
      final friend = Friend(uid: 'u1', nickname: 'alice');
      expect(friend.initial, equals('A'));
    });

    test('copyWith — 修改昵称', () {
      final friend = Friend(uid: 'u1', nickname: '小明');
      final updated = friend.copyWith(nickname: '大明');
      expect(updated.nickname, equals('大明'));
      expect(updated.uid, equals('u1')); // 其他字段不变
    });

    test('copyWith — 修改在线状态', () {
      final friend = Friend(uid: 'u1', nickname: '小明');
      final updated = friend.copyWith(status: OnlineStatus.inCall);
      expect(updated.status, equals(OnlineStatus.inCall));
    });

    test('copyWith — 多字段同时修改', () {
      final now = DateTime(2026, 6, 9, 12, 0);
      final friend = Friend(uid: 'u1', nickname: '小明');
      final updated = friend.copyWith(
        nickname: '大明',
        status: OnlineStatus.online,
        lastSeen: now,
      );
      expect(updated.nickname, equals('大明'));
      expect(updated.status, equals(OnlineStatus.online));
      expect(updated.lastSeen, equals(now));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // Friend JSON 序列化测试
  // ═══════════════════════════════════════════════════════════

  group('Friend JSON 序列化', () {
    test('fromJson — 完整 JSON 正确解析', () {
      final json = {
        'uid': 'user-abc',
        'nickname': '测试好友',
        'status': 'online',
        'lastSeen': 1717939200000, // 2024-06-09T16:00:00
      };

      final friend = Friend.fromJson(json);

      expect(friend.uid, equals('user-abc'));
      expect(friend.nickname, equals('测试好友'));
      expect(friend.status, equals(OnlineStatus.online));
      expect(friend.lastSeen, equals(DateTime.fromMillisecondsSinceEpoch(1717939200000)));
    });

    test('fromJson — 缺少 nickname 使用默认值', () {
      final json = {
        'uid': 'user-abc',
        'status': 'offline',
      };

      final friend = Friend.fromJson(json);
      expect(friend.nickname, equals('未知'));
    });

    test('fromJson — status: in-call 解析为 OnlineStatus.inCall', () {
      final json = {'uid': 'u1', 'status': 'in-call'};
      final friend = Friend.fromJson(json);
      expect(friend.status, equals(OnlineStatus.inCall));
    });

    test('fromJson — 非法 status 回退为 offline', () {
      final json = {'uid': 'u1', 'status': 'invalid-status'};
      final friend = Friend.fromJson(json);
      expect(friend.status, equals(OnlineStatus.offline));
    });

    test('fromJson — 无 status 字段默认 offline', () {
      final json = {'uid': 'u1'};
      final friend = Friend.fromJson(json);
      expect(friend.status, equals(OnlineStatus.offline));
    });

    test('fromJson — null nickname 使用默认值', () {
      final json = {'uid': 'u1', 'nickname': null};
      final friend = Friend.fromJson(json);
      expect(friend.nickname, equals('未知'));
    });

    test('fromJson — 无 lastSeen 时为 null', () {
      final json = {'uid': 'u1', 'status': 'online'};
      final friend = Friend.fromJson(json);
      expect(friend.lastSeen, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // FriendRequest 模型测试
  // ═══════════════════════════════════════════════════════════

  group('FriendRequest 模型', () {
    test('构造基础 FriendRequest', () {
      final now = DateTime(2026, 6, 9);
      final request = FriendRequest(
        fromUid: 'sender-uid',
        nickname: '申请人',
        token: 'a1b2c3d4',
        timestamp: now,
      );

      expect(request.fromUid, equals('sender-uid'));
      expect(request.nickname, equals('申请人'));
      expect(request.token, equals('a1b2c3d4'));
      expect(request.timestamp, equals(now));
      expect(request.status, equals(FriendRequestStatus.pending)); // 默认待处理
    });

    test('fromJson — 完整 JSON 正确解析', () {
      final json = {
        'fromUid': 'sender-uid',
        'nickname': '申请人',
        'token': 'abcdef01',
        'timestamp': 1717939200000,
        'status': 'pending',
      };

      final request = FriendRequest.fromJson(json);

      expect(request.fromUid, equals('sender-uid'));
      expect(request.nickname, equals('申请人'));
      expect(request.token, equals('abcdef01'));
      expect(request.timestamp, equals(DateTime.fromMillisecondsSinceEpoch(1717939200000)));
      expect(request.status, equals(FriendRequestStatus.pending));
    });

    test('fromJson — 已同意的申请', () {
      final json = {
        'fromUid': 'u1',
        'timestamp': 1717939200000,
        'status': 'accepted',
      };
      final request = FriendRequest.fromJson(json);
      expect(request.status, equals(FriendRequestStatus.accepted));
    });

    test('fromJson — 已拒绝的申请', () {
      final json = {
        'fromUid': 'u1',
        'timestamp': 1717939200000,
        'status': 'rejected',
      };
      final request = FriendRequest.fromJson(json);
      expect(request.status, equals(FriendRequestStatus.rejected));
    });

    test('fromJson — 缺少 nickname 和 token 使用默认值', () {
      final json = {
        'fromUid': 'u1',
        'timestamp': 1717939200000,
      };
      final request = FriendRequest.fromJson(json);
      expect(request.nickname, equals('未知'));
      expect(request.token, equals(''));
    });

    test('fromJson — null 字段处理', () {
      final json = {
        'fromUid': 'u1',
        'nickname': null,
        'token': null,
        'timestamp': 1717939200000,
        'status': null,
      };
      final request = FriendRequest.fromJson(json);
      expect(request.nickname, equals('未知'));
      expect(request.token, equals(''));
      expect(request.status, equals(FriendRequestStatus.pending));
    });

    test('fromJson — 非法 status 回退为 pending', () {
      final json = {
        'fromUid': 'u1',
        'timestamp': 1717939200000,
        'status': 'unknown',
      };
      final request = FriendRequest.fromJson(json);
      expect(request.status, equals(FriendRequestStatus.pending));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // OnlineStatus 枚举测试
  // ═══════════════════════════════════════════════════════════

  group('OnlineStatus 枚举', () {
    test('包含三个状态值', () {
      expect(OnlineStatus.values.length, equals(3));
      expect(OnlineStatus.values, contains(OnlineStatus.online));
      expect(OnlineStatus.values, contains(OnlineStatus.offline));
      expect(OnlineStatus.values, contains(OnlineStatus.inCall));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // FriendRequestStatus 枚举测试
  // ═══════════════════════════════════════════════════════════

  group('FriendRequestStatus 枚举', () {
    test('包含三个状态值', () {
      expect(FriendRequestStatus.values.length, equals(3));
      expect(FriendRequestStatus.values, contains(FriendRequestStatus.pending));
      expect(FriendRequestStatus.values, contains(FriendRequestStatus.accepted));
      expect(FriendRequestStatus.values, contains(FriendRequestStatus.rejected));
    });
  });
}
