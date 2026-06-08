import 'package:flutter_test/flutter_test.dart';

import 'package:clearcall/models/room.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  // Room 模型测试
  // ═══════════════════════════════════════════════════════════

  group('Room 模型', () {
    test('构造基础 Room 对象', () {
      final room = Room(
        roomId: '123456',
        creatorUid: 'creator-uuid',
        createdAt: DateTime(2026, 6, 9),
      );

      expect(room.roomId, equals('123456'));
      expect(room.creatorUid, equals('creator-uuid'));
      expect(room.status, equals(RoomStatus.waiting)); // 默认等待中
      expect(room.participantUids, isEmpty);
      expect(room.isFull, isFalse);
      expect(room.isEmpty, isTrue);
    });

    test('isFull — 参与者 >= 3 时为 true', () {
      final room = Room(
        roomId: '123456',
        creatorUid: 'creator',
        createdAt: DateTime.now(),
        participantUids: ['u1', 'u2', 'u3'],
      );
      expect(room.isFull, isTrue);
    });

    test('isFull — 参与者 = 2 时为 false', () {
      final room = Room(
        roomId: '123456',
        creatorUid: 'creator',
        createdAt: DateTime.now(),
        participantUids: ['u1', 'u2'],
      );
      expect(room.isFull, isFalse);
    });

    test('isFull — 参与者 = 0 时为 false', () {
      final room = Room(
        roomId: '123456',
        creatorUid: 'creator',
        createdAt: DateTime.now(),
      );
      expect(room.isFull, isFalse);
    });

    test('isEmpty — 无参与者时为 true', () {
      final room = Room(
        roomId: '123456',
        creatorUid: 'creator',
        createdAt: DateTime.now(),
      );
      expect(room.isEmpty, isTrue);
    });

    test('isEmpty — 有参与者时为 false', () {
      final room = Room(
        roomId: '123456',
        creatorUid: 'creator',
        createdAt: DateTime.now(),
        participantUids: ['u1'],
      );
      expect(room.isEmpty, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // Room JSON 序列化测试
  // ═══════════════════════════════════════════════════════════

  group('Room JSON 序列化', () {
    test('fromJson — 完整 JSON 正确解析', () {
      final json = {
        'roomId': '987654',
        'creator': 'creator-uuid',
        'createdAt': 1717939200000,
        'status': 'waiting',
        'participants': {
          'u1': true,
          'u2': true,
        },
      };

      final room = Room.fromJson(json);

      expect(room.roomId, equals('987654'));
      expect(room.creatorUid, equals('creator-uuid'));
      expect(room.createdAt, equals(DateTime.fromMillisecondsSinceEpoch(1717939200000)));
      expect(room.status, equals(RoomStatus.waiting));
      expect(room.participantUids, containsAll(['u1', 'u2']));
      expect(room.participantUids.length, equals(2));
    });

    test('fromJson — status: active 正确解析', () {
      final json = {
        'roomId': '111111',
        'creator': 'c1',
        'createdAt': 1717939200000,
        'status': 'active',
      };
      final room = Room.fromJson(json);
      expect(room.status, equals(RoomStatus.active));
    });

    test('fromJson — status: closed 正确解析', () {
      final json = {
        'roomId': '111111',
        'creator': 'c1',
        'createdAt': 1717939200000,
        'status': 'closed',
      };
      final room = Room.fromJson(json);
      expect(room.status, equals(RoomStatus.closed));
    });

    test('fromJson — 缺少 participants 使用空列表', () {
      final json = {
        'roomId': '111111',
        'creator': 'c1',
        'createdAt': 1717939200000,
      };
      final room = Room.fromJson(json);
      expect(room.participantUids, isEmpty);
    });

    test('fromJson — null participants 使用空列表', () {
      final json = {
        'roomId': '111111',
        'creator': 'c1',
        'createdAt': 1717939200000,
        'participants': null,
      };
      final room = Room.fromJson(json);
      expect(room.participantUids, isEmpty);
    });

    test('fromJson — 缺少 status 默认 waiting', () {
      final json = {
        'roomId': '111111',
        'creator': 'c1',
        'createdAt': 1717939200000,
      };
      final room = Room.fromJson(json);
      expect(room.status, equals(RoomStatus.waiting));
    });

    test('fromJson — 非法 status 回退为 waiting', () {
      final json = {
        'roomId': '111111',
        'creator': 'c1',
        'createdAt': 1717939200000,
        'status': 'unknown-status',
      };
      final room = Room.fromJson(json);
      expect(room.status, equals(RoomStatus.waiting));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // RoomEvent 模型测试
  // ═══════════════════════════════════════════════════════════

  group('RoomEvent 模型', () {
    test('构造 participantJoined 事件', () {
      final event = RoomEvent(
        type: RoomEventType.participantJoined,
        userId: 'user-123',
        timestamp: DateTime(2026, 6, 9),
      );
      expect(event.type, equals(RoomEventType.participantJoined));
      expect(event.userId, equals('user-123'));
      expect(event.sdp, isNull);
      expect(event.candidate, isNull);
    });

    test('构造 offerReceived 事件 — 含 SDP 数据', () {
      final sdpData = {'type': 'offer', 'sdp': 'v=0...'};
      final event = RoomEvent(
        type: RoomEventType.offerReceived,
        userId: 'user-456',
        sdp: sdpData,
        timestamp: DateTime(2026, 6, 9),
      );
      expect(event.type, equals(RoomEventType.offerReceived));
      expect(event.sdp, equals(sdpData));
    });

    test('构造 iceCandidateReceived 事件 — 含 ICE 数据', () {
      final iceData = {
        'candidate': 'candidate:...',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      };
      final event = RoomEvent(
        type: RoomEventType.iceCandidateReceived,
        userId: 'user-789',
        candidate: iceData,
        timestamp: DateTime(2026, 6, 9),
      );
      expect(event.type, equals(RoomEventType.iceCandidateReceived));
      expect(event.candidate, equals(iceData));
    });

    test('toJson/fromJson — 往返转换一致', () {
      final sdp = {'type': 'offer', 'sdp': 'v=0...'};
      final original = RoomEvent(
        type: RoomEventType.offerReceived,
        userId: 'user-abc',
        sdp: sdp,
        timestamp: DateTime(2026, 6, 9, 12, 0),
      );

      final json = original.toJson();
      final restored = RoomEvent.fromJson(json);

      expect(restored.type, equals(original.type));
      expect(restored.userId, equals(original.userId));
      expect(restored.sdp, equals(original.sdp));
    });

    test('fromJson — 缺乏 type 的 JSON 回退为 participantJoined', () {
      final event = RoomEvent.fromJson({'userId': 'u1', 'timestamp': 1717939200000});
      expect(event.type, equals(RoomEventType.participantJoined));
    });

    test('fromJson — 无 timestamp 使用当前时间', () {
      final before = DateTime.now();
      final event = RoomEvent.fromJson({'type': 'participantJoined'});
      // 时间戳应在构造时刻附近
      expect(event.timestamp.isAfter(before.subtract(const Duration(seconds: 5))), isTrue);
      expect(event.timestamp.isBefore(before.add(const Duration(seconds: 5))), isTrue);
    });

    test('toJson — 生成合法 JSON', () {
      final event = RoomEvent(
        type: RoomEventType.roomClosed,
        timestamp: DateTime(2026, 6, 9),
      );
      final json = event.toJson();
      expect(json['type'], equals('roomClosed'));
      expect(json['userId'], isNull);
      expect(json['timestamp'], isA<int>());
    });
  });

  // ═══════════════════════════════════════════════════════════
  // RoomEventType 枚举测试
  // ═══════════════════════════════════════════════════════════

  group('RoomEventType 枚举', () {
    test('包含 6 种事件类型', () {
      expect(RoomEventType.values.length, equals(6));
    });

    test('名称可转为字符串', () {
      expect(RoomEventType.participantJoined.name, equals('participantJoined'));
      expect(RoomEventType.participantLeft.name, equals('participantLeft'));
      expect(RoomEventType.roomClosed.name, equals('roomClosed'));
      expect(RoomEventType.offerReceived.name, equals('offerReceived'));
      expect(RoomEventType.answerReceived.name, equals('answerReceived'));
      expect(RoomEventType.iceCandidateReceived.name, equals('iceCandidateReceived'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // RoomStatus 枚举测试
  // ═══════════════════════════════════════════════════════════

  group('RoomStatus 枚举', () {
    test('包含 3 种状态', () {
      expect(RoomStatus.values.length, equals(3));
      expect(RoomStatus.values, contains(RoomStatus.waiting));
      expect(RoomStatus.values, contains(RoomStatus.active));
      expect(RoomStatus.values, contains(RoomStatus.closed));
    });
  });
}
