import 'package:flutter/services.dart';

/// 画中画（PiP）服务
///
/// 通过 MethodChannel 与 Android 原生侧通信，控制画中画模式。
/// - 进入 PiP：用户按 Home 键或点击 PiP 按钮时触发
/// - 退出 PiP：用户点击 PiP 窗口返回全屏
/// - Android 8.0+ 支持
class PiPService {
  static const _channel = MethodChannel('com.clearcall/pip');

  /// 进入画中画模式
  ///
  /// 返回 true 表示成功进入 PiP，false 表示失败或不支持。
  static Future<bool> enterPiP() async {
    try {
      final result = await _channel.invokeMethod<bool>('enterPiP');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 检查当前是否在画中画模式
  static Future<bool> isInPiP() async {
    try {
      final result = await _channel.invokeMethod<bool>('isInPiP');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 检查设备是否支持画中画
  static Future<bool> isPiPSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPiPSupported');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
