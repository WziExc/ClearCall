import 'package:flutter/services.dart';

import '../widgets/speaker_picker.dart';

/// 音频设备检测服务
///
/// 通过 MethodChannel 查询 Android 系统当前可用的音频输出设备：
/// - 听筒（earpiece）：默认通话模式
/// - 扬声器（speaker）：外放
/// - 蓝牙（bluetooth）：蓝牙耳机/SCO 已连接时可用
class AudioDeviceService {
  static const _channel = MethodChannel('com.clearcall/audio');

  /// 获取当前可用的音频设备列表
  ///
  /// 至少返回 [听筒, 扬声器]，蓝牙连接时额外返回 [蓝牙]。
  static Future<List<AudioDevice>> getAvailableDevices() async {
    try {
      final devices =
          await _channel.invokeListMethod<String>('getAvailableAudioDevices');
      if (devices == null || devices.isEmpty) {
        return [AudioDevice.earpiece, AudioDevice.speaker];
      }
      return devices.map((d) {
        switch (d) {
          case 'bluetooth':
            return AudioDevice.bluetooth;
          case 'speaker':
            return AudioDevice.speaker;
          default:
            return AudioDevice.earpiece;
        }
      }).toList();
    } catch (e) {
      return [AudioDevice.earpiece, AudioDevice.speaker];
    }
  }
}
