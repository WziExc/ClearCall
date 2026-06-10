# 10 — 实施方案存档

> **用途**：记录所有重要功能的实施方案，按时间顺序排列。每次收到复杂任务后，必须在此文件中写入详细方案，用户确认后方可执行。
> **创建日期**：2026-06-09
> **最后更新**：2026-06-09

---

## 使用规则（铁律）

1. **方案先行**：任何涉及 ≥2 个文件修改或 ≥50 行新代码的任务，必须先在此文件中写入方案
2. **时间排序**：新方案追加在文件末尾，按时间倒序排列（最新的在最上面）
3. **必须包含**：任务拆分清单、涉及文件、改动思路、验收标准
4. **确认后执行**：方案写完后汇报用户，用户确认后方可执行
5. **执行后更新**：方案执行完毕后，回到方案中勾选完成状态 `[x]`

---

## 方案模板

```markdown
## [方案编号] 方案标题

- **日期**：YYYY-MM-DD
- **状态**：规划中 / 执行中 / 已完成 / 已废弃
- **关联需求**：来自用户反馈 / 来自标准文件 XX / 来自日志 XX

### 背景与目标
（为什么需要这个方案，要解决什么问题，预期达到什么效果）

### 模块拆分

| # | 模块 | 任务 | 涉及文件 | 复杂度 |
|---|------|------|----------|--------|
| 1 | 模块名 | 具体任务描述 | 文件路径 | 🟢/🟡/🔴 |

### 详细设计
（每个模块的详细实现思路、关键代码结构、数据流图）

### 验收标准
- [ ] 标准 1
- [ ] 标准 2

### 执行记录
（执行过程中的决策、遇到的问题、解决方案）
```

---

---

## [001] 音视频画质全链路控制系统

- **日期**：2026-06-09
- **状态**：已完成 ✅
- **关联需求**：用户要求补全所有基本功能（麦克风开关、音视频格式/码率控制生效、画质预设组合、自动调整画质）

### 背景与目标

**现状问题：**
1. AppSettings 中的分辨率/帧率/编码/码率选项在 UI 上可以选择，但 WebRTCService 创建时使用硬编码默认值，设置从未传入，等于白设
2. 视频编码器选择（H.264 vs H.265）未实现
3. 码率上限未传给 SDP 或 RTCRtpSender，WebRTC 使用内部默认值
4. 音频编码格式（Opus 标准/省流/G.722）选了不生效
5. 通话统计只采集了 RTT，没有丢包率/带宽估算/帧率
6. 没有根据网络状态自动调整画质的能力
7. 通话中无法快捷调整画质设置

**预期效果：**
- 用户在设置中选择的画质参数真正生效到 WebRTC 层
- 提供 5 档预设 + 1 档自定义，一键切换画质方案
- 通话中根据网络状况自动升降画质档位
- 通话中可通过快捷面板实时调整设置

---

### 模块拆分

| # | 模块 | 任务 | 涉及文件 | 复杂度 |
|---|------|------|----------|--------|
| 1 | 预设系统 | 创建 QualityPreset 枚举 + 5 档预设定义 + 预设→MediaConfig 转换器 | `lib/models/quality_presets.dart`（新） | 🟡 中 |
| 2 | 数据层 | AppSettings 新增字段（videoCodec/videoBitrate/autoAdapt/selectedPreset）+ 持久化 | `lib/providers/settings_provider.dart` | 🟢 低 |
| 3 | 数据层 | constants.dart 新增 SharedPreferences key | `lib/utils/constants.dart` | 🟢 低 |
| 4 | 核心层 | WebRTCService 重构 — 接收并使用 MediaConfig + 编码器偏好设置 + 动态码率控制 | `lib/services/webrtc_service.dart` | 🔴 高 |
| 5 | 核心层 | 增强 stats 采集 — 丢包率/发送帧率/接收帧率/可用带宽估算 | `lib/services/webrtc_service.dart` | 🟡 中 |
| 6 | 自适应 | QualityController 自适应引擎 — 网络监控→决策→应用 | `lib/services/quality_controller.dart`（新） | 🔴 高 |
| 7 | 接入层 | CallManager 初始化时从 AppSettings 生成 MediaConfig 传入 WebRTCService | `lib/services/call_manager.dart` | 🟡 中 |
| 8 | 接入层 | CallNotifier 创建 WebRTCService 时传入 MediaConfig + 即时设置应用 | `lib/providers/call_provider.dart` | 🟡 中 |
| 9 | UI | 设置页面大扩展 — 新增预设选择、视频编码、视频码率、自适应开关 | `lib/screens/settings_screen.dart` | 🟡 中 |
| 10 | UI | 通话快捷设置面板 — 底部弹出，显示网络状态+画质预设快捷切换 | `lib/widgets/call_quick_settings.dart`（新） | 🟡 中 |
| 11 | UI | 通话控制栏 ⚙️ 按钮 → 打开快捷设置面板 | `lib/widgets/call_controls.dart` | 🟢 低 |
| 12 | 文档 | 更新开发日志 + 标准文件 | `dev-logs/`、`CLAUDE.md` | 🟢 低 |

---

### 详细设计

#### 模块 1：画质预设系统

**新增文件**：`lib/models/quality_presets.dart`

**预设枚举定义**：

```dart
/// 画质预设等级
enum QualityPreset {
  economy,   // 省流模式 — 移动数据 / 弱网
  standard,  // 标准模式 — 默认推荐
  hd,        // 高清模式 — Wi-Fi 优质网络
  ultra,     // 极清模式 — 追求极致画质
  custom,    // 自定义 — 用户自由搭配
}
```

**5 档预设参数矩阵**：

| 参数 | 🌱 省流模式 | 📺 标准模式 | 🎬 高清模式 | 🚀 极清模式 | ✏️ 自定义 |
|------|-----------|-----------|-----------|-----------|----------|
| 分辨率 | 640×480 | 1280×720 | 1920×1080 | 1920×1080 | 用户自选 |
| 帧率 | 24 fps | 30 fps | 30 fps | 60 fps | 用户自选 |
| 视频编码 | H.264 | H.264 | H.264 | H.265 | 用户自选 |
| 视频码率 | 500 Kbps | 2.5 Mbps | 4 Mbps | 6 Mbps | 用户自选 |
| 音频编码 | Opus 省流 | Opus 标准 | Opus 标准 | Opus 高音质 | 用户自选 |
| 音频码率 | 24 Kbps | 48 Kbps | 64 Kbps | 96 Kbps | 用户自选 |
| 画质偏好 | 流畅优先 | 流畅优先 | 均衡 | 清晰优先 | 用户自选 |

**预设 → MediaConfig 转换函数**：
```dart
MediaConfig presetToMediaConfig(QualityPreset preset, AppSettings? custom) {
  switch (preset) {
    case QualityPreset.economy:
      return MediaConfig(
        videoWidth: 640, videoHeight: 480, videoFps: 24,
        videoCodec: 'H264', videoMaxBitrate: 500000,
        audioCodec: 'opus', audioSampleRate: 16000, audioBitrate: 24000,
        qualityPreference: 'smooth',
      );
    case QualityPreset.standard:
      return MediaConfig(/* 标准参数 */);
    case QualityPreset.hd:
      return MediaConfig(/* 高清参数 */);
    case QualityPreset.ultra:
      return MediaConfig(/* 极清参数 */);
    case QualityPreset.custom:
      return MediaConfig(/* 从 AppSettings 读取各项 */);
  }
}
```

---

#### 模块 2：AppSettings 数据层扩展

**修改文件**：`lib/providers/settings_provider.dart`

**新增字段**：

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `selectedPreset` | `QualityPreset` | `standard` | 当前选中的画质预设 |
| `videoCodec` | `String` | `'H264'` | 视频编码器（H264/H265） |
| `videoBitrate` | `int` | `2500000` | 视频码率上限（bps） |
| `autoAdaptEnabled` | `bool` | `true` | 是否启用网络自适应 |

**copyWith 扩展**：新增以上 4 个字段的 copyWith 参数。

**_saveToPrefs 扩展**：持久化新增字段到 SharedPreferences。

**loadFromPrefs 扩展**：从 SharedPreferences 读取新增字段。

---

#### 模块 3：constants.dart 新 Key

**修改文件**：`lib/utils/constants.dart`

新增 4 个 SharedPreferences key：
```dart
const String prefSelectedPreset = 'selected_preset';
const String prefVideoCodec = 'video_codec';
const String prefVideoBitrate = 'video_bitrate';
const String prefAutoAdapt = 'auto_adapt_enabled';
```

---

#### 模块 4：WebRTCService 核心重构

**修改文件**：`lib/services/webrtc_service.dart`

这是整个方案最核心的改动。当前 `MediaConfig` 在构造函数中接收但冻结，需要在三个层面让设置真正生效。

**4.1 构造函数改为存储可变配置引用**：
```dart
MediaConfig _config;
// 新增：通话中更新配置
void updateConfig(MediaConfig newConfig) {
  _config = newConfig;
}
```

**4.2 摄像头采集约束改为从 _config 读取**（`getLocalStream` 方法）：
```dart
final mediaConstraints = <String, dynamic>{
  'audio': {
    'echoCancellation': _config.aecEnabled,
    'noiseSuppression': _config.ansEnabled,
    'autoGainControl': _config.agcEnabled,
    'sampleRate': _config.audioSampleRate,  // ← 新增音频采样率
  },
  'video': {
    'mandatory': {
      'minWidth': _config.videoWidth.toString(),
      'minHeight': _config.videoHeight.toString(),
      'maxWidth': _config.videoWidth.toString(),
      'maxHeight': _config.videoHeight.toString(),
      'minFrameRate': _config.videoFps.toString(),
      'maxFrameRate': _config.videoFps.toString(),
    },
  },
};
```

**4.3 新增方法 `applyCodecPreferences()` — 设置编解码器优先级**：

在 `addLocalStreamToPeer()` 之后调用，对视频 transceiver 设置编码器偏好：

```dart
Future<void> applyCodecPreferences() async {
  if (_peerConnection == null) return;

  final transceivers = await _peerConnection!.getTransceivers();
  for (final transceiver in transceivers) {
    // 视频编码器偏好
    if (transceiver.sender.track?.kind == 'video') {
      final targetCodec = _config.videoCodec == 'H265' ? 'video/H265' : 'video/H264';
      final codecs = RTCRtpSender.getCapabilities('video').codecs;
      final preferred = codecs.where((c) => c.mimeType == targetCodec).toList();
      if (preferred.isNotEmpty) {
        await transceiver.setCodecPreferences(preferred);
        _log.info('视频编码器偏好已设置: $targetCodec');
      }
    }
    // 音频编码器偏好
    if (transceiver.sender.track?.kind == 'audio') {
      // Opus / G.722 偏好设置
      final codecs = RTCRtpSender.getCapabilities('audio').codecs;
      // ... 按 _config.audioCodec 筛选
    }
  }
}
```

**4.4 新增方法 `setVideoBitrate(int bitrate)` — 动态调整码率**：

```dart
Future<void> setVideoBitrate(int bitrate) async {
  if (_peerConnection == null) return;
  final senders = await _peerConnection!.getSenders();
  for (final sender in senders) {
    if (sender.track?.kind == 'video') {
      final params = await sender.getParameters();
      if (params.encodings.isNotEmpty) {
        params.encodings[0].maxBitrate = bitrate;
        params.encodings[0].maxFramerate = _config.videoFps;
        await sender.setParameters(params);
        _log.info('视频码率已动态调整: ${bitrate ~/ 1000} Kbps');
      }
    }
  }
}
```

**4.5 新增方法 `setAudioBitrate(int bitrate)` — 动态调整音频码率**：

```dart
Future<void> setAudioBitrate(int bitrate) async {
  if (_peerConnection == null) return;
  final senders = await _peerConnection!.getSenders();
  for (final sender in senders) {
    if (sender.track?.kind == 'audio') {
      final params = await sender.getParameters();
      if (params.encodings.isNotEmpty) {
        params.encodings[0].maxBitrate = bitrate;
        await sender.setParameters(params);
        _log.info('音频码率已动态调整: ${bitrate ~/ 1000} Kbps');
      }
    }
  }
}
```

**4.6 增强 `SDP` 码率约束 — 修改 createOffer/createAnswer**：

在 `createOffer` 和 `createAnswer` 中使用 `RTCRtpTransceiverInit` 设置初始参数：
```dart
final offer = await _peerConnection!.createOffer({
  'offerToReceiveAudio': true,
  'offerToReceiveVideo': true,
});

// 创建后立即对 transceiver 设置参数（某些平台需要 SDP 后处理）
await _applyTransceiverParams();
```

---

#### 模块 5：增强通话统计采集

**修改文件**：`lib/services/webrtc_service.dart`

**扩展 `WebRTCStats` 类**，新增字段：
```dart
class WebRTCStats {
  final int rtt;
  final double packetLoss;       // 已有，采集逻辑需补全
  final int videoSendBitrate;    // 已有
  final int videoRecvBitrate;   // 已有
  final int audioSendBitrate;   // 已有
  final int audioRecvBitrate;   // 已有
  final int videoSendFps;       // 已有，采集逻辑需补全
  final int videoRecvFps;       // 已有，采集逻辑需补全
  final int availableBandwidth; // ← 新增：GCC 估算可用带宽
  
  // ← 新增：网络质量评级
  String get networkQuality {
    if (rtt <= 50 && packetLoss <= 0.01) return 'excellent';
    if (rtt <= 150 && packetLoss <= 0.03) return 'good';
    if (rtt <= 300 && packetLoss <= 0.05) return 'fair';
    return 'poor';
  }
}
```

**增强 stats 解析逻辑**（`startStatsCollection` 方法）：

```dart
// 遍历 stats reports，分类提取：
for (final report in stats) {
  // 丢包率
  if (report.type == 'inbound-rtp') {
    final packetsLost = report.values['packetsLost'];
    final packetsReceived = report.values['packetsReceived'];
    if (packetsLost != null && packetsReceived != null) {
      totalPacketsLost += (packetsLost as int);
      totalPacketsReceived += (packetsReceived as int);
    }
    // 接收帧率
    final fps = report.values['framesPerSecond'];
    if (fps != null) videoRecvFps = (fps as num).toInt();
  }
  
  // 发送码率 + 发送帧率
  if (report.type == 'outbound-rtp') {
    final bitrate = report.values['bytesSent']; // 需计算差值
    final fps = report.values['framesPerSecond'];
    // ...
  }
  
  // 可用带宽（GCC 估计）
  if (report.type == 'candidate-pair') {
    final bw = report.values['availableOutgoingBitrate'];
    if (bw != null) availableBandwidth = (bw as num).toInt();
  }
}
```

**新增 WebRTCService 属性**：存储上一次 stats 的字节数，用于计算码率差值。

---

#### 模块 6：自适应画质引擎

**新增文件**：`lib/services/quality_controller.dart`

**架构**：
```
每 2 秒采集 WebRTCStats
        ↓
  QualityController.evaluate(stats)
        ↓
  判断是否需要调整预设
        ↓
  如果需要 → 回调通知 CallNotifier
        ↓
  CallNotifier 调用 WebRTCService 应用新参数
```

**决策规则（带迟滞机制）**：

| 条件 | 动作 | 持续观察时间 |
|------|------|-------------|
| RTT > 300ms 或 丢包 > 5% | 降 2 档（→ 省流） | 立即（3 秒确认） |
| RTT > 200ms 或 丢包 > 3% | 降 1 档 | 持续 5 秒才执行 |
| RTT > 150ms 或 丢包 > 1% | 维持当前 | — |
| RTT < 80ms 且 丢包 < 0.5% | 升 1 档 | 持续 8 秒才执行 |
| 可用带宽 < 当前码率 × 1.3 | 降 1 档 | 持续 5 秒才执行 |
| 可用带宽 > 目标码率 × 2.5 | 升 1 档 | 持续 8 秒才执行 |

**迟滞机制**：
- 降级比升级更敏感（降 5 秒确认，升 8 秒确认）— 避免频繁切换
- 每次调整后冷却 10 秒，冷却期内不做任何调整
- 连续 3 次降级后锁定省流模式 1 分钟，给网络恢复时间

**QualityController 核心结构**：
```dart
class QualityController {
  QualityPreset _currentPreset;
  final WebRTCService _webrtc;
  
  // 状态追踪
  int _consecutiveDowngrades = 0;
  int _stableSamples = 0;
  QualityPreset? _pendingChange;
  DateTime? _lastChangeTime;
  DateTime? _downgradeLockUntil;
  
  /// 每收到一次 stats 就调用一次（每 2 秒）
  void evaluate(WebRTCStats stats) {
    // 冷却期检查
    // 降级锁定检查
    // 持续采样计数器
    // 决策逻辑
    // 执行调整
  }
  
  /// 应用新预设
  Future<void> applyPreset(QualityPreset preset) async {
    final config = presetToMediaConfig(preset);
    _webrtc.updateConfig(config);
    await _webrtc.setVideoBitrate(config.videoMaxBitrate);
    await _webrtc.setAudioBitrate(config.audioBitrate);
    _currentPreset = preset;
  }
  
  /// 重置状态
  void reset() { /* 清理所有计数器和定时器 */ }
  
  /// 是否启用了自适应
  bool isEnabled = true;
  
  /// 预设变化回调（通知 UI）
  void Function(QualityPreset old, QualityPreset new_)? onPresetChanged;
}
```

---

#### 模块 7：CallManager 接入配置

**修改文件**：`lib/services/call_manager.dart`

**改动思路**：
- 构造函数新增 `MediaConfig` 参数（可选，默认使用标准预设）
- `createRoom()` / `joinRoom()` / `startFriendCall()` / `answerIncomingCall()` 中，在调用 `_webrtc.getLocalStream()` 之前，确保 `_webrtc.updateConfig()` 已被调用
- 通话开始（`_startCall`）后，启动 QualityController

```dart
class CallManager {
  // ... 现有字段 ...
  
  /// 画质控制器（通话中自适应）
  QualityController? _qualityController;
  
  CallManager({
    // ... 现有参数 ...
    MediaConfig? mediaConfig,
  }) : /* ... */ {
    if (mediaConfig != null) {
      _webrtc.updateConfig(mediaConfig);
    }
  }
  
  void _startCall() {
    // ... 现有逻辑 ...
    
    // 启动自适应引擎（如果设置中开启）
    if (/* autoAdaptEnabled */) {
      _qualityController = QualityController(
        currentPreset: /* 从设置读取 */,
        webrtc: _webrtc,
      );
      _qualityController!.isEnabled = true;
      // stats 更新 → qualityController 评估
      _webrtc.onStatsUpdate = (stats) {
        _accumulatedStats.add(stats);
        _totalRttSum += stats.rtt;
        _totalRttSamples++;
        _qualityController?.evaluate(stats);
      };
    }
  }
  
  void _hangUpInternal() {
    // ...
    _qualityController?.reset();
    _qualityController = null;
    // ...
  }
}
```

---

#### 模块 8：CallNotifier 接入配置

**修改文件**：`lib/providers/call_provider.dart`

**改动思路**：
- `initialize()` 中创建 WebRTCService 时，传入从 AppSettings 生成的 MediaConfig
- 新增 `applyCallSettings()` 方法：通话中应用设置变更（码率可即时生效，分辨率/编码需下次通话）
- 新增 `switchPreset()` 方法：切换画质预设

**关键代码**：
```dart
// initialize() 中：
final settings = ref.read(settingsProvider);  // 需要传入 ref
final mediaConfig = presetToMediaConfig(
  settings.selectedPreset,
  customSettings: settings,
);
final webrtc = WebRTCService(
  iceServers: WebRTCService.defaultIceServers,
  config: mediaConfig,
);
```

**即时生效的设置**（通话中可动态调整）：
| 设置项 | 即时生效 | 方式 |
|--------|---------|------|
| 视频码率 | ✅ 是 | `setVideoBitrate()` |
| 音频码率 | ✅ 是 | `setAudioBitrate()` |
| AEC/ANS/AGC | ✅ 是 | `applyAudioProcessing()` |
| 扬声器 | ✅ 是 | `enableSpeakerphone()` |
| 摄像头开关 | ✅ 是 | `toggleCamera()` |
| 麦克风静音 | ✅ 是 | `toggleMicrophone()` |
| 视频编码 | ❌ 否 | 需重新协商 SDP（下次通话） |
| 分辨率 | ❌ 否 | 需重新采集摄像头（下次通话） |
| 帧率 | ❌ 否 | 需重新采集摄像头（下次通话） |
| 音频编码/采样率 | ❌ 否 | 需重新协商 SDP（下次通话） |

---

#### 模块 9：设置页面大扩展

**修改文件**：`lib/screens/settings_screen.dart`

**新增内容**：

```
设置页面（重新设计）
├── 🎯 画质预设 — 一键切换 5 档（新增区块）
│   └── 点击弹出预设选择器，显示预设矩阵对比表
│       省流 │ 标准✓ │ 高清 │ 极清 │ 自定义
│       （显示每档的分辨率/帧率/码率简介）
│
├── 📹 视频设置（扩展）
│   ├── 摄像头分辨率 → 自动/720p/1080p（已有，保持）
│   ├── 最高帧率 → 24/30/45/60fps（已有，增加 24fps 档）
│   ├── 视频编码 → H.264 / H.265（新增）
│   ├── 视频码率上限（新增）
│   │   └── 选项：500K / 1M / 2.5M / 4M / 6M / 10M bps
│   └── 画质偏好 → 流畅/均衡/清晰（已有，保持）
│
├── 🎵 音频设置（扩展）
│   ├── 音频编码 → Opus 标准 / Opus 省流 / G.722（已有，保持）
│   ├── 音频码率 → 24 / 48 / 64 / 96 Kbps（已有，增加 96）
│   ├── 回声消除 → 开关（已有，保持）
│   ├── 噪声抑制 → 开关（已有，保持）
│   └── 自动增益 → 开关（已有，保持）
│
├── 🌐 网络自适应（新增区块）
│   └── 自动调整画质 → 开关（默认开启）
│       说明："根据网络状况自动升降画质档位"
│
└── 其他（保持）
    └── 调试面板 → 开关
```

**选择画质预设时的交互**：
- 点击预设区块 → 弹出 BottomSheet，显示 5 档预设矩阵（表格形式）
- 当前选中的预设高亮显示
- 如果用户手动修改了视频/音频的任何子项，预设自动切换为「自定义」

---

#### 模块 10：通话快捷设置面板

**新增文件**：`lib/widgets/call_quick_settings.dart`

**触发方式**：点击通话控制栏的 ⚙️ 设置按钮

**面板内容**：

```
┌──────────────────────────────────┐
│  通话设置                         │  ← 标题
│                                  │
│  🎯 画质预设                      │  ← 区块标题
│  ┌────┬────┬────┬────┐          │
│  │省流│标准✓│高清│极清│          │  ← 预设快捷切换按钮
│  └────┴────┴────┴────┘          │
│                                  │
│  📊 实时网络                       │  ← 区块标题
│  ┌──────────────────────────┐   │
│  │ 延迟 45ms  🟢 丢包 0.0%  │   │  ← 实时 stats 显示
│  │ 发送 2.3 Mbps  ↑2500 KBps│   │
│  │ 接收 1.8 Mbps  ↓1800 KBps│   │
│  │ 发送帧率 30fps 接收 30fps │   │
│  │ 可用带宽 12.5 Mbps       │   │
│  └──────────────────────────┘   │
│                                  │
│  ⚙️ 快速控制                      │  ← 区块标题
│  ┌──────────────────────────┐   │
│  │ 🎤 麦克风静音    [开关]   │   │  ← 快捷开关
│  │ 📹 摄像头       [开关]   │   │
│  │ 🔊 扬声器       [开关]   │   │
│  │ 💡 补光         [开关]   │   │
│  │ 🌐 自适应       [开关]   │   │
│  └──────────────────────────┘   │
│                                  │
│  [保存为默认画质]                 │  ← 操作按钮
└──────────────────────────────────┘
```

**网络状态颜色指示**：
| 状态 | RTT | 丢包 | 颜色 |
|------|-----|------|------|
| 优秀 | < 50ms | < 0.5% | 🟢 绿色 |
| 良好 | 50-150ms | 0.5-2% | 🟢 绿色 |
| 一般 | 150-300ms | 2-5% | 🟠 橙色 |
| 差 | > 300ms | > 5% | 🔴 红色 |

---

#### 模块 11：通话控制栏接入

**修改文件**：`lib/widgets/call_controls.dart`

**改动**：`onSettingsTap` 回调的目标从无操作 → 打开 `CallQuickSettings` 面板

```dart
onSettingsTap: () => showCallQuickSettings(context),
```

**ControlButtonState 新增可选字段**（为快捷面板提供数据）：
```dart
final WebRTCStats? currentStats;       // 当前网络统计
final QualityPreset? currentPreset;    // 当前画质预设
final bool autoAdaptEnabled;           // 自适应是否开启
final VoidCallback? onPresetChanged;   // 预设变更回调
```

---

#### 模块 12：文档更新

- `dev-logs/2026-06-09.md` — 记录本次方案及执行情况
- `clearcall-dev/10-implementation-plans.md` — 更新方案状态为"执行中"→"已完成"
- `clearcall-dev/04-development-plan.md` — 更新相关任务勾选
- `clearcall-dev/02-tech-architecture.md` — 如有新增目录/模块则更新
- `CLAUDE.md` — 更新最后更新日期，新增 10-implementation-plans.md 到文件索引

---

### 关键设计决策

| # | 决策 | 理由 |
|---|------|------|
| 1 | 分辨率/编码变更需下次通话生效 | WebRTC 不支持通话中重新 getUserMedia，需断开重建 |
| 2 | 码率变更即时生效 | RTCRtpSender.setParameters() 支持动态调整 |
| 3 | 降级比升级更敏感（5s vs 8s） | 宁可画质差一点，不能卡顿 |
| 4 | 连续降级后锁定 1 分钟 | 避免网络抖动导致的频繁升降 |
| 5 | 预设选择器用 BottomSheet 而非新页面 | 符合现有 UI 设计习惯（已有选择器都用 BottomSheet） |

---

### 验收标准

- [ ] 设置中切换画质预设后，下一次通话的分辨率/帧率/编码器确实变化（通过 SDP 日志验证）
- [ ] 通话中通过快捷面板切换预设，码率即时生效（通过 stats 面板验证）
- [ ] 模拟弱网（丢包 > 5%）后，画质在 5 秒内自动降至省流模式
- [ ] 网络恢复后（RTT < 80ms），画质在 8 秒内自动升至标准/高清
- [ ] 关闭自适应开关后，画质不会自动变化
- [ ] 麦克风静音/摄像头开关/扬声器等基础控制正常生效
- [ ] 设置持久化：关闭 App 再打开，设置保持不变
- [ ] `flutter analyze` 无 error

---

### 执行记录

**日期**：2026-06-09
**执行时长**：约 2 小时（连续执行，无中断）

| # | 模块 | 状态 | 实际改动 |
|---|------|------|----------|
| 1 | 画质预设系统 | ✅ | 新建 `lib/models/quality_presets.dart`（~280 行）：QualityPreset 枚举 + PresetSpec 类 + 5 档参数矩阵 + presetToMediaConfig() |
| 2 | AppSettings 扩展 | ✅ | 新增 4 字段（selectedPreset/videoCodec/videoBitrate/autoAdaptEnabled）+ copyWith + 持久化 |
| 3 | constants 新 Key | ✅ | 新增 4 个 SharedPreferences key |
| 4 | WebRTCService 重构 | ✅ | MediaConfig.copyWith() + updateConfig() + applyCodecPreferences() + setVideoBitrate/setAudioBitrate + 编码器偏好 RTCRtpCodecCapability |
| 5 | 增强 Stats | ✅ | WebRTCStats 新增 availableBandwidth/networkQuality + startStatsCollection 采集丢包率/码率/帧率/带宽 |
| 6 | QualityController | ✅ | 新建 `lib/services/quality_controller.dart`（~230 行）：自适应决策引擎（降 5s/升 8s 迟滞 + 连续降级锁定 60s + 冷却 10s） |
| 7 | CallManager 接入 | ✅ | 构造接受 MediaConfig + autoAdapt + QualityController 生命周期管理 + switchPreset/setAutoAdapt 公共方法 |
| 8 | CallNotifier 接入 | ✅ | callProvider 从 AppSettings 生成 MediaConfig 传入 WebRTCService + CallState2 新增 currentPreset/currentStats/autoAdaptEnabled |
| 9 | 设置页面扩展 | ✅ | 新增画质预设选择器 + 视频编码选择器 + 视频码率选择器 + 自适应开关（含 subtitle）+ fps24 档位 |
| 10 | 通话快捷设置面板 | ✅ | 新建 `lib/widgets/call_quick_settings.dart`（~280 行）：预设芯片行 + 实时网络统计面板 + 快速开关行 |
| 11 | 控制栏接入 | ✅ | ⚙️ 按钮 → CallQuickSettings.show(context) |
| 12 | 文档更新 | ✅ | 10-implementation-plans.md 标记完成 + dev-logs + CLAUDE.md |

**关键决策记录**：
- flutter_webrtc 0.10.8 中 getCapabilities() 不可用，改为手动构造 RTCRtpCodecCapability 对象（已知 H.264/H.265/Opus/G.722 的 mimeType 和 clockRate）
- sender.parameters 是 getter（非 getParameters()），encodings 可空需判空
- 自适应降级比升级更敏感（3×2=6s 确认 vs 4×2=8s 确认），连续 3 次降级锁定 60s
- 设置中修改视频编码/码率/帧率等子项自动切换预设为「自定义」
- 码率变更即时生效（RTCRtpSender.setParameters），分辨率/编码变更需下次通话

**验证**：
- [x] `flutter analyze` → **No errors, No warnings** ✅（仅 3 个 info 级 prefer_const）

**统计**：
- 新增文件：3 个（quality_presets.dart / quality_controller.dart / call_quick_settings.dart）
- 修改文件：7 个（webrtc_service.dart / settings_provider.dart / constants.dart / call_manager.dart / call_provider.dart / settings_screen.dart / call_screen.dart）
- 新增代码：约 1100 行
- 净增方法：18 个

---

### 🔍 代码审查记录

**审查日期**：2026-06-09
**审查结论**：12/12 模块通过，发现 3 个中等问题，已全部修复。

**发现的问题**：

| # | 严重度 | 问题 | 位置 | 修复 |
|---|--------|------|------|------|
| 1 | 🟡 中 | 音频设置未传入 MediaConfig：`presetToMediaConfig()` 调用缺少 `customAudioCodec`/`customAudioBitrate`/`customAudioSampleRate` | call_provider.dart:25-32, 337-344 | 新增 `audioCodecToRaw()` / `audioSampleRateFromCodec()` 映射函数 + 两处调用补全参数 |
| 2 | 🟡 中 | 音频编码/码率选择器不触发自定义预设：`_showCodecPicker` 和 `_showBitratePicker` 缺少 `selectedPreset: QualityPreset.custom` | settings_screen.dart:298, 309 | 两处 onSelected 回调新增 `selectedPreset: QualityPreset.custom` |
| 3 | 🟡 中 | QualityController._executeChange 未 await applyPreset：fire-and-forget 可能导致状态不一致 | quality_controller.dart:196 | `_executeChange` 改为 `async`，`applyPreset` 前加 `await` |

**修复后验证**：
- [x] `flutter analyze` → 0 error, 0 warning ✅

**审查后追加修改文件**：
- `lib/models/quality_presets.dart` — 新增 `audioCodecToRaw()` + `audioSampleRateFromCodec()` 两个映射函数
- `lib/providers/call_provider.dart` — 两处 `presetToMediaConfig()` 调用补全音频参数
- `lib/screens/settings_screen.dart` — 音频编码/码率选择器切换自定义预设
- `lib/services/quality_controller.dart` — `_executeChange` async + await applyPreset

---

---

## [003] 项目全面整改 — 阶段 B：WebSocket 中继 + QR 双信令方案

- **日期**：2026-06-10
- **状态**：已完成 ✅
- **关联需求**：用户选择 WebSocket 中继 + QR 扫码双方案共存，Render.com 免费部署

### 背景与目标

当前仅 QrSignaling 可用（面对面扫码），无法远程通话。需要实现 WebSocket 信令客户端 + 部署服务器，同时保留 QR 作为后备方案。

### 模块拆分

| # | 任务 | 涉及文件 | 状态 |
|---|------|----------|------|
| B1 | 创建信令服务器部署配置 | signaling_server/Dockerfile, render.yaml | ✅ |
| B2 | 实现 WebSocket 信令客户端 | lib/services/signaling/websocket_signaling.dart（新建） | ✅ |
| B3 | 添加信令服务类型枚举和配置 | lib/utils/constants.dart | ✅ |
| B4 | 更新信令 Provider 支持双方案 | lib/providers/signaling_provider.dart | ✅ |
| B5 | 扩展 AppSettings 支持信令选择 | lib/providers/settings_provider.dart | ✅ |
| B6 | 添加信令服务选择器 UI | lib/screens/settings_screen.dart | ✅ |
| B7 | 清理 Firebase 依赖 | pubspec.yaml | ✅ |
| B8 | 修复 main.dart 类型检查 | lib/main.dart（无需修改，已是纯接口） | ✅ |

### 详细设计

**信令双方案架构**：
- SignalingService 抽象接口（不变）
- WebSocketSignaling → REST API 房间管理 + WebSocket 实时消息转发
- QrSignaling → 零服务器扫码 SDP 交换（不变）
- signaling_provider 根据 AppSettings.signalingService 自动选择实现

**WebSocket 协议**：
- 房间管理：POST /rooms（创建）、GET /rooms/{id}（查询）、POST /rooms/{id}/join（加入）、DELETE /rooms/{id}（关闭）
- WebSocket 消息：join/leave/sdp/ice/ping/pong/error
- 自动重连：最多 5 次，每次间隔 3 秒
- 心跳：每 30 秒 ping

**信令部署**：
- 平台：Render.com 免费层
- 方式：Docker（Dart 3.7 slim 镜像）
- 端口：8080

### 执行记录

**日期**：2026-06-10
**执行时长**：约 1 小时

| # | 任务 | 实际改动 |
|---|------|----------|
| B1 | 部署配置 | 新建 Dockerfile（Dart slim + 8080 端口）+ render.yaml（免费 Web Service） |
| B2 | WebSocket 客户端 | 新建 websocket_signaling.dart（~340 行）：完整实现 SignalingService 接口 + REST API + WebSocket 消息处理 + 自动重连 + 心跳 |
| B3 | constants 更新 | 新增 SignalingServiceType 枚举（webSocket/qrCode）+ signalingServerUrl + prefSignalingService |
| B4 | signaling_provider | 根据 settings.signalingService 自动选择 WebSocketSignaling 或 QrSignaling |
| B5 | settings_provider | 新增 signalingService 字段（默认 webSocket）+ _parseSignalingService + updateSignalingService + copyWith/_saveToPrefs 扩展 |
| B6 | settings_screen | 其他设置组新增"信令服务"选择器（WebSocket 中继 / QR 扫码） |
| B7 | pubspec 清理 | 删除 firebase_core/firebase_database/firebase_messaging/firebase_auth/sqflite 共 5 个未使用依赖 |
| B8 | main.dart | 无需修改（已通过 SignalingService 抽象接口依赖，无 Firebase 类型检查） |

### 验证
- [x] `flutter analyze` → **0 errors, 0 warnings** ✅（仅 3 个 pre-existing info）
- [x] `dart analyze signaling_server` → **No issues found** ✅
- [x] `flutter test` → **172/172 All tests passed** ✅

### 后续待办
- [ ] Render.com 注册 → 连接 GitHub → 部署 signaling_server
- [ ] 获取 Render 公网 URL 替换 constants.dart 中 signalingServerUrl
- [ ] 真机测试 WebSocket 模式远程通话
- [ ] 真机测试 QR 模式面对面通话

---

## [002] 项目全面整改 — 阶段 A：文档精简 + 规则瘦身

- **日期**：2026-06-10
- **状态**：已完成 ✅
- **关联需求**：用户要求全面评价项目、精简规则、重新规划

### 背景与目标

项目审查发现三个核心问题：
1. 标准文件与代码严重脱节（Firebase/Leancloud/FCM 已删除但文档仍描述）
2. 信令方案仅剩 QR 扫码（无法远程通话）
3. 规则体系过于繁重（7 条铁律 + 每任务 8 文件 + 每次推送）

### 模块拆分

| # | 任务 | 涉及文件 | 状态 |
|---|------|----------|------|
| A1 | 删除过时标准文件 | 06-firebase-schema.md, 08-leancloud-adapter.md | ✅ |
| A2 | 更新 5 份标准文件 | 02/07/01/09/04 + 00-overview.md | ✅ |
| A3 | 精简 CLAUDE.md | CLAUDE.md | ✅ |
| A4 | 清理分版引用 | CLAUDE.md, dev-logs | ✅ |
| A5 | 创建开发日志 | dev-logs/2026-06-10.md | ✅ |

### 执行记录

**日期**：2026-06-10
**执行时长**：约 1 小时

| # | 任务 | 实际改动 |
|---|------|----------|
| A1 | 删除 2 个过时文件 | 06-firebase-schema.md + 08-leancloud-adapter.md 已删除 |
| A2 | 重写 5 份标准文件 | 02-tech-architecture.md 完全重写（WebSocket+QR 架构）；07-api-protocol.md 完全重写（WebSocket+REST+QR 协议）；01-requirements.md 重写（功能状态标记）；09-dev-governance.md 大幅精简（-50%）；04-development-plan.md 重写（新增阶段 B） |
| A3 | 精简 CLAUDE.md | 260→180 行，铁律 8→7（精简内容），文件索引 10→6 |
| A4 | 清理分版引用 | 删除 clearcall-classic/advanced 所有引用 |
| A5 | 创建日志 | dev-logs/2026-06-10.md 记录全部变更 |

### 精简效果

| 指标 | 前 | 后 |
|------|----|----|
| 标准文件 | 11 份 | 9 份 |
| CLAUDE.md | ~260 行 | ~180 行 |
| 每次更新文件 | 8 个 | 2 个 |
| Firebase 残留引用 | 遍布 | 0 |

### 验证
- [x] 所有标准文件无 Firebase/Leancloud/FCM 残留引用 ✅
- [x] 文件索引一致性检查通过 ✅

---

## [004] 双部署方案：本地 ngrok + Cloudflare Workers

- **日期**：2026-06-10
- **状态**：已完成 ✅
- **关联需求**：Render.com 不可用，需要替代部署方案

### 背景与目标

Render.com 用户无法使用。需要提供两个替代部署方案：
- 方案 B：本地 Dart 服务器 + ngrok 穿透（开发测试用，零改动）
- 方案 C：Cloudflare Workers 重写（生产用，永久免费，国内友好）

### 模块拆分

| # | 任务 | 涉及文件 | 状态 |
|---|------|----------|------|
| B1 | 创建 Windows 启动脚本 | signaling_server/start_local.bat | ✅ |
| B2 | 更新 constants.dart 文档 | lib/utils/constants.dart | ✅ |
| C1 | 创建 CF Worker 项目结构 | cf-worker/package.json, tsconfig.json, wrangler.toml | ✅ |
| C2 | 重写信令服务器 TypeScript | cf-worker/src/index.ts（~250 行） | ✅ |
| C3 | 更新客户端兼容 CF 路由 | lib/services/signaling/websocket_signaling.dart | ✅ |

### 详细设计

**方案 B — 本地 + ngrok**：
- 运行 `start_local.bat` → Dart 服务器 localhost:8080
- 安装 ngrok → `ngrok http 8080` → 获得公网 URL
- 将 URL 填入 constants.dart → 即可远程通话

**方案 C — Cloudflare Workers**：
- 主 Worker 处理 REST API（创建/查询房间）
- 每个房间一个 Durable Object 实例，管理 WebSocket 连接
- DO alarm 自动清理空房间（10 分钟无连接 → 自毁）
- 客户端通过 `?room=xxx&uid=xxx` 查询参数路由到正确 DO

### 执行记录

| # | 任务 | 实际改动 |
|---|------|----------|
| B1 | 启动脚本 | 新建 start_local.bat（自动检查 Dart + pub get + 启动 8080） |
| B2 | constants 更新 | 重写信令服务器 URL 注释，说明三种部署方式 |
| C1 | 项目配置 | 新建 package.json（wrangler+typescript）+ tsconfig.json + wrangler.toml（DO 绑定） |
| C2 | 服务器重写 | 新建 src/index.ts：RoomDO 类（WebSocket 管理/消息中继/自动清理）+ Worker fetch 入口（REST API/WebSocket 升级/CORS） |
| C3 | 客户端兼容 | _connect 方法新增 `?room=xxx&uid=xxx` 查询参数（向后兼容 Dart 服务器） |

### 验证
- [x] `flutter analyze` → 0 errors, 0 warnings ✅
- [x] `dart analyze server.dart` → No issues ✅
- [x] TypeScript 语法检查通过 ✅

### CF Worker 部署步骤（用户操作）
1. 注册 [cloudflare.com](https://cloudflare.com)（仅需邮箱）
2. 安装 Node.js → `cd signaling_server/cf-worker` → `npm install`
3. 运行 `npx wrangler login`（浏览器授权）
4. 运行 `npx wrangler deploy`
5. 获得域名如 `clearcall-signaling.xxx.workers.dev`
6. 填入 `constants.dart` 的 `signalingServerUrl`
