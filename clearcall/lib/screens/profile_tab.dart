import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../providers/settings_provider.dart';
import '../utils/constants.dart';
import '../widgets/color_avatar.dart';
import 'settings_screen.dart';

/// 我 Tab
///
/// 包含：头像+昵称、快捷设置入口、App 版本信息。
/// 视频/音频详细设置已迁移到 SettingsScreen 二级页面。
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

          // 快捷设置入口（跳转完整设置页）
          const Text('快捷查看', style: styleTitle2),
          const SizedBox(height: 8.0),
          _buildQuickViewGroup(context, ref, settings),
          const SizedBox(height: 24.0),

          // 设置入口按钮
          SizedBox(
            width: double.infinity,
            child: _buildSettingsEntry(context),
          ),
          const SizedBox(height: 24.0),

          // App 版本信息
          Center(
            child: Text(
              'ClearCall v0.2.0',
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
          const SizedBox(height: 32.0),
          ColorAvatar(
            nickname: settings.nickname,
            size: 88.0,
            borderRadius: 36.0,
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

  /// 快捷查看组（当前设置只读，点击跳转设置页修改）
  Widget _buildQuickViewGroup(
      BuildContext context, WidgetRef ref, AppSettings settings) {
    return Container(
      decoration: BoxDecoration(
        color: colorGlassBackground,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: colorGlassBorder),
      ),
      child: Column(
        children: [
          _buildInfoItem(
            icon: Icons.hd_rounded,
            title: '摄像头分辨率',
            value: settings.cameraResolution.label,
          ),
          _divider(),
          _buildInfoItem(
            icon: Icons.speed_rounded,
            title: '最高帧率',
            value: settings.frameRate.label,
          ),
          _divider(),
          _buildInfoItem(
            icon: Icons.tune_rounded,
            title: '画质偏好',
            value: settings.qualityPreference == QualityPreference.smooth
                ? '流畅优先'
                : settings.qualityPreference == QualityPreference.balanced
                    ? '均衡'
                    : '清晰优先',
          ),
          _divider(),
          _buildInfoItem(
            icon: Icons.music_note_rounded,
            title: '音频编码',
            value: settings.audioCodec,
          ),
        ],
      ),
    );
  }

  /// 设置入口按钮
  Widget _buildSettingsEntry(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      },
      child: Container(
        height: 56.0,
        decoration: BoxDecoration(
          color: colorAccent.withAlpha(20),
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: colorAccent.withAlpha(50)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.settings_rounded,
                color: colorAccent, size: 22.0),
            const SizedBox(width: 8.0),
            Text(
              '打开全部设置',
              style: styleBody.copyWith(
                color: colorAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 快捷信息项（只读）
  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      child: Row(
        children: [
          Icon(icon, size: 22.0, color: colorAccent),
          const SizedBox(width: 12.0),
          Expanded(child: Text(title, style: styleBody)),
          Text(value, style: styleCaption),
        ],
      ),
    );
  }

  /// 分割线
  Widget _divider() {
    return const Divider(
      color: colorDivider,
      height: 1.0,
      indent: 52.0,
      endIndent: 16.0,
    );
  }
}
