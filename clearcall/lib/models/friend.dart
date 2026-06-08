/// 在线状态
enum OnlineStatus {
  /// 在线
  online,

  /// 离线
  offline,

  /// 通话中
  inCall,
}

/// 好友申请状态
enum FriendRequestStatus {
  /// 待处理
  pending,

  /// 已同意
  accepted,

  /// 已拒绝
  rejected,
}

/// 好友数据模型
class Friend {
  /// 好友的本地唯一 ID
  final String uid;

  /// 好友昵称
  final String nickname;

  /// 在线状态
  final OnlineStatus status;

  /// 最后在线时间
  final DateTime? lastSeen;

  const Friend({
    required this.uid,
    required this.nickname,
    this.status = OnlineStatus.offline,
    this.lastSeen,
  });

  /// 是否在线（包括通话中）
  bool get isOnline => status != OnlineStatus.offline;

  /// 是否正在通话
  bool get isInCall => status == OnlineStatus.inCall;

  /// 昵称首字母（用于头像生成）
  String get initial {
    if (nickname.isEmpty) return '?';
    return nickname[0].toUpperCase();
  }

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      uid: json['uid'] as String,
      nickname: json['nickname'] as String? ?? '未知',
      status: _parseStatus(json['status'] as String?),
      lastSeen: json['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int)
          : null,
    );
  }

  static OnlineStatus _parseStatus(String? status) {
    switch (status) {
      case 'online':
        return OnlineStatus.online;
      case 'in-call':
        return OnlineStatus.inCall;
      default:
        return OnlineStatus.offline;
    }
  }

  Friend copyWith({
    String? nickname,
    OnlineStatus? status,
    DateTime? lastSeen,
  }) {
    return Friend(
      uid: uid,
      nickname: nickname ?? this.nickname,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// 好友申请数据模型
class FriendRequest {
  /// 申请者 UID
  final String fromUid;

  /// 申请者昵称
  final String nickname;

  /// 验证 token（8 位十六进制，嵌入二维码）
  final String token;

  /// 申请时间
  final DateTime timestamp;

  /// 申请状态
  final FriendRequestStatus status;

  const FriendRequest({
    required this.fromUid,
    required this.nickname,
    required this.token,
    required this.timestamp,
    this.status = FriendRequestStatus.pending,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      fromUid: json['fromUid'] as String,
      nickname: json['nickname'] as String? ?? '未知',
      token: json['token'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      status: _parseStatus(json['status'] as String?),
    );
  }

  static FriendRequestStatus _parseStatus(String? status) {
    switch (status) {
      case 'accepted':
        return FriendRequestStatus.accepted;
      case 'rejected':
        return FriendRequestStatus.rejected;
      default:
        return FriendRequestStatus.pending;
    }
  }
}
