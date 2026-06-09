import 'package:flutter/material.dart';

/// ClearCall 全局常量
///
/// 包含色彩系统、尺寸规范、排版样式等所有设计 token。
/// 所有 UI 代码必须引用此文件中的常量，不允许硬编码颜色值。

/// ─── 色彩系统 ─────────────────────────────────────────

/// 主背景色（iOS 系统背景灰白）
const Color colorBackground = Color(0xFFF2F2F7);

/// 磨砂卡片背景（白色半透明）
const Color colorGlassBackground = Color.fromARGB(204, 255, 255, 255); // rgba(255,255,255,0.8)

/// 磨砂卡片边框
const Color colorGlassBorder = Color.fromARGB(77, 255, 255, 255); // rgba(255,255,255,0.3)

/// 主强调色（蓝色 — 接通、确认、链接）
const Color colorAccent = Color(0xFF007AFF);

/// 危险色（红色 — 挂断、删除、拒绝）
const Color colorDanger = Color(0xFFFF3B30);

/// 成功色（绿色 — 在线状态、网络优秀）
const Color colorSuccess = Color(0xFF34C759);

/// 警告色（橙色 — 通话中、网络一般）
const Color colorWarning = Color(0xFFFF9500);

/// 中性色（灰色 — 离线状态、占位文字）
const Color colorNeutral = Color(0xFF8E8E93);

/// 文字主色（深灰 — 标题、正文）
const Color colorTextPrimary = Color(0xFF1C1C1E);

/// 文字次级（灰色 — 说明文字、时间戳）
const Color colorTextSecondary = Color(0xFF8E8E93);

/// 分割线颜色
const Color colorDivider = Color(0xFFE5E5EA);

/// 纯黑（视频静画背景）
const Color colorBlack = Color(0xFF000000);

/// 纯白（前置补光）
const Color colorWhite = Color(0xFFFFFFFF);

/// ColorAvatar 预置 12 色调色板
const List<Color> avatarColorPalette = [
  Color(0xFFE53935), // 红
  Color(0xFFD81B60), // 粉
  Color(0xFF8E24AA), // 紫
  Color(0xFF5E35B1), // 深紫
  Color(0xFF3949AB), // 靛蓝
  Color(0xFF1E88E5), // 蓝
  Color(0xFF039BE5), // 浅蓝
  Color(0xFF00ACC1), // 青
  Color(0xFF00897B), // 深绿
  Color(0xFF43A047), // 绿
  Color(0xFFF4511E), // 深橙
  Color(0xFF6D4C41), // 棕
];

/// ─── 尺寸规范 ─────────────────────────────────────────

/// 圆角：磨砂卡片
const double radiusCard = 16.0;

/// 圆角：胶囊按钮（全圆角）
const double radiusPill = 50.0;

/// 圆角：列表项
const double radiusListItem = 12.0;

/// 圆角：头像（列表用）
const double radiusAvatarList = 24.0; // 48dp 直径

/// 圆角：头像（详情用）
const double radiusAvatarDetail = 32.0; // 64dp 直径

/// 圆角：视频静画头像
const double radiusAvatarStill = 16.0; // 80×80dp 圆角矩形

/// 水平内边距
const double paddingHorizontal = 16.0;

/// 元素间距（标准）
const double spacingStandard = 16.0;

/// 元素间距（紧凑）
const double spacingCompact = 8.0;

/// 按钮高度
const double buttonHeight = 56.0;

/// 列表项高度
const double listItemHeight = 64.0;

/// 状态指示点直径
const double indicatorDiameter = 12.0;

/// 网络质量指示点直径（通话中）
const double networkIndicatorDiameter = 8.0;

/// 磨砂模糊强度
const double blurStrength = 20.0;

/// ─── 排版样式 ─────────────────────────────────────────

/// 大标题（34sp Bold）
const TextStyle styleLargeTitle = TextStyle(
  fontSize: 34.0,
  fontWeight: FontWeight.w700,
  color: colorTextPrimary,
  letterSpacing: -0.5,
);

/// 标题1（28sp Bold — 房间号）
const TextStyle styleTitle1 = TextStyle(
  fontSize: 28.0,
  fontWeight: FontWeight.w700,
  color: colorTextPrimary,
);

/// 标题2（22sp SemiBold — 区块标题）
const TextStyle styleTitle2 = TextStyle(
  fontSize: 22.0,
  fontWeight: FontWeight.w600,
  color: colorTextPrimary,
);

/// 标题3（20sp SemiBold — 卡片标题）
const TextStyle styleTitle3 = TextStyle(
  fontSize: 20.0,
  fontWeight: FontWeight.w600,
  color: colorTextPrimary,
);

/// 正文（17sp Regular）
const TextStyle styleBody = TextStyle(
  fontSize: 17.0,
  fontWeight: FontWeight.w400,
  color: colorTextPrimary,
);

/// 说明文字（15sp Regular）
const TextStyle styleCaption = TextStyle(
  fontSize: 15.0,
  fontWeight: FontWeight.w400,
  color: colorTextSecondary,
);

/// 小字（13sp Regular — 时间戳、标签）
const TextStyle styleSmall = TextStyle(
  fontSize: 13.0,
  fontWeight: FontWeight.w400,
  color: colorTextSecondary,
);

/// 极小字（11sp Regular — 角标）
const TextStyle styleTiny = TextStyle(
  fontSize: 11.0,
  fontWeight: FontWeight.w400,
  color: colorTextSecondary,
);

/// ─── 通话相关常量 ─────────────────────────────────────

/// 房间号长度
const int roomCodeLength = 6;

/// 最大通话人数
const int maxParticipants = 3;

/// 房间超时时间（5 分钟无响应自动关闭）
const Duration roomTimeout = Duration(minutes: 5);

/// 呼叫超时时间（60 秒无人接听）
const Duration callTimeout = Duration(seconds: 60);

/// 名片显示时长（3 秒后自动消失）
const Duration nameCardDuration = Duration(seconds: 3);

/// 网络质量面板自动收起时长
const Duration networkPanelDuration = Duration(seconds: 3);

/// ─── SharedPreferences Key ───────────────────────────

const String prefLocalId = 'local_id';
const String prefNickname = 'nickname';
const String prefFirstLaunch = 'first_launch';
const String prefCameraResolution = 'camera_resolution';
const String prefFrameRate = 'frame_rate';
const String prefQualityPreference = 'quality_preference';
const String prefH265Enabled = 'h265_enabled';
const String prefAudioCodec = 'audio_codec';
const String prefAudioBitrate = 'audio_bitrate';
const String prefAEC = 'aec_enabled';
const String prefANS = 'ans_enabled';
const String prefAGC = 'agc_enabled';
const String prefMobileWarningShown = 'mobile_warning_shown';
const String prefDebugPanel = 'debug_panel_enabled';

/// ─── 信令服务配置 ─────────────────────────────────────

/// 信令方案：扫码 SDP 交换（无需服务器）
