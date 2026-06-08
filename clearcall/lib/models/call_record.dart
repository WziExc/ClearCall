/// 通话记录数据模型
///
/// 存储在本地 sqflite 数据库中。
class CallRecord {
  /// 记录 ID（自增主键）
  final int? id;

  /// 通话对象标识（好友 UID 或房间号）
  final String targetId;

  /// 通话对象昵称（好友名或"房间#xxxxxx"）
  final String targetName;

  /// 通话开始时间
  final DateTime startTime;

  /// 通话结束时间
  final DateTime? endTime;

  /// 通话时长（秒）
  final int? durationSeconds;

  /// 是否为好友通话（false = 房间通话）
  final bool isFriendCall;

  /// 通话类型（"video"）
  final String callType;

  /// 通话方向（"outgoing" / "incoming"）
  final String direction;

  /// 是否已接听
  final bool answered;

  const CallRecord({
    this.id,
    required this.targetId,
    required this.targetName,
    required this.startTime,
    this.endTime,
    this.durationSeconds,
    this.isFriendCall = false,
    this.callType = 'video',
    this.direction = 'outgoing',
    this.answered = true,
  });

  /// 时长格式化显示（如 "02:34"）
  String get formattedDuration {
    if (durationSeconds == null) return '--:--';
    final mins = durationSeconds! ~/ 60;
    final secs = durationSeconds! % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  factory CallRecord.fromMap(Map<String, dynamic> map) {
    return CallRecord(
      id: map['id'] as int?,
      targetId: map['targetId'] as String,
      targetName: map['targetName'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
      endTime: map['endTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['endTime'] as int)
          : null,
      durationSeconds: map['durationSeconds'] as int?,
      isFriendCall: (map['isFriendCall'] as int?) == 1,
      callType: map['callType'] as String? ?? 'video',
      direction: map['direction'] as String? ?? 'outgoing',
      answered: (map['answered'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'targetId': targetId,
      'targetName': targetName,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'durationSeconds': durationSeconds,
      'isFriendCall': isFriendCall ? 1 : 0,
      'callType': callType,
      'direction': direction,
      'answered': answered ? 1 : 0,
    };
  }
}
