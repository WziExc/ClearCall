/// 房间状态
enum RoomStatus {
  /// 等待中（已创建，等待他人加入）
  waiting,

  /// 通话中（至少 2 人在线）
  active,

  /// 已关闭（所有人离开或超时）
  closed,
}

/// 房间事件类型
enum RoomEventType {
  /// 参与者加入
  participantJoined,

  /// 参与者离开
  participantLeft,

  /// 房间关闭
  roomClosed,

  /// SDP Offer 收到
  offerReceived,

  /// SDP Answer 收到
  answerReceived,

  /// ICE Candidate 收到
  iceCandidateReceived,
}

/// 房间事件数据
///
/// 由 SignalingService 的 onRoomEvent 流发出，
/// 包含事件类型和关联数据。
class RoomEvent {
  /// 事件类型
  final RoomEventType type;

  /// 触发事件的用户 ID
  final String? userId;

  /// SDP 数据（type 为 offer/answer 时）
  final Map<String, dynamic>? sdp;

  /// ICE Candidate 数据（type 为 iceCandidate 时）
  final Map<String, dynamic>? candidate;

  /// 事件时间戳
  final DateTime timestamp;

  const RoomEvent({
    required this.type,
    this.userId,
    this.sdp,
    this.candidate,
    required this.timestamp,
  });

  factory RoomEvent.fromJson(Map<String, dynamic> json) {
    return RoomEvent(
      type: RoomEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RoomEventType.participantJoined,
      ),
      userId: json['userId'] as String?,
      sdp: json['sdp'] as Map<String, dynamic>?,
      candidate: json['candidate'] as Map<String, dynamic>?,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'userId': userId,
      'sdp': sdp,
      'candidate': candidate,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}

/// 房间数据模型
class Room {
  /// 房间号（6 位数字）
  final String roomId;

  /// 创建者 UID
  final String creatorUid;

  /// 创建时间
  final DateTime createdAt;

  /// 房间状态
  final RoomStatus status;

  /// 参与者 UID 列表
  final List<String> participantUids;

  const Room({
    required this.roomId,
    required this.creatorUid,
    required this.createdAt,
    this.status = RoomStatus.waiting,
    this.participantUids = const [],
  });

  /// 房间是否已满（达 3 人上限）
  bool get isFull => participantUids.length >= 3;

  /// 房间是否为空（无人）
  bool get isEmpty => participantUids.isEmpty;

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      roomId: json['roomId'] as String,
      creatorUid: json['creator'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      status: _parseStatus(json['status'] as String?),
      participantUids: json['participants'] != null
          ? (json['participants'] as Map).keys.map((k) => k.toString()).toList()
          : [],
    );
  }

  static RoomStatus _parseStatus(String? status) {
    switch (status) {
      case 'active':
        return RoomStatus.active;
      case 'closed':
        return RoomStatus.closed;
      default:
        return RoomStatus.waiting;
    }
  }
}
