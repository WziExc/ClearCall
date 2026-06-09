import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 画质偏好三档
enum QualityPreference {
  smooth,   // 流畅优先（默认）
  balanced, // 均衡
  clear,    // 清晰优先
}

/// 摄像头分辨率选项
enum CameraResolution {
  auto('自适应'),
  hd('720p'),
  fhd('1080p');

  final String label;
  const CameraResolution(this.label);

  int get width {
    switch (this) {
      case auto:
      case fhd: return 1920;
      case hd: return 1280;
    }
  }

  int get height {
    switch (this) {
      case auto:
      case fhd: return 1080;
      case hd: return 720;
    }
  }
}

/// 帧率选项
enum FrameRateOption {
  fps30(30, '30fps'),
  fps45(45, '45fps'),
  fps60(60, '60fps');

  final int fps;
  final String label;
  const FrameRateOption(this.fps, this.label);
}

/// 应用设置状态
class AppSettings {
  final String nickname;
  final String localId;
  final bool isFirstLaunch;
  final CameraResolution cameraResolution;
  final FrameRateOption frameRate;
  final QualityPreference qualityPreference;
  final bool h265Enabled;
  final String audioCodec;
  final int audioBitrate;
  final bool aecEnabled;
  final bool ansEnabled;
  final bool agcEnabled;
  final bool mobileWarningShown;
  final bool debugPanelEnabled;

  const AppSettings({
    required this.nickname,
    required this.localId,
    required this.isFirstLaunch,
    this.cameraResolution = CameraResolution.auto,
    this.frameRate = FrameRateOption.fps60,
    this.qualityPreference = QualityPreference.smooth,
    this.h265Enabled = false,
    this.audioCodec = 'Opus 标准',
    this.audioBitrate = 48,
    this.aecEnabled = true,
    this.ansEnabled = true,
    this.agcEnabled = true,
    this.mobileWarningShown = false,
    this.debugPanelEnabled = false,
  });

  factory AppSettings.defaults({required String localId}) {
    return AppSettings(
      nickname: localId.isEmpty ? '' : 'User${localId.substring(0, 4)}',
      localId: localId,
      isFirstLaunch: true,
    );
  }

  int get effectiveWidth => cameraResolution.width;
  int get effectiveHeight => cameraResolution.height;
  int get effectiveFps => frameRate.fps;

  AppSettings copyWith({
    String? nickname,
    String? localId,
    bool? isFirstLaunch,
    CameraResolution? cameraResolution,
    FrameRateOption? frameRate,
    QualityPreference? qualityPreference,
    bool? h265Enabled,
    String? audioCodec,
    int? audioBitrate,
    bool? aecEnabled,
    bool? ansEnabled,
    bool? agcEnabled,
    bool? mobileWarningShown,
    bool? debugPanelEnabled,
  }) {
    return AppSettings(
      nickname: nickname ?? this.nickname,
      localId: localId ?? this.localId,
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      cameraResolution: cameraResolution ?? this.cameraResolution,
      frameRate: frameRate ?? this.frameRate,
      qualityPreference: qualityPreference ?? this.qualityPreference,
      h265Enabled: h265Enabled ?? this.h265Enabled,
      audioCodec: audioCodec ?? this.audioCodec,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      aecEnabled: aecEnabled ?? this.aecEnabled,
      ansEnabled: ansEnabled ?? this.ansEnabled,
      agcEnabled: agcEnabled ?? this.agcEnabled,
      mobileWarningShown: mobileWarningShown ?? this.mobileWarningShown,
      debugPanelEnabled: debugPanelEnabled ?? this.debugPanelEnabled,
    );
  }
}

/// 设置状态管理器
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(super.state);

  static Future<AppSettings> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final localId = prefs.getString(prefLocalId) ?? '';
    final isFirstLaunch = prefs.getBool(prefFirstLaunch) ?? true;

    if (localId.isEmpty) {
      return AppSettings.defaults(localId: '');
    }

    return AppSettings(
      nickname: prefs.getString(prefNickname) ?? 'User',
      localId: localId,
      isFirstLaunch: isFirstLaunch,
      cameraResolution: CameraResolution.values[
        prefs.getInt(prefCameraResolution) ?? 0],
      frameRate: FrameRateOption.values[
        prefs.getInt(prefFrameRate) ?? 2],
      qualityPreference: QualityPreference.values[
        prefs.getInt(prefQualityPreference) ?? 0],
      h265Enabled: prefs.getBool(prefH265Enabled) ?? false,
      audioCodec: prefs.getString(prefAudioCodec) ?? 'Opus 标准',
      audioBitrate: prefs.getInt(prefAudioBitrate) ?? 48,
      aecEnabled: prefs.getBool(prefAEC) ?? true,
      ansEnabled: prefs.getBool(prefANS) ?? true,
      agcEnabled: prefs.getBool(prefAGC) ?? true,
      mobileWarningShown: prefs.getBool(prefMobileWarningShown) ?? false,
      debugPanelEnabled: prefs.getBool(prefDebugPanel) ?? false,
    );
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefNickname, state.nickname);
    await prefs.setBool(prefFirstLaunch, state.isFirstLaunch);
    await prefs.setInt(prefCameraResolution, state.cameraResolution.index);
    await prefs.setInt(prefFrameRate, state.frameRate.index);
    await prefs.setInt(prefQualityPreference, state.qualityPreference.index);
    await prefs.setBool(prefH265Enabled, state.h265Enabled);
    await prefs.setString(prefAudioCodec, state.audioCodec);
    await prefs.setInt(prefAudioBitrate, state.audioBitrate);
    await prefs.setBool(prefAEC, state.aecEnabled);
    await prefs.setBool(prefANS, state.ansEnabled);
    await prefs.setBool(prefAGC, state.agcEnabled);
    await prefs.setBool(prefMobileWarningShown, state.mobileWarningShown);
    await prefs.setBool(prefDebugPanel, state.debugPanelEnabled);
  }

  Future<void> updateNickname(String nickname) async {
    state = state.copyWith(nickname: nickname);
    await _saveToPrefs();
  }

  Future<void> saveLocalId(String localId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefLocalId, localId);
    state = state.copyWith(localId: localId);
  }

  Future<void> completeFirstLaunch() async {
    state = state.copyWith(isFirstLaunch: false);
    await _saveToPrefs();
  }

  Future<void> updateQualityPreference(QualityPreference pref) async {
    state = state.copyWith(qualityPreference: pref);
    await _saveToPrefs();
  }

  Future<void> saveAllSettings(AppSettings newSettings) async {
    state = newSettings;
    await _saveToPrefs();
  }

  void updateAll(AppSettings newSettings) {
    state = newSettings;
  }
}

/// 设置 Provider
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  throw UnimplementedError(
      '必须在 App 初始化时通过 override 提供 SettingsNotifier');
});
