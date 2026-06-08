import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/friend.dart';
import '../../models/room.dart';

/// 信令服务抽象接口
///
/// 定义所有信令操作的标准接口。Firebase 和 Leancloud 实现都遵循此接口。
/// 上层业务逻辑（CallManager、FriendManager）只依赖此抽象接口，
/// 不依赖具体实现。
///
/// 规则：
/// - 所有方法返回 Future，调用方负责 try-catch
/// - Stream 用于实时事件（房间变化、好友请求、在线状态）
/// - 房间信令和好友信令分离，各自独立
abstract class SignalingService {
  // ─── 房间管理 ────────────────────────────────────

  /// 创建新房间，返回 6 位数字房间号
  Future<String> createRoom(String userId);

  /// 加入已有房间
  Future<void> joinRoom(String roomId, String userId);

  /// 离开房间
  Future<void> leaveRoom(String roomId, String userId);

  /// 关闭房间（创建者或最后离开者调用）
  Future<void> closeRoom(String roomId);

  /// 监听房间事件（参与者加入/离开、SDP/ICE 等）
  Stream<RoomEvent> onRoomEvent(String roomId);

  /// 获取房间当前参与者列表
  Future<List<String>> getRoomParticipants(String roomId);

  /// 检查房间是否已满
  Future<bool> isRoomFull(String roomId);

  // ─── WebRTC 信令 ────────────────────────────────

  /// 发送 SDP Offer 到指定房间参与者的信令节点
  Future<void> sendOffer(String roomId, String userId, RTCSessionDescription offer);

  /// 发送 SDP Answer 到指定房间参与者的信令节点
  Future<void> sendAnswer(String roomId, String userId, RTCSessionDescription answer);

  /// 发送 ICE Candidate 到指定房间参与者的信令节点
  Future<void> sendCandidate(String roomId, String userId, RTCIceCandidate candidate);

  // ─── 好友系统 ────────────────────────────────────

  /// 发送好友申请
  Future<void> sendFriendRequest(
    String fromUid,
    String toUid,
    String nickname,
    String token,
  );

  /// 监听好友申请（被申请方调用）
  Stream<FriendRequest> onFriendRequest(String userId);

  /// 同意好友申请
  Future<void> acceptFriendRequest(String fromUid, String toUid);

  /// 拒绝好友申请
  Future<void> rejectFriendRequest(String fromUid, String toUid);

  /// 删除好友（双向）
  Future<void> removeFriend(String uid, String friendUid);

  /// 获取好友列表
  Future<List<Friend>> getFriends(String userId);

  // ─── 在线状态 ────────────────────────────────────

  /// 设置在线状态
  Future<void> setOnlineStatus(String userId, OnlineStatus status);

  /// 设置断线时自动标记离线（使用 onDisconnect）
  Future<void> setDisconnectCleanup(String userId);

  /// 获取用户在线状态
  Future<OnlineStatus> getUserStatus(String userId);

  /// 监听好友状态变化
  Stream<Map<String, OnlineStatus>> onFriendsStatusChange(List<String> friendUids);

  // ─── 呼叫信令 ────────────────────────────────────

  /// 发起呼叫（写入 /calls/{targetUid}/）
  Future<void> sendCallOffer(
    String fromUid,
    String toUid,
    Map<String, dynamic> callData,
  );

  /// 应答呼叫（更新 status 为 answered）
  Future<void> sendCallAnswer(String fromUid, String toUid);

  /// 拒绝呼叫（更新 status 为 rejected）
  Future<void> sendCallReject(String fromUid, String toUid);

  /// 监听来电（被叫方监听 /calls/{uid}/）
  Stream<Map<String, dynamic>> onIncomingCall(String userId);

  /// 清理呼叫节点（挂断后删除）
  Future<void> clearCallNode(String targetUid);

  // ─── 连接检测 ────────────────────────────────────

  /// 检测信令服务是否可用
  Future<bool> isAvailable();

  /// 获取服务名称（Firebase / Leancloud）
  String get serviceName;
}
