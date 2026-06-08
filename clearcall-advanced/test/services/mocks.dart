import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:clearcall/models/friend.dart';
import 'package:clearcall/models/room.dart';
import 'package:clearcall/services/signaling/signaling_service.dart';
import 'package:clearcall/services/webrtc_service.dart';

/// ─── Mock SignalingService ─────────────────────────────

/// 手动 Mock 信令服务
///
/// 不依赖 mockito 代码生成，每个方法返回可配置的 Future/Stream。
/// 测试中通过设置 [_methodResults] 和 [_streamResults] 来控制行为。
class MockSignalingService extends SignalingService {
  /// 方法返回值映射表（方法名 → 返回值）
  final Map<String, dynamic> _methodResults = {};

  /// Stream 返回值映射表
  final Map<String, Stream<dynamic>> _streamResults = {};

  /// 记录所有方法调用
  final List<MethodCall> calls = [];

  @override
  String get serviceName => 'MockSignaling';

  @override
  Future<void> initialize() async {
    calls.add(MethodCall('initialize', null));
    final result = _result('initialize');
    if (result is ThrowingFuture) throw result.exception;
  }

  /// 设置方法的返回值
  void when(String method, dynamic result) {
    _methodResults[method] = result;
  }

  /// 设置方法的 Stream 返回值
  void whenStream(String method, Stream<dynamic> stream) {
    _streamResults[method] = stream;
  }

  /// 设置方法抛出异常
  void whenThrow(String method, Exception exception) {
    _methodResults[method] = ThrowingFuture(exception);
  }

  dynamic _result(String method) {
    return _methodResults[method];
  }

  Stream<T> _stream<T>(String method) {
    return (_streamResults[method] as Stream<T>?) ?? const Stream.empty();
  }

  // ─── 房间管理 ────────────────────────────────────

  @override
  Future<String> createRoom(String userId) async {
    calls.add(MethodCall('createRoom', {'userId': userId}));
    final result = _result('createRoom');
    if (result is ThrowingFuture) throw result.exception;
    return (result as String?) ?? '999999';
  }

  @override
  Future<void> joinRoom(String roomId, String userId) async {
    calls.add(MethodCall('joinRoom', {'roomId': roomId, 'userId': userId}));
    final result = _result('joinRoom');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> leaveRoom(String roomId, String userId) async {
    calls.add(MethodCall('leaveRoom', {'roomId': roomId, 'userId': userId}));
    final result = _result('leaveRoom');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> closeRoom(String roomId) async {
    calls.add(MethodCall('closeRoom', {'roomId': roomId}));
    final result = _result('closeRoom');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Stream<RoomEvent> onRoomEvent(String roomId) {
    return _stream<RoomEvent>('onRoomEvent');
  }

  @override
  Future<List<String>> getRoomParticipants(String roomId) async {
    calls.add(MethodCall('getRoomParticipants', {'roomId': roomId}));
    final result = _result('getRoomParticipants');
    if (result is ThrowingFuture) throw result.exception;
    return (result as List<String>?) ?? [];
  }

  @override
  Future<bool> isRoomFull(String roomId) async {
    calls.add(MethodCall('isRoomFull', {'roomId': roomId}));
    final result = _result('isRoomFull');
    if (result is ThrowingFuture) throw result.exception;
    return (result as bool?) ?? false;
  }

  // ─── WebRTC 信令 ─────────────────────────────────

  @override
  Future<void> sendOffer(String roomId, String userId, RTCSessionDescription offer) async {
    calls.add(MethodCall('sendOffer', {'roomId': roomId, 'userId': userId}));
    final result = _result('sendOffer');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> sendAnswer(String roomId, String userId, RTCSessionDescription answer) async {
    calls.add(MethodCall('sendAnswer', {'roomId': roomId, 'userId': userId}));
    final result = _result('sendAnswer');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> sendCandidate(String roomId, String userId, RTCIceCandidate candidate) async {
    calls.add(MethodCall('sendCandidate', {'roomId': roomId, 'userId': userId}));
    final result = _result('sendCandidate');
    if (result is ThrowingFuture) throw result.exception;
  }

  // ─── 好友系统 ────────────────────────────────────

  @override
  Future<void> sendFriendRequest(
    String fromUid,
    String toUid,
    String nickname,
    String token,
  ) async {
    calls.add(MethodCall('sendFriendRequest', {'fromUid': fromUid, 'toUid': toUid}));
    final result = _result('sendFriendRequest');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Stream<FriendRequest> onFriendRequest(String userId) {
    return _stream<FriendRequest>('onFriendRequest');
  }

  @override
  Future<void> acceptFriendRequest(String fromUid, String toUid) async {
    calls.add(MethodCall('acceptFriendRequest', {'fromUid': fromUid, 'toUid': toUid}));
    final result = _result('acceptFriendRequest');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> rejectFriendRequest(String fromUid, String toUid) async {
    calls.add(MethodCall('rejectFriendRequest', {'fromUid': fromUid, 'toUid': toUid}));
    final result = _result('rejectFriendRequest');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> removeFriend(String uid, String friendUid) async {
    calls.add(MethodCall('removeFriend', {'uid': uid, 'friendUid': friendUid}));
    final result = _result('removeFriend');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<List<Friend>> getFriends(String userId) async {
    calls.add(MethodCall('getFriends', {'userId': userId}));
    final result = _result('getFriends');
    if (result is ThrowingFuture) throw result.exception;
    return (result as List<Friend>?) ?? [];
  }

  // ─── 在线状态 ────────────────────────────────────

  @override
  Future<void> setOnlineStatus(String userId, OnlineStatus status) async {
    calls.add(MethodCall('setOnlineStatus', {'userId': userId, 'status': status}));
    final result = _result('setOnlineStatus');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> setDisconnectCleanup(String userId) async {
    calls.add(MethodCall('setDisconnectCleanup', {'userId': userId}));
    final result = _result('setDisconnectCleanup');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<OnlineStatus> getUserStatus(String userId) async {
    calls.add(MethodCall('getUserStatus', {'userId': userId}));
    final result = _result('getUserStatus');
    if (result is ThrowingFuture) throw result.exception;
    return (result as OnlineStatus?) ?? OnlineStatus.offline;
  }

  @override
  Stream<Map<String, OnlineStatus>> onFriendsStatusChange(List<String> friendUids) {
    return _stream<Map<String, OnlineStatus>>('onFriendsStatusChange');
  }

  // ─── 呼叫信令 ────────────────────────────────────

  @override
  Future<void> sendCallOffer(String fromUid, String toUid, Map<String, dynamic> callData) async {
    calls.add(MethodCall('sendCallOffer', {'fromUid': fromUid, 'toUid': toUid}));
    final result = _result('sendCallOffer');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> sendCallAnswer(String fromUid, String toUid) async {
    calls.add(MethodCall('sendCallAnswer', {'fromUid': fromUid, 'toUid': toUid}));
    final result = _result('sendCallAnswer');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Future<void> sendCallReject(String fromUid, String toUid) async {
    calls.add(MethodCall('sendCallReject', {'fromUid': fromUid, 'toUid': toUid}));
    final result = _result('sendCallReject');
    if (result is ThrowingFuture) throw result.exception;
  }

  @override
  Stream<Map<String, dynamic>> onIncomingCall(String userId) {
    return _stream<Map<String, dynamic>>('onIncomingCall');
  }

  @override
  Future<void> clearCallNode(String targetUid) async {
    calls.add(MethodCall('clearCallNode', {'targetUid': targetUid}));
    final result = _result('clearCallNode');
    if (result is ThrowingFuture) throw result.exception;
  }

  // ─── 连接检测 ────────────────────────────────────

  @override
  Future<bool> isAvailable() async {
    calls.add(MethodCall('isAvailable', null));
    final result = _result('isAvailable');
    if (result is ThrowingFuture) throw result.exception;
    return (result as bool?) ?? true;
  }
}

/// ─── Mock WebRTCService ────────────────────────────────

/// 手动 Mock WebRTC 服务
///
/// 不创建真实的 PeerConnection，所有操作为空实现或返回预设值。
/// 使用假 RTCVideoRenderer 避免平台依赖。
class MockWebRTCService extends WebRTCService {
  /// 记录方法调用
  final List<String> calls = [];

  bool _getLocalStreamThrow = false;
  bool _initPeerConnectionThrow = false;
  bool _createOfferThrow = false;
  bool _createAnswerThrow = false;

  /// 使用默认 ICE 服务器构造
  MockWebRTCService() : super(iceServers: WebRTCService.defaultIceServers);

  void reset() {
    calls.clear();
    _getLocalStreamThrow = false;
    _initPeerConnectionThrow = false;
    _createOfferThrow = false;
    _createAnswerThrow = false;
  }

  void throwOnGetLocalStream() => _getLocalStreamThrow = true;
  void throwOnInitPeerConnection() => _initPeerConnectionThrow = true;

  @override
  Future<MediaStream> getLocalStream() async {
    calls.add('getLocalStream');
    if (_getLocalStreamThrow) throw Exception('摄像头不可用');
    // 返回一个假的 MediaStream（flutter_webrtc 不提供公开构造，使用 dynamic）
    throw UnimplementedError('Mock 不支持真实 MediaStream，此调用仅用于记录');
  }

  @override
  Future<void> initLocalRenderer() async {
    calls.add('initLocalRenderer');
  }

  @override
  void attachLocalStream() {
    calls.add('attachLocalStream');
  }

  @override
  Future<RTCPeerConnection> initPeerConnection() async {
    calls.add('initPeerConnection');
    if (_initPeerConnectionThrow) throw Exception('PeerConnection 创建失败');
    throw UnimplementedError('Mock 不支持真实 RTCPeerConnection，此调用仅用于记录');
  }

  @override
  void setupPeerConnectionListeners({
    required void Function(RTCIceCandidate candidate) onIceCandidate,
    required void Function(MediaStream stream) onAddStream,
    required void Function(MediaStream stream) onRemoveStream,
    void Function(RTCIceConnectionState state)? onIceConnectionState,
  }) {
    calls.add('setupPeerConnectionListeners');
  }

  @override
  Future<void> addLocalStreamToPeer() async {
    calls.add('addLocalStreamToPeer');
  }

  @override
  Future<RTCSessionDescription> createOffer() async {
    calls.add('createOffer');
    if (_createOfferThrow) throw Exception('创建 Offer 失败');
    return RTCSessionDescription('mock-sdp-offer', 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer() async {
    calls.add('createAnswer');
    if (_createAnswerThrow) throw Exception('创建 Answer 失败');
    return RTCSessionDescription('mock-sdp-answer', 'answer');
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    calls.add('setRemoteDescription');
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    calls.add('addCandidate');
  }

  @override
  void removeRemoteRenderer(String participantId) {
    calls.add('removeRemoteRenderer:$participantId');
  }

  @override
  Future<void> hangUp() async {
    calls.add('hangUp');
  }

  @override
  void startStatsCollection() {
    calls.add('startStatsCollection');
  }

  @override
  void applyAudioProcessing({
    required bool aec,
    required bool ans,
    required bool agc,
  }) {
    calls.add('applyAudioProcessing');
  }
}

/// ─── 内部辅助类 ───────────────────────────────────────

class MethodCall {
  final String method;
  final dynamic params;
  MethodCall(this.method, this.params);
}

class ThrowingFuture {
  final Exception exception;
  ThrowingFuture(this.exception);
}
