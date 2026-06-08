import 'dart:async';
import 'package:flutter/services.dart';

/// 网络连接检测服务
///
/// 通过 MethodChannel 查询当前网络类型（Wi-Fi / 移动数据）。
class ConnectivityService {
  static const _channel = MethodChannel('com.clearcall/audio');

  /// 检查当前是否使用移动数据（非 Wi-Fi）
  ///
  /// Android 侧通过 ConnectivityManager 判断。
  static Future<bool> isOnMobileData() async {
    try {
      final result = await _channel.invokeMethod<bool>('isOnMobileData');
      return result ?? false;
    } catch (e) {
      // 检测失败时保守处理：假定为非移动数据
      return false;
    }
  }
}
