import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quality_presets.dart';
import '../providers/settings_provider.dart';
import '../utils/constants.dart';
import '../widgets/glass_dialog.dart';

/// 设置页面
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
            // ─── 画质预设 ───
            const Text('画质预设', style: styleTitle2),
            const SizedBox(height: 8.0),
            _buildGroup([
              _buildNavItem(
                context, ref,
                icon: Icons.tune_rounded,
                title: '当前预设',
                onTap: () => _showPresetPicker(context, ref),
              ),
              _buildSwitchItem(
                context, ref,
                icon: Icons.network_check_rounded,
                title: '自动调整画质',
                subtitle: '根据网络状况自动升降画质档位',
                value: ref.watch(settingsProvider).autoAdaptEnabled,
                onChanged: (v) => _saveSetting(ref, (s) => s.copyWith(autoAdaptEnabled: v)),
              ),
            ]),
            const SizedBox(height: 24.0),

            // ─── 视频设置 ───
            const Text('视频', style: styleTitle2),
            const SizedBox(height: 8.0),
            _buildGroup([
              _buildNavItem(
                context, ref,
                icon: Icons.hd_rounded,
                title: '摄像头分辨率',
                onTap: () => _showResolutionPicker(context, ref),
              ),
              _buildNavItem(
                context, ref,
                icon: Icons.speed_rounded,
                title: '最高帧率',
                onTap: () => _showFrameRatePicker(context, ref),
              ),
              _buildNavItem(
                context, ref,
                icon: Icons.videocam_rounded,
                title: '视频编码',
                onTap: () => _showVideoCodecPicker(context, ref),
              ),
              _buildNavItem(
                context, ref,
                icon: Icons.data_usage_rounded,
                title: '视频码率上限',
                onTap: () => _showVideoBitratePicker(context, ref),
              ),
              _buildNavItem(
                context, ref,
                icon: Icons.tune_rounded,
                title: '画质偏好',
                onTap: () => _showQualityPicker(context, ref),
              ),
            ]),
            const SizedBox(height: 24.0),

            // ─── 音频设置 ───
            const Text('音频', style: styleTitle2),
            const SizedBox(height: 8.0),
            _buildGroup([
              _buildNavItem(
                context, ref,
                icon: Icons.music_note_rounded,
                title: '音频编码',
                onTap: () => _showCodecPicker(context, ref),
              ),
              _buildNavItem(
                context, ref,
                icon: Icons.equalizer_rounded,
                title: '音频码率',
                onTap: () => _showBitratePicker(context, ref),
              ),
              _buildSwitchItem(
                context, ref,
                icon: Icons.hearing_rounded,
                title: '回声消除',
                value: ref.watch(settingsProvider).aecEnabled,
                onChanged: (v) => _saveSetting(ref, (s) => s.copyWith(aecEnabled: v)),
              ),
              _buildSwitchItem(
                context, ref,
                icon: Icons.noise_control_off_rounded,
                title: '噪声抑制',
                value: ref.watch(settingsProvider).ansEnabled,
                onChanged: (v) => _saveSetting(ref, (s) => s.copyWith(ansEnabled: v)),
              ),
              _buildSwitchItem(
                context, ref,
                icon: Icons.volume_up_rounded,
                title: '自动增益',
                value: ref.watch(settingsProvider).agcEnabled,
                onChanged: (v) => _saveSetting(ref, (s) => s.copyWith(agcEnabled: v)),
              ),
            ]),
            const SizedBox(height: 24.0),

            // ─── 其他设置 ───
            const Text('其他', style: styleTitle2),
            const SizedBox(height: 8.0),
            _buildGroup([
              _buildSwitchItem(
                context, ref,
                icon: Icons.bug_report_rounded,
                title: '调试面板',
                value: ref.watch(settingsProvider).debugPanelEnabled,
                onChanged: (v) => _saveSetting(ref, (s) => s.copyWith(debugPanelEnabled: v)),
              ),
            ]),
            const SizedBox(height: 32.0),
          ],
        ),
      ),
    );
  }

  void _saveSetting(WidgetRef ref, AppSettings Function(AppSettings) fn) {
    final s = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).saveAllSettings(fn(s));
  }

  // ═══════════════════════════════════════════════════════════════════
  // UI builders
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildGroup(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: colorGlassBackground,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colorGlassBorder),
      ),
      child: Column(children: items),
    );
  }

  Widget _buildNavItem(
    BuildContext context, WidgetRef ref, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final settings = ref.watch(settingsProvider);
    String? valueText;
    switch (title) {
      case '当前预设': valueText = settings.selectedPreset.label;
      case '摄像头分辨率': valueText = settings.cameraResolution.label;
      case '最高帧率': valueText = settings.frameRate.label;
      case '视频编码': valueText = videoCodecLabel(settings.videoCodec);
      case '视频码率上限': valueText = videoBitrateLabel(settings.videoBitrate);
      case '画质偏好':
        valueText = settings.qualityPreference == QualityPreference.smooth
            ? '流畅优先'
            : settings.qualityPreference == QualityPreference.balanced
                ? '均衡'
                : '清晰优先';
      case '音频编码': valueText = settings.audioCodec;
      case '音频码率': valueText = '${settings.audioBitrate} Kbps';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Icon(icon, size: 22.0, color: colorAccent),
            const SizedBox(width: 12.0),
            Expanded(child: Text(title, style: styleBody)),
            if (valueText != null) ...[
              Text(valueText, style: styleCaption),
              const SizedBox(width: 4.0),
            ],
            const Icon(Icons.chevron_right_rounded, size: 20.0, color: colorNeutral),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchItem(
    BuildContext context, WidgetRef ref, {
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          Icon(icon, size: 22.0, color: colorAccent),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: styleBody),
                if (subtitle != null) ...[
                  const SizedBox(height: 2.0),
                  Text(subtitle, style: styleSmall),
                ],
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeTrackColor: colorAccent),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Pickers
  // ═══════════════════════════════════════════════════════════════════

  void _showResolutionPicker(BuildContext context, WidgetRef ref) {
    _showOptionSheet(context, title: '摄像头分辨率',
      currentIndex: ref.read(settingsProvider).cameraResolution.index,
      options: CameraResolution.values.map((r) => r.label).toList(),
      descriptions: const [
        '自动模式最高 1080p @ 60fps',
        '1280×720 高清画质',
        '1920×1080 全高清画质',
      ],
      onSelected: (i) => _saveSetting(ref, (s) => s.copyWith(cameraResolution: CameraResolution.values[i])),
    );
  }

  void _showFrameRatePicker(BuildContext context, WidgetRef ref) {
    _showOptionSheet(context, title: '最高帧率',
      currentIndex: ref.read(settingsProvider).frameRate.index,
      options: FrameRateOption.values.map((f) => f.label).toList(),
      descriptions: const ['24fps — 省电省流量', '30fps — 平衡推荐', '45fps — 更顺滑', '60fps — 极致流畅'],
      onSelected: (i) => _saveSetting(ref, (s) => s.copyWith(frameRate: FrameRateOption.values[i])),
    );
  }

  void _showQualityPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).qualityPreference;
    _showOptionSheet(context, title: '画质偏好',
      currentIndex: QualityPreference.values.indexOf(current),
      options: const ['流畅优先', '均衡', '清晰优先'],
      descriptions: const [
        '自适应降分辨率保流畅',
        '画质与流畅度平衡',
        '优先保证画质清晰',
      ],
      onSelected: (i) => _saveSetting(ref, (s) => s.copyWith(qualityPreference: QualityPreference.values[i])),
    );
  }

  void _showCodecPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).audioCodec;
    const options = ['Opus 标准', 'Opus 省流', 'G.722'];
    _showOptionSheet(context, title: '音频编码',
      currentIndex: options.indexOf(current),
      options: options,
      descriptions: const [
        'Opus 标准 — 48kHz 采样，推荐',
        'Opus 省流 — 16kHz 采样，省40%流量',
        'G.722 — 兼容旧设备',
      ],
      onSelected: (i) => _saveSetting(ref, (s) => s.copyWith(
            audioCodec: options[i],
            selectedPreset: QualityPreset.custom,
          )),
    );
  }

  void _showBitratePicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).audioBitrate;
    const options = [24, 48, 64];
    _showOptionSheet(context, title: '音频码率',
      currentIndex: options.indexOf(current),
      options: options.map((b) => '$b Kbps').toList(),
      descriptions: const ['24 Kbps — 省流', '48 Kbps — 推荐', '64 Kbps — 高音质'],
      onSelected: (i) => _saveSetting(ref, (s) => s.copyWith(
            audioBitrate: options[i],
            selectedPreset: QualityPreset.custom,
          )),
    );
  }

  void _showPresetPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).selectedPreset;
    final presets = QualityPreset.values;
    _showOptionSheet(
      context,
      title: '画质预设',
      currentIndex: presets.indexOf(current),
      options: presets.map((p) => p.label).toList(),
      descriptions: presets.map((p) => p.shortDesc).toList(),
      onSelected: (i) {
        final preset = presets[i];
        _saveSetting(ref, (s) => s.copyWith(selectedPreset: preset));
        // 切换预设时同步更新各项子设置为预设默认值
        if (preset != QualityPreset.custom) {
          final spec = presetSpecs[preset];
          if (spec != null) {
            _saveSetting(ref, (s) => s.copyWith(
                  videoCodec: spec.videoCodec,
                  videoBitrate: spec.videoMaxBitrate,
                  selectedPreset: preset,
                ));
          }
        }
      },
    );
  }

  void _showVideoCodecPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).videoCodec;
    final codes = videoCodecOptions;
    _showOptionSheet(
      context,
      title: '视频编码',
      currentIndex: codes.indexOf(current),
      options: codes.map((c) => videoCodecLabel(c)).toList(),
      descriptions: const [
        'H.264 — 兼容性最好，推荐',
        'H.265/HEVC — 省 40% 流量，画质相同',
      ],
      onSelected: (i) => _saveSetting(ref, (s) => s.copyWith(
            videoCodec: codes[i],
            selectedPreset: QualityPreset.custom,
          )),
    );
  }

  void _showVideoBitratePicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(settingsProvider).videoBitrate;
    final bits = videoBitrateOptions;
    _showOptionSheet(
      context,
      title: '视频码率上限',
      currentIndex: bits.indexOf(current),
      options: bits.map((b) => videoBitrateLabel(b)).toList(),
      descriptions: const [
        '500 Kbps — 省流模式',
        '1 Mbps — 低画质',
        '2.5 Mbps — 标准画质',
        '4 Mbps — 高清画质',
        '6 Mbps — 极清画质',
        '10 Mbps — 超清画质',
      ],
      onSelected: (i) => _saveSetting(ref, (s) => s.copyWith(
            videoBitrate: bits[i],
            selectedPreset: QualityPreset.custom,
          )),
    );
  }

  void _showOptionSheet(
    BuildContext context, {
    required String title,
    required int currentIndex,
    required List<String> options,
    required List<String> descriptions,
    required ValueChanged<int> onSelected,
  }) {
    showGlassBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: colorGlassBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCard)),
        ),
        padding: const EdgeInsets.all(paddingHorizontal),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: colorNeutral.withAlpha(77),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: styleTitle2),
            const SizedBox(height: 12),
            ...List.generate(options.length, (i) {
              final selected = i == currentIndex;
              return InkWell(
                onTap: () { Navigator.of(ctx).pop(); onSelected(i); },
                borderRadius: BorderRadius.circular(radiusListItem),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? colorAccent.withAlpha(15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(radiusListItem),
                    border: selected ? Border.all(color: colorAccent.withAlpha(50)) : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(options[i], style: styleBody.copyWith(
                              color: selected ? colorAccent : colorTextPrimary,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            )),
                            const SizedBox(height: 2),
                            Text(descriptions[i], style: styleSmall.copyWith(color: colorNeutral)),
                          ],
                        ),
                      ),
                      if (selected) const Icon(Icons.check_circle_rounded, color: colorAccent, size: 22),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
