import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// 控制按钮状态
class ControlButtonState {
  /// 是否静音
  final bool isMuted;

  /// 补光是否开启
  final bool isFlashOn;

  /// 摄像头是否开启
  final bool isCameraOn;

  /// 是否为前置摄像头
  final bool isFrontCamera;

  /// 补光是否可用（仅前置+暗光）
  final bool isFlashAvailable;

  /// 按钮点击回调
  final VoidCallback onMicToggle;
  final VoidCallback onFlashToggle;
  final VoidCallback onCameraToggle;
  final VoidCallback onSpeakerTap;
  final VoidCallback onFlipCamera;
  final VoidCallback onHangUp;
  final VoidCallback onSettingsTap;

  const ControlButtonState({
    this.isMuted = false,
    this.isFlashOn = false,
    this.isCameraOn = true,
    this.isFrontCamera = true,
    this.isFlashAvailable = false,
    required this.onMicToggle,
    required this.onFlashToggle,
    required this.onCameraToggle,
    required this.onSpeakerTap,
    required this.onFlipCamera,
    required this.onHangUp,
    required this.onSettingsTap,
  });
}

/// 通话底部控制栏
///
/// 7 个按钮：静音 / 补光 / 摄像头 / 扬声器 / 翻转 / 挂断 / 设置
/// 磨砂背景，80dp 高度，对齐 03-ui-design-spec.md 5.13 节
class CallControls extends StatelessWidget {
  final ControlButtonState state;

  const CallControls({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24.0),
        topRight: Radius.circular(24.0),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurStrength, sigmaY: blurStrength),
        child: Container(
          height: 80.0,
          decoration: BoxDecoration(
            color: colorGlassBackground.withAlpha(180),
            border: const Border(
              top: BorderSide(color: colorGlassBorder, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlIcon(
                icon: state.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: state.isMuted ? colorDanger : colorWhite,
                onTap: state.onMicToggle,
                tooltip: state.isMuted ? '取消静音' : '静音',
              ),
              _ControlIcon(
                icon: state.isFlashOn
                    ? Icons.highlight_rounded
                    : Icons.highlight_outlined,
                color: state.isFlashOn ? colorWarning : colorWhite,
                onTap: state.isFlashAvailable ? state.onFlashToggle : null,
                tooltip: '补光',
                disabled: !state.isFlashAvailable,
              ),
              _ControlIcon(
                icon: state.isCameraOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                color: state.isCameraOn ? colorWhite : colorDanger,
                onTap: state.onCameraToggle,
                tooltip: state.isCameraOn ? '关闭摄像头' : '开启摄像头',
              ),
              _ControlIcon(
                icon: Icons.volume_up_rounded,
                color: colorWhite,
                onTap: state.onSpeakerTap,
                tooltip: '扬声器',
              ),
              _ControlIcon(
                icon: Icons.flip_camera_android_rounded,
                color: colorWhite,
                onTap: state.onFlipCamera,
                tooltip: '翻转镜头',
              ),
              // 挂断按钮（红色醒目）
              _HangUpButton(onTap: state.onHangUp),
              _ControlIcon(
                icon: Icons.settings_rounded,
                color: colorWhite,
                size: 20.0,
                onTap: state.onSettingsTap,
                tooltip: '通话设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个控制图标按钮
class _ControlIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;
  final bool disabled;

  const _ControlIcon({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip = '',
    this.size = 24.0,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44.0,
          height: 44.0,
          decoration: BoxDecoration(
            color: disabled
                ? colorWhite.withAlpha(25)
                : colorWhite.withAlpha(38),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: disabled ? colorWhite.withAlpha(60) : color,
            size: size,
          ),
        ),
      ),
    );
  }
}

/// 红色挂断按钮（直径 52dp，比其余按钮更大更醒目）
class _HangUpButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HangUpButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52.0,
        height: 52.0,
        decoration: const BoxDecoration(
          color: colorDanger,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.call_end_rounded,
          color: colorWhite,
          size: 26.0,
        ),
      ),
    );
  }
}
