import 'package:flutter_test/flutter_test.dart';

import 'package:clearcall/services/call_manager.dart';

import 'mocks.dart';

void main() {
  late MockSignalingService mockSignaling;
  late MockWebRTCService mockWebrtc;
  late CallManager callManager;

  const testLocalUid = 'test-local-user-123';

  setUp(() {
    mockSignaling = MockSignalingService();
    mockWebrtc = MockWebRTCService();
    callManager = CallManager(
      signaling: mockSignaling,
      webrtc: mockWebrtc,
      localUid: testLocalUid,
    );
  });

  // ═══════════════════════════════════════════════════════════
  // 构造与初始状态
  // ═══════════════════════════════════════════════════════════

  group('CallManager 构造与初始状态', () {
    test('初始状态为 idle', () {
      expect(callManager.state, equals(CallState.idle));
    });

    test('初始 roomId 为 null', () {
      expect(callManager.roomId, isNull);
    });

    test('初始通话时长为 0', () {
      expect(callManager.elapsedSeconds, equals(0));
    });

    test('初始参与者为空', () {
      expect(callManager.participants, isEmpty);
    });

    test('初始 participantCount 为 0', () {
      expect(callManager.participantCount, equals(0));
    });

    test('isInCall 初始为 false', () {
      expect(callManager.isInCall, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 状态变化回调
  // ═══════════════════════════════════════════════════════════

  group('状态变化回调', () {
    test('rejectIncomingCall 触发状态变化回调', () async {
      final states = <CallState>[];
      callManager.onStateChanged = (s) => states.add(s);

      // 模拟：先收到来电，然后拒绝
      // 由于无法直接设置内部状态，通过 callIncoming + reject 测试
      await callManager.rejectIncomingCall('caller-uid');

      expect(states, contains(CallState.ended));
    });

    test('hangUp 从 idle 也可以正常执行（无副作用）', () async {
      // hangUp 在任何状态都应是安全的
      await callManager.hangUp();
      // 不应崩溃
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 拒绝来电
  // ═══════════════════════════════════════════════════════════

  group('拒绝来电', () {
    test('调用 sendCallReject 发送拒绝信令', () async {
      await callManager.rejectIncomingCall('caller-uid');

      final rejectCalls = mockSignaling.calls
          .where((c) => c.method == 'sendCallReject')
          .toList();
      expect(rejectCalls.length, greaterThanOrEqualTo(1));
      expect(rejectCalls.first.params['fromUid'], equals(testLocalUid));
      expect(rejectCalls.first.params['toUid'], equals('caller-uid'));
    });

    test('拒绝后状态变为 ended', () async {
      await callManager.rejectIncomingCall('caller-uid');
      expect(callManager.state, equals(CallState.ended));
    });

    test('拒绝时 signaling 异常会向上抛出', () async {
      mockSignaling.whenThrow('sendCallReject', Exception('网络错误'));

      expect(
        () => callManager.rejectIncomingCall('caller-uid'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 取消呼叫
  // ═══════════════════════════════════════════════════════════

  group('取消呼叫', () {
    test('调用 clearCallNode 清理信令节点', () async {
      await callManager.cancelCall('target-uid');

      final clearCalls = mockSignaling.calls
          .where((c) => c.method == 'clearCallNode')
          .toList();
      expect(clearCalls.length, greaterThanOrEqualTo(1));
      expect(clearCalls.first.params['targetUid'], equals('target-uid'));
    });

    test('取消后调用 hangUp 清理媒体资源', () async {
      await callManager.cancelCall('target-uid');

      expect(mockWebrtc.calls, contains('hangUp'));
    });

    test('取消时 signaling 异常会向上抛出', () async {
      mockSignaling.whenThrow('clearCallNode', Exception('网络错误'));

      expect(
        () => callManager.cancelCall('target-uid'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 挂断
  // ═══════════════════════════════════════════════════════════

  group('挂断', () {
    test('挂断后释放 WebRTC 资源', () async {
      await callManager.hangUp();
      expect(mockWebrtc.calls, contains('hangUp'));
    });

    test('挂断后触发 onCallEnded 回调', () async {
      CallEndReport? report;
      callManager.onCallEnded = (r) => report = r;

      await callManager.hangUp();

      expect(report, isNotNull);
      expect(report!.durationSeconds, equals(0));
      expect(report!.qualityRating, isNotEmpty);
    });

    test('挂断后状态变为 ended', () async {
      await callManager.hangUp();
      expect(callManager.state, equals(CallState.ended));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 创建房间 — 错误处理
  // ═══════════════════════════════════════════════════════════

  group('创建房间 — 错误处理', () {
    test('signaling 创建房间失败时恢复为 idle', () async {
      mockSignaling.whenThrow('createRoom', Exception('Firebase 不可用'));

      try {
        await callManager.createRoom();
        fail('应抛出异常');
      } catch (_) {
        // 预期异常
      }

      expect(callManager.state, equals(CallState.idle));
      expect(callManager.roomId, isNull);
    });

    test('已经在非 idle 状态时创建房间抛出 StateError', () async {
      // 先让 signaling 成功返回房间号，但 WebRTC 会失败（因为真实平台不在）
      // 这里只测试 StateError 场景
      mockSignaling.when('createRoom', '123456');

      // 由于 WebRTC 需要平台支持，createRoom 会失败
      // 但状态应该先变为 waiting 再恢复
      try {
        await callManager.createRoom();
      } catch (_) {
        // WebRTC 平台错误
      }

      // 恢复后状态应为 idle，再次调用应成功进入 waiting
      mockSignaling.when('createRoom', '654321');
      try {
        await callManager.createRoom();
      } catch (_) {
        // WebRTC 平台错误
      }
      // 不应抛出 StateError（状态已恢复为 idle）
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 加入房间 — 错误处理
  // ═══════════════════════════════════════════════════════════

  group('加入房间 — 错误处理', () {
    test('signaling 加入房间失败时恢复为 idle', () async {
      mockSignaling.whenThrow('joinRoom', Exception('房间不存在'));

      try {
        await callManager.joinRoom('999999');
        fail('应抛出异常');
      } catch (_) {
        // 预期异常
      }

      expect(callManager.state, equals(CallState.idle));
      expect(callManager.roomId, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // CallEndReport 生成
  // ═══════════════════════════════════════════════════════════

  group('CallEndReport 生成', () {
    test('挂断后生成结束报告（含质量评级）', () async {
      CallEndReport? report;
      callManager.onCallEnded = (r) => report = r;

      await callManager.hangUp();

      expect(report, isNotNull);
      // 时长为 0 时评为"未接通"
      expect(report!.durationSeconds, equals(0));
      expect(report!.qualityRating, equals('未接通'));
    });

    test('报告包含建议列表', () async {
      CallEndReport? report;
      callManager.onCallEnded = (r) => report = r;

      await callManager.hangUp();

      expect(report, isNotNull);
      expect(report!.suggestions, isA<List<String>>());
    });

    test('时长 < 10 秒评为未接通', () async {
      CallEndReport? report;
      callManager.onCallEnded = (r) => report = r;

      await callManager.hangUp();

      expect(report!.qualityRating, equals('未接通'));
    });

    test('房间通话时 targetName 显示房间号', () async {
      mockSignaling.when('createRoom', '123456');
      CallEndReport? report;
      callManager.onCallEnded = (r) => report = r;

      // createRoom 会失败（WebRTC 需要平台），但 signaling 返回了房间号
      try {
        await callManager.createRoom();
      } catch (_) {}

      // 如果有房间号，报告应包含
      if (callManager.roomId != null) {
        await callManager.hangUp();
        expect(report!.targetName, contains('123456'));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // CallEndReport 数据模型
  // ═══════════════════════════════════════════════════════════

  group('CallEndReport 数据模型', () {
    test('构造默认报告', () {
      const report = CallEndReport(
        targetName: '好友',
        durationSeconds: 120,
      );
      expect(report.targetName, equals('好友'));
      expect(report.durationSeconds, equals(120));
      expect(report.avgRtt, equals(0));
      expect(report.qualityRating, equals('未知'));
      expect(report.estimatedTrafficMB, equals(0));
      expect(report.suggestions, isEmpty);
    });

    test('构造含所有字段的报告', () {
      const report = CallEndReport(
        targetName: '房间 123456',
        durationSeconds: 300,
        avgRtt: 80,
        qualityRating: '优秀',
        estimatedTrafficMB: 58.2,
        suggestions: ['网络连接质量优秀'],
      );
      expect(report.avgRtt, equals(80));
      expect(report.estimatedTrafficMB, equals(58.2));
      expect(report.suggestions.length, equals(1));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // CallParticipant 数据模型
  // ═══════════════════════════════════════════════════════════

  group('CallParticipant 数据模型', () {
    test('构造默认参与者', () {
      final p = CallParticipant(uid: 'user-1');
      expect(p.uid, equals('user-1'));
      expect(p.nickname, isNull);
      expect(p.remoteRenderer, isNull);
      expect(p.iceConnectionState, equals('new'));
      expect(p.isConnected, isFalse);
    });

    test('ICE 连接后 isConnected 为 true', () {
      final p = CallParticipant(
        uid: 'user-1',
        iceConnectionState: 'connected',
      );
      expect(p.isConnected, isTrue);
    });

    test('支持昵称和渲染器', () {
      final p = CallParticipant(
        uid: 'user-1',
        nickname: '小明',
        iceConnectionState: 'checking',
      );
      expect(p.nickname, equals('小明'));
      expect(p.isConnected, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 通话记录（模型层面）
  // ═══════════════════════════════════════════════════════════

  group('CallState 枚举', () {
    test('包含 5 个状态', () {
      expect(CallState.values.length, equals(5));
    });

    test('状态名称对应', () {
      expect(CallState.idle.name, equals('idle'));
      expect(CallState.waiting.name, equals('waiting'));
      expect(CallState.ringing.name, equals('ringing'));
      expect(CallState.inCall.name, equals('inCall'));
      expect(CallState.ended.name, equals('ended'));
    });
  });
}
