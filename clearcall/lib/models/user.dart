/// 本地用户数据模型
///
/// 纯数据类，无业务逻辑。
/// 存储在 SharedPreferences 中，非云端。
class User {
  /// 本地唯一 ID（首次启动自动生成，36 位 UUID 格式）
  final String localId;

  /// 用户昵称（可修改）
  final String nickname;

  /// 创建时间
  final DateTime createdAt;

  const User({
    required this.localId,
    required this.nickname,
    required this.createdAt,
  });

  /// 从 JSON 反序列化（SharedPreferences 存储用）
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      localId: json['localId'] as String,
      nickname: json['nickname'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// 序列化为 JSON（SharedPreferences 存储用）
  Map<String, dynamic> toJson() {
    return {
      'localId': localId,
      'nickname': nickname,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 昵称首字母（大写，用于头像生成）
  String get initial {
    if (nickname.isEmpty) return '?';
    return nickname[0].toUpperCase();
  }

  /// 复制并修改部分字段
  User copyWith({
    String? nickname,
  }) {
    return User(
      localId: localId,
      nickname: nickname ?? this.nickname,
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'User(localId: $localId, nickname: $nickname)';
}
