import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../utils/constants.dart';
import '../widgets/color_avatar.dart';
import '../widgets/glass_card.dart';

/// 我 Tab
///
/// 包含：头像+昵称编辑、设置列表（摄像头/帧率/画质/音频/调试等）。
/// 阶段 1 为静态界面，设置项可浏览但切换功能在阶段 2 实现。
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8.0),

          // 头像 + 昵称区
          _buildProfileHeader(settings),
          const SizedBox(height: 32.0),

          // 设置分组：视频
          const Text('视频', style: styleTitle2),
          const SizedBox(height: 8.0),
          _buildSettingsGroup([
            _buildSettingItem('摄像头分辨率', settings.cameraResolution,
                Icons.hd_rounded),
            _buildSettingItem('最高帧率', '${settings.frameRate}fps',
                Icons.speed_rounded),
            _buildSettingItem(
              '画质偏好',
              settings.qualityPreference == QualityPreference.smooth
                  ? '流畅优先'
                  : settings.qualityPreference == QualityPreference.balanced
                      ? '均衡'
                      : '清晰优先',
              Icons.tune_rounded,
            ),
            _buildSettingItem(
              'H.265 编码',
              settings.h265Enabled ? '开' : '关',
              Icons.videocam_rounded,
            ),
          ]),
          const SizedBox(height: 24.0),

          // 设置分组：音频
          const Text('音频', style: styleTitle2),
          const SizedBox(height: 8.0),
          _buildSettingsGroup([
            _buildSettingItem('音频编码', settings.audioCodec,
                Icons.music_note_rounded),
            _buildSettingItem(
                '音频码率', '${settings.audioBitrate} Kbps', Icons.equalizer_rounded),
            _buildSettingItem(
              '回声消除',
              settings.aecEnabled ? '开' : '关',
              Icons.hearing_rounded,
            ),
            _buildSettingItem(
              '噪声抑制',
              settings.ansEnabled ? '开' : '关',
              Icons.noise_control_off_rounded,
            ),
            _buildSettingItem(
              '自动增益',
              settings.agcEnabled ? '开' : '关',
              Icons.volume_up_rounded,
            ),
          ]),
          const SizedBox(height: 24.0),

          // 设置分组：其他
          const Text('其他', style: styleTitle2),
          const SizedBox(height: 8.0),
          _buildSettingsGroup([
            _buildSettingItem(
              '信令服务',
              'Firebase',
              Icons.cloud_rounded,
            ),
            _buildSettingItem(
              '高级调试面板',
              settings.debugPanelEnabled ? '开' : '关',
              Icons.bug_report_rounded,
            ),
          ]),

          const SizedBox(height: 32.0),

          // App 版本信息
          Center(
            child: Text(
              'ClearCall v0.1.0',
              style: styleSmall.copyWith(color: colorNeutral),
            ),
          ),
          const SizedBox(height: 16.0),
        ],
      ),
    );
  }

  /// 头像 + 昵称区
  Widget _buildProfileHeader(AppSettings settings) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 24.0),
          ColorAvatar(
            nickname: settings.nickname,
            size: 80.0,
            borderRadius: 32.0,
          ),
          const SizedBox(height: 12.0),
          Text(settings.nickname, style: styleTitle2),
          const SizedBox(height: 4.0),
          Text(
            'ID: ${settings.localId.isEmpty ? '未生成' : settings.localId.substring(0, 8)}...',
            style: styleSmall,
          ),
        ],
      ),
    );
  }

  /// 设置分组容器（磨砂卡片）
  Widget _buildSettingsGroup(List<Widget> items) {
    return GlassCard(
      child: Column(
        children: items,
      ),
    );
  }

  /// 单个设置项
  Widget _buildSettingItem(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 16.0, vertical: 14.0),
      child: Row(
        children: [
          Icon(icon, size: 22.0, color: colorAccent),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(title, style: styleBody),
          ),
          Text(value, style: styleCaption),
          const SizedBox(width: 4.0),
          const Icon(Icons.chevron_right_rounded,
              size: 20.0, color: colorNeutral),
        ],
      ),
    );
  }
}
