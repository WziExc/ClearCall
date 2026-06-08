import 'dart:math';

/// 本地唯一 ID 生成器
///
/// 生成全局唯一的 UUID v4 格式标识符。
/// 基于随机数，不依赖网络或云端服务。
/// 首次启动时调用一次，持久化存储在 SharedPreferences 中。
class IdGenerator {
  static final _random = Random.secure();

  /// 生成 UUID v4 格式的唯一标识符
  ///
  /// 格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  /// 例如：a3f2b8c1-4d5e-6f7a-8b9c-0d1e2f3a4b5c
  static String generate() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));

    // 构造 UUID v4 格式
    return _formatUuidV4(bytes);
  }

  /// 按 UUID v4 格式拼接 hex 字符串
  static String _formatUuidV4(List<int> bytes) {
    final hex = bytes.map((b) => (b % 16).toRadixString(16)).join();

    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '4${hex.substring(13, 16)}-' // version 4
        '${_pickVariantHex(bytes[16])}${hex.substring(17, 19)}-' // variant bits
        '${hex.substring(19, 31)}';
  }

  /// 选择符合 UUID variant 10xx 的 hex 字符
  static String _pickVariantHex(int b) {
    // variant bits = 10xx → hex 值为 8, 9, a, b
    const variants = ['8', '9', 'a', 'b'];
    return variants[b % 4];
  }
}
