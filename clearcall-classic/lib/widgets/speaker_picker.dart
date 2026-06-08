import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 音频输出设备
enum AudioDevice {
  speaker('扬声器', Icons.volume_up_rounded),
  earpiece('听筒', Icons.phone_in_talk_rounded),
  bluetooth('蓝牙耳机', Icons.bluetooth_rounded);

  final String label;
  final IconData icon;
  const AudioDevice(this.label, this.icon);
}

/// 扬声器选择面板
///
/// iPhone 风格磨砂弹出面板，从控制栏上方浮出。
/// 当前选中设备显示蓝色 ✓。
class SpeakerPicker extends StatelessWidget {
  /// 当前选中的设备
  final AudioDevice selectedDevice;

  /// 可用设备列表
  final List<AudioDevice> availableDevices;

  /// 设备选择回调
  final void Function(AudioDevice device) onSelected;

  /// 关闭面板回调
  final VoidCallback onClose;

  const SpeakerPicker({
    super.key,
    required this.selectedDevice,
    required this.availableDevices,
    required this.onSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spacer(),
            // 面板
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 180.0,
                margin: const EdgeInsets.only(bottom: 100.0),
                decoration: BoxDecoration(
                  color: colorGlassBackground.withAlpha(220),
                  borderRadius: BorderRadius.circular(radiusCard),
                  border: Border.all(color: colorGlassBorder, width: 0.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: availableDevices.map((device) {
                    final isSelected = device == selectedDevice;
                    return GestureDetector(
                      onTap: () {
                        onSelected(device);
                        onClose();
                      },
                      child: Container(
                        height: 44.0,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        decoration: BoxDecoration(
                          border: device != availableDevices.last
                              ? const Border(
                                  bottom: BorderSide(
                                    color: colorGlassBorder,
                                    width: 0.5,
                                  ),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              device.icon,
                              size: 20.0,
                              color:
                                  isSelected ? colorAccent : colorTextPrimary,
                            ),
                            const SizedBox(width: 12.0),
                            Text(
                              device.label,
                              style: styleBody.copyWith(
                                color: isSelected
                                    ? colorAccent
                                    : colorTextPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            const Spacer(),
                            if (isSelected)
                              const Icon(
                                Icons.check_rounded,
                                color: colorAccent,
                                size: 20.0,
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
