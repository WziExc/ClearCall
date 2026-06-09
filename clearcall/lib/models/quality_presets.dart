import '../services/webrtc_service.dart';

/// 画质预设等级
///
/// 提供 5 档预设 + 1 档自定义，每档对应一组完整的音视频参数。
/// 用户可在设置中一键切换，也可逐项自定义（自动切换为 custom 档）。
enum QualityPreset {
  /// 🌱 省流模式 — 移动数据 / 弱网环境
  economy,

  /// 📺 标准模式 — 默认推荐，日常 Wi-Fi 通话
  standard,

  /// 🎬 高清模式 — Wi-Fi 优质网络
  hd,

  /// 🚀 极清模式 — 追求极致画质（需 H.265 支持）
  ultra,

  /// ✏️ 自定义 — 用户自由搭配各项参数
  custom,
}

/// 预设扩展方法
extension QualityPresetExt on QualityPreset {
  /// 预设显示名称
  String get label {
    switch (this) {
      case QualityPreset.economy:
        return '省流模式';
      case QualityPreset.standard:
        return '标准模式';
      case QualityPreset.hd:
        return '高清模式';
      case QualityPreset.ultra:
        return '极清模式';
      case QualityPreset.custom:
        return '自定义';
    }
  }

  /// 预设简短描述（一行）
  String get shortDesc {
    switch (this) {
      case QualityPreset.economy:
        return '480p · 24fps · H.264 · 500K — 省电省流量';
      case QualityPreset.standard:
        return '720p · 30fps · H.264 · 2.5M — 平衡推荐';
      case QualityPreset.hd:
        return '1080p · 30fps · H.264 · 4M — 全高清画质';
      case QualityPreset.ultra:
        return '1080p · 60fps · H.265 · 6M — 极致体验';
      case QualityPreset.custom:
        return '自由搭配各项参数';
    }
  }

  /// 预设图标（Material Icons 名称）
  String get iconName {
    switch (this) {
      case QualityPreset.economy:
        return 'eco';
      case QualityPreset.standard:
        return 'tune';
      case QualityPreset.hd:
        return 'hd';
      case QualityPreset.ultra:
        return 'rocket_launch';
      case QualityPreset.custom:
        return 'build_circle';
    }
  }
}

/// 预设参数规格
///
/// 每档预设的完整音视频参数，用于：
/// - UI 展示（设置页面预设选择器）
/// - 生成 MediaConfig（传给 WebRTCService）
class PresetSpec {
  final QualityPreset preset;
  final int videoWidth;
  final int videoHeight;
  final int videoFps;
  final String videoCodec;
  final int videoMaxBitrate;
  final String audioCodec;
  final int audioSampleRate;
  final int audioBitrate;
  final String qualityPreference;

  const PresetSpec({
    required this.preset,
    required this.videoWidth,
    required this.videoHeight,
    required this.videoFps,
    required this.videoCodec,
    required this.videoMaxBitrate,
    required this.audioCodec,
    required this.audioSampleRate,
    required this.audioBitrate,
    required this.qualityPreference,
  });

  /// 分辨率标签（如 "640×480"）
  String get resolutionLabel => '$videoWidth×$videoHeight';

  /// 视频码率标签（如 "500 Kbps"）
  String get videoBitrateLabel {
    if (videoMaxBitrate >= 1000000) {
      return '${(videoMaxBitrate / 1000000).toStringAsFixed(1)} Mbps';
    }
    return '${videoMaxBitrate ~/ 1000} Kbps';
  }

  /// 音频码率标签
  String get audioBitrateLabel => '$audioBitrate Kbps';

  /// 视频编码器标签
  String get videoCodecLabel {
    switch (videoCodec) {
      case 'H264':
        return 'H.264';
      case 'H265':
        return 'H.265/HEVC';
      case 'VP8':
        return 'VP8';
      case 'VP9':
        return 'VP9';
      default:
        return videoCodec;
    }
  }

  /// 转换为 MediaConfig
  MediaConfig toMediaConfig() {
    return MediaConfig(
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      videoFps: videoFps,
      videoCodec: videoCodec,
      videoMaxBitrate: videoMaxBitrate,
      audioCodec: audioCodec,
      audioSampleRate: audioSampleRate,
      audioBitrate: audioBitrate,
      qualityPreference: qualityPreference,
    );
  }
}

/// 5 档内置预设的参数矩阵
///
/// | 参数 | 省流 | 标准 | 高清 | 极清 |
/// |------|------|------|------|------|
/// | 分辨率 | 640×480 | 1280×720 | 1920×1080 | 1920×1080 |
/// | 帧率 | 24fps | 30fps | 30fps | 60fps |
/// | 视频编码 | H.264 | H.264 | H.264 | H.265 |
/// | 视频码率 | 500K | 2.5M | 4M | 6M |
/// | 音频编码 | Opus | Opus | Opus | Opus |
/// | 音频采样率 | 16kHz | 48kHz | 48kHz | 48kHz |
/// | 音频码率 | 24K | 48K | 64K | 96K |
/// | 画质偏好 | smooth | smooth | balanced | clear |
const Map<QualityPreset, PresetSpec> presetSpecs = {
  QualityPreset.economy: PresetSpec(
    preset: QualityPreset.economy,
    videoWidth: 640,
    videoHeight: 480,
    videoFps: 24,
    videoCodec: 'H264',
    videoMaxBitrate: 500000, // 500 Kbps
    audioCodec: 'opus',
    audioSampleRate: 16000,
    audioBitrate: 24000, // 24 Kbps
    qualityPreference: 'smooth',
  ),
  QualityPreset.standard: PresetSpec(
    preset: QualityPreset.standard,
    videoWidth: 1280,
    videoHeight: 720,
    videoFps: 30,
    videoCodec: 'H264',
    videoMaxBitrate: 2500000, // 2.5 Mbps
    audioCodec: 'opus',
    audioSampleRate: 48000,
    audioBitrate: 48000, // 48 Kbps
    qualityPreference: 'smooth',
  ),
  QualityPreset.hd: PresetSpec(
    preset: QualityPreset.hd,
    videoWidth: 1920,
    videoHeight: 1080,
    videoFps: 30,
    videoCodec: 'H264',
    videoMaxBitrate: 4000000, // 4 Mbps
    audioCodec: 'opus',
    audioSampleRate: 48000,
    audioBitrate: 64000, // 64 Kbps
    qualityPreference: 'balanced',
  ),
  QualityPreset.ultra: PresetSpec(
    preset: QualityPreset.ultra,
    videoWidth: 1920,
    videoHeight: 1080,
    videoFps: 60,
    videoCodec: 'H265',
    videoMaxBitrate: 6000000, // 6 Mbps
    audioCodec: 'opus',
    audioSampleRate: 48000,
    audioBitrate: 96000, // 96 Kbps
    qualityPreference: 'clear',
  ),
};

/// 根据预设 + 自定义设置生成 MediaConfig
///
/// 如果 [preset] 是 custom，则从 [customWidth]/[customHeight] 等参数构建；
/// 否则直接使用内置预设表。
MediaConfig presetToMediaConfig(
  QualityPreset preset, {
  // 自定义参数（仅 custom 预设时使用）
  int customWidth = 1280,
  int customHeight = 720,
  int customFps = 30,
  String customVideoCodec = 'H264',
  int customVideoBitrate = 2500000,
  String customAudioCodec = 'opus',
  int customAudioSampleRate = 48000,
  int customAudioBitrate = 48000,
  String customQualityPref = 'smooth',
  bool aecEnabled = true,
  bool ansEnabled = true,
  bool agcEnabled = true,
  bool frontFlashEnabled = false,
}) {
  if (preset == QualityPreset.custom) {
    return MediaConfig(
      videoWidth: customWidth,
      videoHeight: customHeight,
      videoFps: customFps,
      videoCodec: customVideoCodec,
      videoMaxBitrate: customVideoBitrate,
      audioCodec: customAudioCodec,
      audioSampleRate: customAudioSampleRate,
      audioBitrate: customAudioBitrate,
      qualityPreference: customQualityPref,
      aecEnabled: aecEnabled,
      ansEnabled: ansEnabled,
      agcEnabled: agcEnabled,
      frontFlashEnabled: frontFlashEnabled,
    );
  }

  final spec = presetSpecs[preset] ?? presetSpecs[QualityPreset.standard]!;
  return spec.toMediaConfig().copyWith(
        aecEnabled: aecEnabled,
        ansEnabled: ansEnabled,
        agcEnabled: agcEnabled,
        frontFlashEnabled: frontFlashEnabled,
      );
}

/// 视频码率选项列表（供选择器使用）
const List<int> videoBitrateOptions = [
  500000,   // 500 Kbps
  1000000,  // 1 Mbps
  2500000,  // 2.5 Mbps
  4000000,  // 4 Mbps
  6000000,  // 6 Mbps
  10000000, // 10 Mbps
];

/// 视频码率显示标签
String videoBitrateLabel(int bitrate) {
  if (bitrate >= 1000000) {
    return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
  }
  return '${bitrate ~/ 1000} Kbps';
}

/// 音频码率选项列表（供选择器使用）
const List<int> audioBitrateOptions = [24, 48, 64, 96];

/// 音频码率显示标签
String audioBitrateLabel(int bitrate) => '$bitrate Kbps';

/// 视频编码器选项
const List<String> videoCodecOptions = ['H264', 'H265'];

/// 视频编码器显示标签
String videoCodecLabel(String codec) {
  switch (codec) {
    case 'H264':
      return 'H.264';
    case 'H265':
      return 'H.265/HEVC';
    default:
      return codec;
  }
}
