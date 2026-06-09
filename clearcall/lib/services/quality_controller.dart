import 'dart:async';

import 'package:logging/logging.dart';

import '../models/quality_presets.dart';
import 'webrtc_service.dart';

/// 自适应画质控制器
///
/// 根据实时网络统计自动升降画质预设，保证通话流畅度。
///
/// 架构：
/// ```
/// 每 2 秒收到 WebRTCStats → evaluate() → 判断是否需要调整 → applyPreset()
/// ```
///
/// 决策规则（带迟滞）：
/// - 降级更敏感（5 秒确认），升级更保守（8 秒确认）
/// - 每次调整后冷却 10 秒
/// - 连续 3 次降级后锁定省流模式 60 秒
class QualityController {
  final Logger _log = Logger('QualityController');

  /// WebRTC 服务引用（用于应用码率变更）
  final WebRTCService _webrtc;

  /// 当前画质预设
  QualityPreset _currentPreset;

  /// 目标预设（待确认的变更）
  QualityPreset? _pendingPreset;

  /// 目标预设的稳定采样计数
  int _stableSamples = 0;

  /// 连续降级次数
  int _consecutiveDowngrades = 0;

  /// 上次调整时间
  DateTime? _lastChangeTime;

  /// 降级锁定到期时间
  DateTime? _downgradeLockUntil;

  /// 是否启用自适应
  bool isEnabled = true;

  /// 预设变化回调（通知 UI）
  void Function(QualityPreset oldPreset, QualityPreset newPreset)? onPresetChanged;

  QualityController({
    required WebRTCService webrtc,
    QualityPreset initialPreset = QualityPreset.standard,
  })  : _webrtc = webrtc,
        _currentPreset = initialPreset;

  /// 当前预设
  QualityPreset get currentPreset => _currentPreset;

  /// 每收到一次 stats 就调用一次（每 2 秒由 CallManager 驱动）
  void evaluate(WebRTCStats stats) {
    if (!isEnabled) return;

    // ── 降级锁定检查 ──
    if (_downgradeLockUntil != null) {
      if (DateTime.now().isBefore(_downgradeLockUntil!)) {
        return; // 锁定中，不调整
      }
      _downgradeLockUntil = null;
      _consecutiveDowngrades = 0;
      _log.info('降级锁定已解除');
    }

    // ── 冷却期检查 ──
    if (_lastChangeTime != null) {
      final cooldown = DateTime.now().difference(_lastChangeTime!);
      if (cooldown.inSeconds < 10) return; // 10 秒冷却
    }

    // ── 决策：需要升/降/不变？ ──
    final desired = _decideAction(stats);

    if (desired == null) {
      // 不需要变更 → 重置稳定计数
      _resetPending();
      return;
    }

    // 和当前预设相同 → 不调整
    if (desired == _currentPreset) {
      _resetPending();
      return;
    }

    // ── 稳定期确认 ──
    final isDowngrade = _isDowngrade(desired);
    final requiredSamples = isDowngrade ? 3 : 4; // 降 3×2=6s, 升 4×2=8s

    if (_pendingPreset == desired) {
      _stableSamples++;
    } else {
      _pendingPreset = desired;
      _stableSamples = 1;
    }

    if (_stableSamples >= requiredSamples) {
      _executeChange(desired, isDowngrade);
    }
  }

  /// 决定应该升/降/不变
  QualityPreset? _decideAction(WebRTCStats stats) {
    final rtt = stats.rtt;
    final loss = stats.packetLoss;

    // ── 紧急降级（严重弱网 → 立即降至省流）──
    if (rtt > 400 || loss > 0.08) {
      if (_currentPreset != QualityPreset.economy) {
        return QualityPreset.economy;
      }
      return null; // 已是最低档
    }

    // ── 降级判定 ──
    if (rtt > 300 || loss > 0.05) {
      return _downgrade();
    }
    if (rtt > 200 || loss > 0.03) {
      return _downgrade();
    }
    // 带宽不足 → 降级
    if (stats.availableBandwidth > 0) {
      final spec = presetSpecs[_currentPreset];
      if (spec != null && stats.availableBandwidth < spec.videoMaxBitrate * 0.8) {
        return _downgrade();
      }
    }

    // ── 升级判定（需要网络完全恢复）──
    if (rtt < 80 && loss < 0.005) {
      // 带宽充足才升级
      if (stats.availableBandwidth > 0) {
        final nextPreset = _upgradeTarget();
        if (nextPreset != null) {
          final nextSpec = presetSpecs[nextPreset];
          if (nextSpec != null &&
              stats.availableBandwidth > nextSpec.videoMaxBitrate * 1.5) {
            return nextPreset;
          }
        }
      } else {
        // 无法获取带宽信息，仅凭 RTT + 丢包判断
        return _upgradeTarget();
      }
    }

    return null; // 维持当前
  }

  /// 降级一档
  QualityPreset? _downgrade() {
    switch (_currentPreset) {
      case QualityPreset.ultra:
        return QualityPreset.hd;
      case QualityPreset.hd:
        return QualityPreset.standard;
      case QualityPreset.standard:
        return QualityPreset.economy;
      case QualityPreset.economy:
      case QualityPreset.custom:
        return null; // 已是最低，或自定义不自动降
    }
  }

  /// 升级目标（比当前高一档）
  QualityPreset? _upgradeTarget() {
    switch (_currentPreset) {
      case QualityPreset.economy:
        return QualityPreset.standard;
      case QualityPreset.standard:
        return QualityPreset.hd;
      case QualityPreset.hd:
        return QualityPreset.ultra;
      case QualityPreset.ultra:
      case QualityPreset.custom:
        return null; // 已是最高，或自定义不自动升
    }
  }

  /// 判断 desired 相对 current 是否为降级
  bool _isDowngrade(QualityPreset desired) {
    return desired.index < _currentPreset.index;
  }

  /// 执行预设切换
  Future<void> _executeChange(QualityPreset newPreset, bool isDowngrade) async {
    final oldPreset = _currentPreset;

    _log.info('自适应画质调整: ${oldPreset.label} → ${newPreset.label} '
        '(${isDowngrade ? "降级" : "升级"}, '
        '连续降级: $_consecutiveDowngrades 次)');

    // 应用新预设（await 确保码率设置完成后再更新状态）
    await applyPreset(newPreset);

    // 追踪降级次数
    if (isDowngrade) {
      _consecutiveDowngrades++;
      if (_consecutiveDowngrades >= 3) {
        _downgradeLockUntil =
            DateTime.now().add(const Duration(seconds: 60));
        _log.warning('连续 3 次降级，锁定省流模式 60 秒');
      }
    } else {
      _consecutiveDowngrades = 0;
    }

    _lastChangeTime = DateTime.now();
    _resetPending();
  }

  /// 应用预设（码率即时生效）
  Future<void> applyPreset(QualityPreset preset) async {
    if (preset == QualityPreset.custom) return; // 自定义不自动覆盖

    final spec = presetSpecs[preset];
    if (spec == null) return;

    final oldPreset = _currentPreset;
    _currentPreset = preset;

    // 动态调整码率（即时生效，无需重启媒体流）
    try {
      await _webrtc.setVideoBitrate(spec.videoMaxBitrate);
      await _webrtc.setAudioBitrate(spec.audioBitrate);
      _log.info('画质预设已应用: ${preset.label} '
          '(视频=${spec.videoBitrateLabel}, 音频=${spec.audioBitrateLabel})');
    } catch (e) {
      _log.warning('应用预设码率失败: $e');
    }

    // 通知 UI
    onPresetChanged?.call(oldPreset, preset);
  }

  /// 手动强制切换预设（跳过自适应规则）
  Future<void> forcePreset(QualityPreset preset) async {
    if (preset == _currentPreset) return;
    _resetPending();
    _consecutiveDowngrades = 0;
    _downgradeLockUntil = null;
    _lastChangeTime = null;
    await applyPreset(preset);
  }

  /// 重置待确认状态
  void _resetPending() {
    _pendingPreset = null;
    _stableSamples = 0;
  }

  /// 重置所有状态（挂断时调用）
  void reset() {
    _resetPending();
    _consecutiveDowngrades = 0;
    _lastChangeTime = null;
    _downgradeLockUntil = null;
  }
}
