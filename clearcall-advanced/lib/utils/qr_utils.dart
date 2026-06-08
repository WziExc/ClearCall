import 'dart:math';

/// 二维码工具函数
///
/// 处理好友二维码和房间二维码的生成与解析。
class QrUtils {
  /// 生成 8 位十六进制验证 token（用于好友添加）
  static String generateFriendToken() {
    final random = Random.secure();
    return List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  /// 生成好友二维码数据
  ///
  /// 格式: clearcall://friend/{uid}/{token}
  static String generateFriendQrData(String uid, String token) {
    return 'clearcall://friend/$uid/$token';
  }

  /// 生成房间二维码数据
  ///
  /// 格式: clearcall://room/{roomCode}
  static String generateRoomQrData(String roomCode) {
    return 'clearcall://room/$roomCode';
  }

  /// 解析好友二维码数据
  ///
  /// 返回 (uid, token)，如果格式不匹配返回 null。
  static (String, String)? parseFriendQrData(String data) {
    final uri = Uri.tryParse(data);
    if (uri == null) return null;

    // 匹配 clearcall://friend/{uid}/{token}
    if (uri.scheme == 'clearcall' && uri.host == 'friend') {
      final segments = uri.pathSegments;
      if (segments.length == 2) {
        final uid = segments[0];
        final token = segments[1];
        if (uid.isNotEmpty && token.length == 8) {
          return (uid, token);
        }
      }
    }
    return null;
  }

  /// 解析房间二维码数据
  ///
  /// 返回房间号，如果格式不匹配返回 null。
  static String? parseRoomQrData(String data) {
    final uri = Uri.tryParse(data);
    if (uri == null) return null;

    // 匹配 clearcall://room/{roomCode}
    if (uri.scheme == 'clearcall' && uri.host == 'room') {
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final code = segments.first;
        if (code.length == 6 && int.tryParse(code) != null) {
          return code;
        }
      }
    }
    return null;
  }

  /// 解析任意 ClearCall 二维码数据
  ///
  /// 返回 Map 包含 'type' ('friend' 或 'room') 和对应数据。
  static Map<String, dynamic>? parseQrData(String data) {
    // 先尝试好友格式
    final friendData = parseFriendQrData(data);
    if (friendData != null) {
      return {
        'type': 'friend',
        'uid': friendData.$1,
        'token': friendData.$2,
      };
    }

    // 再尝试房间格式
    final roomCode = parseRoomQrData(data);
    if (roomCode != null) {
      return {
        'type': 'room',
        'roomCode': roomCode,
      };
    }

    // 尝试纯文本格式（只包含 16 位 hex UID 和 8 位 hex token）
    final text = data.trim();
    if (text.length >= 24) {
      final uid = text.substring(0, 16);
      final token = text.substring(16, 24);
      if (RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(uid) &&
          RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(token)) {
        return {
          'type': 'friend',
          'uid': uid.toLowerCase(),
          'token': token.toLowerCase(),
        };
      }
    }

    return null;
  }
}
