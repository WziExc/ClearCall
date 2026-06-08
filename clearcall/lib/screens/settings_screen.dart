import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../utils/constants.dart';


/// 设置页面（从"我" Tab 进入）
///
/// 分 3 组：视频设置、音频设置、其他设置。
/// 每项均可点击进入详细选择页面。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: colorBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: colorTextPrimary, size: 20.0),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('设置', style: styleTitle3),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 视频设置 ───
            const Text('视频', style: styleTitle2),
            const SizedBox(height: 8.0),
            _buildGroup([
              _buildNavItem(
                context,
                ref,
                icon: Icons.hd_rounded,
                title: '摄像头分辨率',
                onTap: () => _showResolutionPicker(context, ref),
              ),
              _buildNavItem(
                context,
                ref,
                icon: Icons.speed_rounded,
                title: '最高帧率',
                onTap: () => _showFrameRatePicker(context, ref),
              ),
              _buildNavItem(
                context,
                ref,
                icon: Icons.tune_rounded,
                title: '画质偏好',
                onTap: () => _showQualityPicker(context, ref),
              ),
              _buildSwitchItem(
                context,
                ref,
                icon: Icons.videocam_rounded,
                title: 'H.265 编码',
                value: ref.watch(settingsProvider).h265Enabled,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).saveAllSettings(
                        ref.read(settingsProvider).copyWith(h265Enabled: v),
                      );
                },
              ),
            ]),
            const SizedBox(height: 24.0),

            // ─── 音频设置 ───
            const Text('音频', style: styleTitle2),
            const SizedBox(height: 8.0),
            _buildGroup([
              _buildNavItem(
                context,
                ref,
                icon: Icons.music_note_rounded,
                title: '音频编码',
                onTap: () => _showCodecPicker(context, ref),
              ),
              _buildNavItem(
                context,
                ref,
                icon: Icons.equalizer_rounded,
                title: '音频码率',
                onTap: () => _showBitratePicker(context, ref),
              ),
              _buildSwitchItem(
                context,
                ref,
                icon: Icons.hearing_rounded,
                title: '回声消除',
                value: ref.watch(settingsProvider).aecEnabled,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).saveAllSettings(
                        ref.read(settingsProvider).copyWith(aecEnabled: v),
                      );
                },
              ),
              _buildSwitchItem(
                context,
                ref,
                icon: Icons.noise_control_off_rounded,
                title: '噪声抑制',
                value: ref.watch(settingsProvider).ansEnabled,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).saveAllSettings(
                        ref.read(settingsProvider).copyWith(ansEnabled: v),
                      );
                },
              ),
              _buildSwitchItem(
                context,
                ref,
                icon: Icons.volume_up_rounded,
                title: '自动增益',
                value: ref.watch(settingsProvider).agcEnabled,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).saveAllSettings(
                        ref.read(settingsProvider).copyWith(agcEnabled: v),
                      );
                },
              ),
            ]),
            const SizedBox(height: 24.0),

            // ─── 其他设置 ───
            const Text('其他', style: styleTitle2),
            const SizedBox(height: 8.0),
            _buildGroup([
              _buildNavItem(
                context,
                ref,
                icon: Icons.cloud_rounded,
                title: '信令服务',
                onTap: () => _showSignalingPicker(context, ref),
              ),
              _buildSwitchItem(
                context,
                ref,
                icon: Icons.bug_report_rounded,
                title: '高级调试面板',
                value: ref.watch(settingsProvider).debugPanelEnabled,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).saveAllSettings(
                        ref
                            .read(settingsProvider)
                            .copyWith(debugPanelEnabled: v),
                      );
                },
              ),
            ]),

            const SizedBox(height: 32.0),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // UI 辅助方法
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildGroup(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: colorGlassBackground,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colorGlassBorder),
      ),
      child: Column(
        children: items,
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final settings = ref.watch(settingsProvider);

    // 获取当前值显示文本
    String? valueText;
    switch (title) {
      case '摄像头分辨率':
        valueText = settings.cameraResolution.label;
      case '最高帧率':
        valueText = settings.frameRate.label;
      case '画质偏好':
        valueText = settings.qualityPreference == QualityPreference.smooth
            ? '流畅优先'
            : settings.qualityPreference == QualityPreference.balanced
                ? '均衡'
                : '清晰优先';
      case '音频编码':
        valueText = settings.audioCodec;
      case '音频码率':
        valueText = '${settings.audioBitrate} Kbps';
      case '信令服务':
        valueText = _signalingLabel(settings.signalingService);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Icon(icon, size: 22.0, color: colorAccent),
            const SizedBox(width: 12.0),
            Expanded(child: Text(title, style: styleBody)),
            if (valueText != null) ...[
              Text(valueText, style: styleCaption),
              const SizedBox(width: 4.0),
            ],
            const Icon(Icons.chevron_right_rounded,
                size: 20.0, color: colorNeutral),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchItem(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          Icon(icon, size: 22.0, color: colorAccent),
          const SizedBox(width: 12.0),
          Expanded(child: Text(title, style: styleBody)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: colorAccent,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 选择器弹窗
  // ═══════════════════════════════════════════════════════════════════

  void _showResolutionPicker(BuildContext context, WidgetRef ref) {
    _showOptionSheet(
      context,
      ref,
      title: '摄像头分辨率',
      currentIndex: ref.read(settingsProvider).cameraResolution.index,
      options: CameraResolution.values.map((r) => r.label).toList(),
      descriptions: const [
        '自动模式最高 1080p @ 60fps，根据网络自适应',
        '1280×720 高清画质，适合大多数网络',
        '1920×1080 全高清画质，需较好网络',
      ],
      onSelected: (index) {
        ref.read(settingsProvider.notifier).saveAllSettings(
              ref
                  .read(settingsProvider)
                  .copyWith(cameraResolution: CameraResolution.values[index]),
            );
      },
    );
  }

  void _showFrameRatePicker(BuildContext context, WidgetRef ref) {
    _showOptionSheet(
      context,
      ref,
      title: '最高帧率',
      currentIndex: ref.read(settingsProvider).frameRate.index,
      options: FrameRateOption.values.map((f) => f.label).toList(),
      descriptions: const [
        '30fps — 标准流畅度，省电省流量',
        '45fps — 高流畅度，画面更顺滑',
        '60fps — 极致流畅，需较好网络和性能',
      ],
      onSelected: (index) {
        ref.read(settingsProvider.notifier).saveAllSettings(
              ref
                  .read(settingsProvider)
                  .copyWith(frameRate: FrameRateOption.values[index]),
            );
      },
    );
  }

  void _showQualityPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).qualityPreference;
    _showOptionSheet(
      context,
      ref,
      title: '画质偏好',
      currentIndex: QualityPreference.values.indexOf(current),
      options: const ['流畅优先', '均衡', '清晰优先'],
      descriptions: const [
        '自适应降分辨率保流畅，适合移动网络',
        '画质与流畅度平衡，适合大部分场景',
        '优先保证画质清晰，需较好网络',
      ],
      onSelected: (index) {
        ref.read(settingsProvider.notifier).saveAllSettings(
              ref
                  .read(settingsProvider)
                  .copyWith(qualityPreference: QualityPreference.values[index]),
            );
      },
    );
  }

  void _showCodecPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).audioCodec;
    const options = ['Opus 标准', 'Opus 省流', 'G.722'];
    _showOptionSheet(
      context,
      ref,
      title: '音频编码',
      currentIndex: options.indexOf(current),
      options: options,
      descriptions: const [
        'Opus 标准 — 推荐，48kHz 采样，音质最佳',
        'Opus 省流 — 16kHz 采样，节省约 40% 流量',
        'G.722 — 兼容旧设备，音质一般',
      ],
      onSelected: (index) {
        ref.read(settingsProvider.notifier).saveAllSettings(
              ref.read(settingsProvider).copyWith(audioCodec: options[index]),
            );
      },
    );
  }

  void _showBitratePicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).audioBitrate;
    const options = [24, 48, 64];
    _showOptionSheet(
      context,
      ref,
      title: '音频码率',
      currentIndex: options.indexOf(current),
      options: options.map((b) => '$b Kbps').toList(),
      descriptions: const [
        '24 Kbps — 省流模式，音质可接受',
        '48 Kbps — 标准码率，推荐',
        '64 Kbps — 高码率，音质最佳',
      ],
      onSelected: (index) {
        ref.read(settingsProvider.notifier).saveAllSettings(
              ref
                  .read(settingsProvider)
                  .copyWith(audioBitrate: options[index]),
            );
      },
    );
  }

  void _showSignalingPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).signalingService;
    final options = SignalingServiceType.values;
    _showOptionSheet(
      context,
      ref,
      title: '信令服务',
      currentIndex: options.indexOf(current),
      options: options.map((s) => _signalingLabel(s)).toList(),
      descriptions: const [
        'Firebase — 需 Google Play 服务，国内不可用',
        'Leancloud — 需注册，当前不可用',
        'WebSocket 中继 — 推荐，国内可用',
        '扫码 SDP 交换 — 无需服务器，应急后备',
      ],
      onSelected: (index) {
        ref.read(settingsProvider.notifier).updateSignalingService(
              options[index],
            );
      },
    );
  }

  /// 通用选项选择底部弹窗
  void _showOptionSheet(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required int currentIndex,
    required List<String> options,
    required List<String> descriptions,
    required ValueChanged<int> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: colorGlassBackground,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusCard)),
        ),
        padding: const EdgeInsets.all(paddingHorizontal),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: colorNeutral.withAlpha(77),
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            Text(title, style: styleTitle2),
            const SizedBox(height: 12.0),
            ...List.generate(options.length, (i) {
              final isSelected = i == currentIndex;
              return InkWell(
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSelected(i);
                },
                borderRadius: BorderRadius.circular(radiusListItem),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4.0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 14.0),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorAccent.withAlpha(15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(radiusListItem),
                    border: isSelected
                        ? Border.all(color: colorAccent.withAlpha(50))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              options[i],
                              style: styleBody.copyWith(
                                color: isSelected
                                    ? colorAccent
                                    : colorTextPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 2.0),
                            Text(
                              descriptions[i],
                              style: styleSmall.copyWith(color: colorNeutral),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: colorAccent, size: 22.0),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16.0),
          ],
        ),
      ),
    );
  }

  static String _signalingLabel(SignalingServiceType type) {
    switch (type) {
      case SignalingServiceType.firebase:
        return 'Firebase';
      case SignalingServiceType.leancloud:
        return 'Leancloud';
      case SignalingServiceType.webSocket:
        return 'WebSocket 中继';
      case SignalingServiceType.qrCode:
        return '扫码交换';
    }
  }
}
