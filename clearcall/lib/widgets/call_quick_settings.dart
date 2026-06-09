import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quality_presets.dart';
import '../providers/call_provider.dart';
import '../services/webrtc_service.dart';
import '../utils/constants.dart';

/// 通话快捷设置面板
///
/// 从通话控制栏 ⚙️ 按钮触发，底部弹出。
/// 包含画质预设快捷切换、实时网络统计、麦克风/摄像头/扬声器开关。
class CallQuickSettings extends ConsumerWidget {
  const CallQuickSettings({super.key});

  /// 显示通话快捷设置面板
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CallQuickSettings(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callProvider);
    final notifier = ref.read(callProvider.notifier);
    final stats = callState.currentStats;

    return Container(
      decoration: const BoxDecoration(
        color: colorGlassBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCard)),
      ),
      padding: const EdgeInsets.fromLTRB(
        paddingHorizontal, 12, paddingHorizontal, paddingHorizontal + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 36.0,
              height: 4.0,
              margin: const EdgeInsets.only(bottom: 16.0),
              decoration: BoxDecoration(
                color: colorNeutral.withAlpha(77),
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          ),

          // ── 标题 ──
          const Text('通话设置', style: styleTitle2),
          const SizedBox(height: 16.0),

          // ── 画质预设快捷切换 ──
          const Text('画质预设', style: styleBody),
          const SizedBox(height: 8.0),
          _buildPresetChips(context, callState, notifier),
          const SizedBox(height: 16.0),

          // ── 实时网络统计 ──
          const Text('实时网络', style: styleBody),
          const SizedBox(height: 8.0),
          _buildNetworkStats(stats),
          const SizedBox(height: 16.0),

          // ── 快速控制 ──
          const Text('快速控制', style: styleBody),
          const SizedBox(height: 8.0),
          _buildQuickToggles(callState, notifier),
          const SizedBox(height: 8.0),
        ],
      ),
    );
  }

  /// 画质预设芯片行
  Widget _buildPresetChips(
    BuildContext context,
    CallState2 state,
    CallNotifier notifier,
  ) {
    final presets = [
      QualityPreset.economy,
      QualityPreset.standard,
      QualityPreset.hd,
      QualityPreset.ultra,
    ];

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: presets.map((preset) {
        final isSelected = preset == state.currentPreset;
        return GestureDetector(
          onTap: () => notifier.switchPreset(preset),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorAccent.withAlpha(30)
                  : colorWhite.withAlpha(38),
              borderRadius: BorderRadius.circular(20.0),
              border: isSelected
                  ? Border.all(color: colorAccent.withAlpha(100))
                  : null,
            ),
            child: Text(
              preset.label,
              style: TextStyle(
                fontSize: 13.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? colorAccent : colorTextPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 网络统计展示
  Widget _buildNetworkStats(WebRTCStats? stats) {
    if (stats == null) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: colorWhite.withAlpha(25),
          borderRadius: BorderRadius.circular(radiusListItem),
        ),
        child: const Center(
          child: Text('通话未建立，暂无网络数据', style: styleSmall),
        ),
      );
    }

    final qualityColor = _qualityColor(stats.networkQualityLevel);

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: colorWhite.withAlpha(25),
        borderRadius: BorderRadius.circular(radiusListItem),
      ),
      child: Column(
        children: [
          // 延迟 + 丢包 + 质量评级
          Row(
            children: [
              _statItem('延迟', '${stats.rtt}ms'),
              const SizedBox(width: 16.0),
              _statItem('丢包', '${(stats.packetLoss * 100).toStringAsFixed(1)}%'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: qualityColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8.0,
                      height: 8.0,
                      decoration: BoxDecoration(
                        color: qualityColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6.0),
                    Text(
                      stats.networkQualityLabel,
                      style: TextStyle(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: qualityColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          // 发送/接收码率
          Row(
            children: [
              _statItem('发送', _formatBitrate(stats.videoSendBitrate)),
              const SizedBox(width: 16.0),
              _statItem('接收', _formatBitrate(stats.videoRecvBitrate)),
              const Spacer(),
              _statItem('帧率', '${stats.videoSendFps}/${stats.videoRecvFps}fps'),
            ],
          ),
          if (stats.availableBandwidth > 0) ...[
            const SizedBox(height: 4.0),
            Row(
              children: [
                _statItem('可用带宽', _formatBitrate(stats.availableBandwidth)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: styleTiny),
        const SizedBox(height: 2.0),
        Text(value, style: const TextStyle(
          fontSize: 13.0,
          fontWeight: FontWeight.w600,
          color: colorTextPrimary,
        )),
      ],
    );
  }

  /// 快速开关行
  Widget _buildQuickToggles(CallState2 state, CallNotifier notifier) {
    return Container(
      decoration: BoxDecoration(
        color: colorWhite.withAlpha(25),
        borderRadius: BorderRadius.circular(radiusListItem),
      ),
      child: Column(
        children: [
          _toggleRow(
            icon: state.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            iconColor: state.isMuted ? colorDanger : colorSuccess,
            label: state.isMuted ? '麦克风已静音' : '麦克风',
            value: !state.isMuted,
            onChanged: (_) => notifier.toggleMicrophone(),
          ),
          const Divider(height: 1, color: colorDivider),
          _toggleRow(
            icon: state.isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            iconColor: state.isCameraOn ? colorSuccess : colorDanger,
            label: state.isCameraOn ? '摄像头' : '摄像头已关闭',
            value: state.isCameraOn,
            onChanged: (_) => notifier.toggleCamera(),
          ),
          const Divider(height: 1, color: colorDivider),
          _toggleRow(
            icon: state.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            iconColor: state.isSpeakerOn ? colorSuccess : colorNeutral,
            label: state.isSpeakerOn ? '扬声器' : '听筒',
            value: state.isSpeakerOn,
            onChanged: (v) => notifier.toggleSpeaker(v),
          ),
          const Divider(height: 1, color: colorDivider),
          _toggleRow(
            icon: Icons.network_check_rounded,
            iconColor: state.autoAdaptEnabled ? colorSuccess : colorNeutral,
            label: '自动调整画质',
            value: state.autoAdaptEnabled,
            onChanged: (v) => notifier.setAutoAdapt(v),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20.0, color: iconColor),
          const SizedBox(width: 12.0),
          Expanded(child: Text(label, style: styleBody)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: colorAccent,
          ),
        ],
      ),
    );
  }

  /// 网络质量颜色
  Color _qualityColor(int level) {
    switch (level) {
      case 0:
        return colorSuccess;
      case 1:
        return colorWarning;
      case 2:
        return colorDanger;
      default:
        return colorNeutral;
    }
  }

  /// 格式化码率
  String _formatBitrate(int bps) {
    if (bps >= 1000000) {
      return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
    }
    if (bps >= 1000) {
      return '${bps ~/ 1000} Kbps';
    }
    return '$bps bps';
  }
}
