import 'dart:async';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

import '../../models/friend.dart';
import '../../models/room.dart';
import 'signaling_service.dart';

/// 扫码 SDP 交换信令服务 — 零服务器方案
///
/// 完全不依赖任何网络服务器。通话双方通过互相扫描二维码
/// 来交换 WebRTC SDP 信息（Offer/Answer/ICE Candidates）。
///
/// 工作原理：
/// 1. 创建方生成 Offer（等待 ICE 收集完成）→ 编码为 QR 码
/// 2. 加入方扫描 → 设置远端描述 → 生成 Answer → 编码为 QR 码
/// 3. 创建方扫描 → 设置远端描述 → WebRTC 连接建立！
///
/// 限制：
/// - 不支持好友系统（需要服务器存储好友关系）
/// - 不支持在线呼叫（需要服务器推送来电通知）
/// - 仅支持 1 对 1 通话（2 人以上需要服务器中继信令）
/// - 需等待 ICE 收集完成（Trickle ICE 不可用）
///
/// 优势：
/// - 零服务器成本，最高隐私
/// - 国内任何网络环境均可用
/// - 不需要任何第三方账号
class QrSignaling implements SignalingService {
  final Logger _log = Logger('QrSignaling');

  /// 当前用户 ID（本地随机生成）
  String? _userId;

  /// ─── 房间事件流控制器（手动推送）───────────────
  StreamController<RoomEvent>? _roomEventController;

  /// ─── SDP 数据缓冲区（供 QR 编解码）─────────────
  /// 创建方：创建 Offer 后存入 [_offerSdp]，等待写入 QR
  String? _offerSdp;
  /// 加入方：创建 Answer 后存入 [_answerSdp]，等待写入 QR
  String? _answerSdp;
  /// 本地生成的 ICE candidates（收集完成后合并到 SDP）
  final List<Map<String, dynamic>> _localCandidates = [];

  /// 用于触发 RoomEvent 的回调（由 CallManager 设置）
  void Function(SignalingService signaling)? onServiceReady;

  @override
  String get serviceName => '扫码交换（无服务器）';

  @override
  Future<void> initialize() async {
    _userId = 'qr_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    _log.info('QR 信令初始化完成，userId: $_userId');
  }

  // ═══════════════════════════════════════════════════════════
  // 对外暴露：SDP 数据供 QR 编解码使用
  // ═══════════════════════════════════════════════════════════

  /// 获取创建方的 Offer SDP（用于生成 QR 码）
  /// 在 createRoom 后、收到对方 Answer 前调用
  String? get offerSdpForQr => _offerSdp;

  /// 获取加入方的 Answer SDP（用于生成 QR 码）
  /// 在收到 Offer 并创建 Answer 后调用
  String? get answerSdpForQr => _answerSdp;

  /// 加入方扫码后注入远端 Offer SDP，触发房间事件
  void injectRemoteOffer(String remoteSdp) {
    _log.info('扫码注入远端 Offer');
    if (_roomEventController != null && !_roomEventController!.isClosed) {
      _roomEventController!.add(RoomEvent(
        type: RoomEventType.offerReceived,
        userId: 'remote',
        sdp: {'type': 'offer', 'sdp': remoteSdp},
        timestamp: DateTime.now(),
      ));
    }
  }

  /// 创建方扫码后注入远端 Answer SDP，触发房间事件
  void injectRemoteAnswer(String remoteSdp) {
    _log.info('扫码注入远端 Answer');
    if (_roomEventController != null && !_roomEventController!.isClosed) {
      _roomEventController!.add(RoomEvent(
        type: RoomEventType.answerReceived,
        userId: 'remote',
        sdp: {'type': 'answer', 'sdp': remoteSdp},
        timestamp: DateTime.now(),
      ));
    }
  }

  /// 注入远端 ICE Candidate（扫码模式通常不需要，因已含在 SDP 中）
  void injectRemoteCandidate(List<Map<String, dynamic>> candidates) {
    for (final c in candidates) {
      if (_roomEventController != null && !_roomEventController!.isClosed) {
        _roomEventController!.add(RoomEvent(
          type: RoomEventType.iceCandidateReceived,
          userId: 'remote',
          candidate: c,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 房间管理
  // ═══════════════════════════════════════════════════════════

  @override
  Future<String> createRoom(String appUserId) async {
    final roomId = _generateRoomCode();
    _log.info('QR 房间创建（本地）: $roomId');
    return roomId;
  }

  @override
  Future<void> joinRoom(String roomId, String appUserId) async {
    _log.info('QR 加入房间（本地）: $roomId');
  }

  @override
  Future<void> leaveRoom(String roomId, String appUserId) async {
    _offerSdp = null;
    _answerSdp = null;
    _localCandidates.clear();
    _log.info('QR 离开房间: $roomId');
  }

  @override
  Future<void> closeRoom(String roomId) async {
    _offerSdp = null;
    _answerSdp = null;
    _localCandidates.clear();
    _log.info('QR 关闭房间: $roomId');
  }

  @override
  Future<List<String>> getRoomParticipants(String roomId) async {
    return [];
  }

  @override
  Future<bool> isRoomFull(String roomId) async {
    return false;
  }

  @override
  Stream<RoomEvent> onRoomEvent(String roomId) {
    _roomEventController = StreamController<RoomEvent>.broadcast();

    return _roomEventController!.stream;
  }

  // ═══════════════════════════════════════════════════════════
  // WebRTC 信令（存入缓冲区供 QR 编码）
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendOffer(
      String roomId, String userId, RTCSessionDescription offer) async {
    // 存储 Offer SDP 供 QR 编码
    _offerSdp = offer.sdp;
    _log.info('Offer 已存入缓冲区（${_offerSdp!.length} 字符），等待扫码');
  }

  @override
  Future<void> sendAnswer(
      String roomId, String userId, RTCSessionDescription answer) async {
    // 存储 Answer SDP 供 QR 编码
    _answerSdp = answer.sdp;
    _log.info('Answer 已存入缓冲区（${_answerSdp!.length} 字符），等待扫码');
  }

  @override
  Future<void> sendCandidate(
      String roomId, String userId, RTCIceCandidate candidate) async {
    // 收集 ICE candidates（通常不单独使用，而是等收集完包含在 SDP 中）
    _localCandidates.add({
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 以下方法在扫码模式下不可用
  // ═══════════════════════════════════════════════════════════

  @override
  Future<void> sendFriendRequest(
    String fromUid,
    String toUid,
    String nickname,
    String token,
  ) async {
    _log.info('扫码模式不支持好友申请');
  }

  @override
  Stream<FriendRequest> onFriendRequest(String userId) {
    return const Stream.empty();
  }

  @override
  Future<void> acceptFriendRequest(String fromUid, String toUid) async {}

  @override
  Future<void> rejectFriendRequest(String fromUid, String toUid) async {}

  @override
  Future<void> removeFriend(String uid, String friendUid) async {}

  @override
  Future<List<Friend>> getFriends(String userId) async {
    return [];
  }

  @override
  Future<void> setOnlineStatus(String userId, OnlineStatus status) async {}

  @override
  Future<void> setDisconnectCleanup(String userId) async {}

  @override
  Future<OnlineStatus> getUserStatus(String userId) async {
    return OnlineStatus.offline;
  }

  @override
  Stream<Map<String, OnlineStatus>> onFriendsStatusChange(
      List<String> friendUids) {
    return const Stream.empty();
  }

  @override
  Future<void> sendCallOffer(
    String fromUid,
    String toUid,
    Map<String, dynamic> callData,
  ) async {}

  @override
  Future<void> sendCallAnswer(String fromUid, String toUid) async {}

  @override
  Future<void> sendCallReject(String fromUid, String toUid) async {}

  @override
  Stream<Map<String, dynamic>> onIncomingCall(String userId) {
    return const Stream.empty();
  }

  @override
  Future<void> clearCallNode(String targetUid) async {}

  @override
  Future<bool> isAvailable() async {
    // 扫码模式永远可用（不需要网络）
    return true;
  }

  // ═══════════════════════════════════════════════════════════
  // 工具
  // ═══════════════════════════════════════════════════════════

  static String _generateRoomCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  void dispose() {
    _roomEventController?.close();
    _log.info('QrSignaling 已清理');
  }
}
