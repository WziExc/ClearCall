import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 画质偏好三档
enum QualityPreference {
  /// 流畅优先（默认）：自适应降分辨率保流畅
  smooth,

  /// 均衡：画质与流畅度平衡
  balanced,

  /// 清晰优先：优先保证画质
  clear,
}

/// 应用设置状态
class AppSettings {
  /// 用户昵称
  final String nickname;

  /// 本地唯一 ID
  final String localId;

  /// 是否首次启动
  final bool isFirstLaunch;

  /// 摄像头分辨率（自适应 / 720p / 1080p）
  final String cameraResolution;

  /// 最高帧率（30 / 60）
  final int frameRate;

  /// 画质偏好
  final QualityPreference qualityPreference;

  /// H.265 编码开关
  final bool h265Enabled;

  /// 音频编码格式
  final String audioCodec;

  /// 音频码率（Kbps）
  final int audioBitrate;

  /// 回声消除开关
  final bool aecEnabled;

  /// 噪声抑制开关
  final bool ansEnabled;

  /// 自动增益开关
  final bool agcEnabled;

  /// 是否已显示流量警告
  final bool mobileWarningShown;

  /// 调试面板开关
  final bool debugPanelEnabled;

  const AppSettings({
    required this.nickname,
    required this.localId,
    required this.isFirstLaunch,
    this.cameraResolution = '自适应',
    this.frameRate = 30,
    this.qualityPreference = QualityPreference.smooth,
    this.h265Enabled = false,
    this.audioCodec = 'Opus 48kHz',
    this.audioBitrate = 48,
    this.aecEnabled = true,
    this.ansEnabled = true,
    this.agcEnabled = true,
    this.mobileWarningShown = false,
    this.debugPanelEnabled = false,
  });

  /// 创建默认设置
  factory AppSettings.defaults({required String localId}) {
    return AppSettings(
      nickname: localId.isEmpty ? '' : 'User${localId.substring(0, 4)}',
      localId: localId,
      isFirstLaunch: true,
    );
  }

  AppSettings copyWith({
    String? nickname,
    bool? isFirstLaunch,
    String? cameraResolution,
    int? frameRate,
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
      localId: localId,
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

  /// 从 SharedPreferences 加载设置
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
      cameraResolution: prefs.getString(prefCameraResolution) ?? '自适应',
      frameRate: prefs.getInt(prefFrameRate) ?? 30,
      qualityPreference: QualityPreference.values[
        prefs.getInt(prefQualityPreference) ?? 0],
      h265Enabled: prefs.getBool(prefH265Enabled) ?? false,
      audioCodec: prefs.getString(prefAudioCodec) ?? 'Opus 48kHz',
      audioBitrate: prefs.getInt(prefAudioBitrate) ?? 48,
      aecEnabled: prefs.getBool(prefAEC) ?? true,
      ansEnabled: prefs.getBool(prefANS) ?? true,
      agcEnabled: prefs.getBool(prefAGC) ?? true,
      mobileWarningShown: prefs.getBool(prefMobileWarningShown) ?? false,
      debugPanelEnabled: prefs.getBool(prefDebugPanel) ?? false,
    );
  }

  /// 持久化设置到 SharedPreferences
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefNickname, state.nickname);
    await prefs.setBool(prefFirstLaunch, state.isFirstLaunch);
    await prefs.setString(prefCameraResolution, state.cameraResolution);
    await prefs.setInt(prefFrameRate, state.frameRate);
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

  /// 更新昵称
  Future<void> updateNickname(String nickname) async {
    state = state.copyWith(nickname: nickname);
    await _saveToPrefs();
  }

  /// 保存本地 ID
  Future<void> saveLocalId(String localId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefLocalId, localId);
    state = state.copyWith();
  }

  /// 标记首次启动完成
  Future<void> completeFirstLaunch() async {
    state = state.copyWith(isFirstLaunch: false);
    await _saveToPrefs();
  }

  /// 更新画质偏好
  Future<void> updateQualityPreference(QualityPreference pref) async {
    state = state.copyWith(qualityPreference: pref);
    await _saveToPrefs();
  }

  /// 保存所有设置（从设置面板批量更新）
  Future<void> saveAllSettings(AppSettings newSettings) async {
    state = newSettings;
    await _saveToPrefs();
  }

  /// 替换全部设置（不从本地覆盖，用于从 SharedPreferences 加载后同步）
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
