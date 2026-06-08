import 'package:flutter/services.dart';

/// 呼叫音效服务
///
/// 通过 MethodChannel 播放系统默认铃声和自定义音效。
/// Android 侧使用 RingtoneManager 播放系统铃声。
class RingtoneService {
  static const _channel = MethodChannel('com.clearcall/audio');

  /// 播放呼叫铃声（发起/收到来电时）
  static Future<void> startRinging() async {
    try {
      await _channel.invokeMethod('startRinging');
    } catch (e) {
      // 铃声非关键功能，失败不阻塞
    }
  }

  /// 停止铃声（接通/挂断/拒绝时）
  static Future<void> stopRinging() async {
    try {
      await _channel.invokeMethod('stopRinging');
    } catch (e) {
      // 静默失败
    }
  }

  /// 播放挂断音效
  static Future<void> playHangupSound() async {
    try {
      await _channel.invokeMethod('playHangupSound');
    } catch (e) {
      // 静默失败
    }
  }

  /// 播放接通音效
  static Future<void> playConnectSound() async {
    try {
      await _channel.invokeMethod('playConnectSound');
    } catch (e) {
      // 静默失败
    }
  }
}
