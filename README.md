# ClearCall — 极简视频通话

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-Android%208.0+-34A853?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/WebRTC-1.0-21C25E" alt="WebRTC">
  <img src="https://img.shields.io/badge/Firebase-Realtime%20DB-FFCA28?logo=firebase" alt="Firebase">
  <img src="https://img.shields.io/badge/Stage-3%20Complete-success" alt="Stage 3">
</p>

ClearCall 是一款极简风格的视频通话 App。不需要注册账号，不读取通讯录，通过 **6 位数字房间号** 或 **好友系统** 即可快速发起 2-3 人视频通话。

---

## ✨ 核心卖点

| 卖点 | 说明 |
|------|------|
| 🔢 **房间号即开即用** | 生成 6 位随机房间号，告诉好友即可通话 |
| 📱 **扫码加入** | 房间号一键生成二维码，好友扫码自动加入 |
| 👥 **好友系统** | 扫码/链接添加好友，在线状态实时显示，一键呼叫 |
| 👤 **匿名优先** | 无需手机号、无需邮箱，Firebase 匿名认证 |
| 🎨 **磨砂风格** | iOS 风格磨砂玻璃界面，简洁清爽 |
| 🌏 **国内优化** | Firebase 为主信令，新加坡节点低延迟；预留 Leancloud 适配 |

---

## 🚀 快速开始

### 环境要求

- **Flutter** 3.22+ / **Dart** 3.4+（开发环境：Flutter 3.44.1 / Dart 3.12.1）
- **Android** 8.0+（API 26+）/ Android Studio
- **Firebase** 项目（免费套餐即可）

### 构建运行

```bash
# 1. 克隆项目
git clone https://github.com/WziExc/ClearCall.git
cd ClearCall/clearcall

# 2. 安装依赖
flutter pub get

# 3. 配置 Firebase（详见 firebase/README.md）
#    将 google-services.json 放到 android/app/ 目录

# 4. 运行
flutter run
```

### Firebase 配置（5 步）

1. [创建 Firebase 项目](https://console.firebase.google.com/)
2. 添加 Android 应用（包名：`com.clearcall.app`），下载 `google-services.json`
3. 将 `google-services.json` 放到 `android/app/` 目录
4. 启用 **匿名认证**（Authentication → Anonymous）
5. 创建 **Realtime Database**（推荐 `asia-southeast1` 新加坡节点，测试模式）

> 已配置 `.gitignore` 忽略 `google-services.json`，API 密钥不会上传到 Git。

---

## 📁 项目结构

```
ClearCall/
├── README.md                            ← 你在这里
├── CLAUDE.md                            ← 项目总指引（AI 开发规范）
├── clearcall-dev/                       ← 9 份标准文件（需求/架构/UI/协议）
│   ├── 00-overview.md                   ← 项目全景
│   ├── 01-requirements.md               ← 功能需求 + 16 项决策
│   ├── 02-tech-architecture.md          ← 技术架构
│   ├── 03-ui-design-spec.md             ← UI 设计规范（18 个界面）
│   ├── 04-development-plan.md           ← 6 阶段开发计划
│   ├── 05-coding-standards.md           ← 编码规范
│   ├── 06-firebase-schema.md            ← Firebase 数据结构
│   ├── 07-api-protocol.md               ← WebRTC 信令协议
│   ├── 08-leancloud-adapter.md          ← Leancloud 国内方案
│   └── 09-dev-governance.md             ← 开发治理规范
├── dev-logs/                            ← 每日开发日志
└── clearcall/                           ← Flutter 项目
    ├── android/
    │   └── app/src/main/kotlin/
    │       └── MainActivity.kt          ← 原生层（PiP/音频/铃声/网络检测）
    └── lib/
        ├── main.dart                    ← 入口 + AppRoot 生命周期
        ├── app.dart                     ← MaterialApp 主题配置
        ├── models/                      ← 数据模型
        │   ├── user.dart                ← 本地用户模型
        │   ├── friend.dart              ← 好友/好友申请模型
        │   ├── room.dart                ← 房间/房间事件模型
        │   └── call_record.dart         ← 通话记录模型
        ├── services/                    ← 业务服务
        │   ├── signaling/
        │   │   ├── signaling_service.dart   ← 信令抽象接口（30 个方法）
        │   │   ├── firebase_signaling.dart  ← Firebase RTDB 实现
        │   │   └── leancloud_signaling.dart ← Leancloud 实现（预留）
        │   ├── webrtc_service.dart      ← WebRTC 媒体采集/连接/渲染
        │   ├── call_manager.dart        ← 通话状态机 + 信令协调 + 结束报告
        │   ├── friend_manager.dart      ← 好友系统（用户节点/状态/申请/删除）
        │   ├── call_history_db.dart     ← sqflite 通话记录本地存储
        │   ├── ringtone_service.dart    ← 系统铃声音效（MethodChannel）
        │   ├── pip_service.dart         ← 画中画服务（MethodChannel）
        │   ├── audio_device_service.dart← 音频设备检测（MethodChannel）
        │   ├── connectivity_service.dart← 网络类型检测（MethodChannel）
        │   └── fcm_service.dart         ← FCM 推送服务
        ├── providers/                   ← 状态管理（Riverpod）
        │   ├── call_provider.dart       ← 通话状态 + 好友呼叫
        │   ├── friend_provider.dart     ← 好友列表 + 申请状态
        │   ├── call_history_provider.dart← 通话记录状态
        │   ├── settings_provider.dart   ← 用户设置
        │   └── signaling_provider.dart  ← 共享信令实例
        ├── screens/                     ← 页面
        │   ├── welcome_screen.dart      ← 首次启动欢迎页
        │   ├── home_screen.dart         ← Tab 导航主页
        │   ├── call_tab.dart            ← 通话 Tab（房间按钮 + 通话记录）
        │   ├── friends_tab.dart         ← 好友 Tab（列表/搜索/呼叫/删除）
        │   ├── profile_tab.dart         ← 我 Tab（头像/昵称/设置）
        │   ├── room_waiting_screen.dart ← 房间等待页（房间号/二维码/倒计时）
        │   ├── join_room_screen.dart    ← 加入房间页（输入房间号/扫码）
        │   ├── call_screen.dart         ← 通话中界面（2P/3P/控制栏/PiP/补光/调试）
        │   ├── incoming_call_screen.dart← 来电接听界面
        │   └── add_friend_screen.dart   ← 添加好友页（二维码/扫一扫）
        ├── widgets/                     ← 可复用组件
        │   ├── glass_card.dart          ← 磨砂卡片
        │   ├── glass_button.dart        ← 磨砂按钮（3 种类型）
        │   ├── color_avatar.dart        ← 自动生成彩色头像（12 色调色板）
        │   ├── call_controls.dart       ← 通话控制栏（7 按钮）
        │   ├── speaker_picker.dart      ← 扬声器选择面板（含蓝牙）
        │   ├── name_card_overlay.dart   ← 通话中名片条
        │   └── debug_panel.dart         ← 开发者调试面板
        └── utils/                       ← 工具函数
            ├── id_generator.dart        ← 本地唯一 ID 生成（UUID v4）
            ├── qr_utils.dart            ← 二维码生成/解析工具
            └── constants.dart           ← 全局常量（26 色 + 排版 + 尺寸 + pref key）
```

---

## 🛠 技术栈

| 类别 | 技术 | 版本 |
|------|------|------|
| 框架 | Flutter | 3.44.1 |
| 语言 | Dart | 3.12.1 |
| 音视频 | WebRTC（flutter_webrtc） | 0.10+ |
| 信令 | Firebase Realtime Database | 11.0+ |
| 穿透 | Google STUN + Metered.ca TURN | - |
| 推送 | Firebase Cloud Messaging | 15.0+ |
| 认证 | Firebase Anonymous Auth | 5.0+ |
| 状态管理 | Riverpod | 2.5+ |
| 本地存储 | sqflite + SharedPreferences | 2.3+ / 2.2+ |
| 二维码 | qr_flutter + mobile_scanner | 4.1+ / 5.0+ |
| 权限 | permission_handler | 11.0+ |

### 音视频规格

| 参数 | 默认值 | 可选 |
|------|------|------|
| 视频分辨率 | 720p 自适应 | 最高 1080p 手动 |
| 视频帧率 | 30fps | 最高 60fps |
| 视频编码 | H.264 硬编 | H.265 可选（需设备支持） |
| 视频码率上限 | 10 Mbps | - |
| 音频编码 | Opus 48kHz | G.722 / Opus 16kHz |
| 音频码率 | 48 Kbps | 24 / 64 Kbps |
| 关键帧间隔 | 2 秒 GOP | - |
| 画质偏好 | 流畅优先 | 均衡 / 清晰优先（三档） |
| 带宽检测 | WebRTC GCC | - |

### 网络自适应

| 检测带宽 | 视频档位 | 音频档位 |
|------|------|------|
| > 3 Mbps | 1080p@30fps | Opus 48kHz@48K |
| 2 - 3 Mbps | 720p@30fps | Opus 48kHz@48K |
| 1 - 2 Mbps | 480p@24fps | Opus 48kHz@48K |
| 500K - 1 Mbps | 360p@15fps | Opus 48kHz@40K |
| 300K - 500K | 360p@15fps 限 300K | Opus 16kHz@24K |
| < 300K | 仅音频 | Opus 16kHz@24K |

---

## 📱 已完成功能

### 阶段 1：Flutter 项目 + 基础 UI ✅
- ✅ Flutter 项目骨架（pubspec.yaml + AndroidManifest 12 项权限）
- ✅ 磨砂组件库（GlassCard / GlassButton(3 种类型) / GlassScaffold）
- ✅ 自动生成彩色头像（12 色调色板 + 哈希选色）
- ✅ 3 Tab 导航（通话/好友/我）
- ✅ 首次启动欢迎页 + 昵称输入
- ✅ 本地唯一 ID 生成（UUID v4）

### 阶段 2：房间通话 + 完整通话功能 ✅
- ✅ 6 位随机房间号创建/加入 + 二维码分享
- ✅ 房间超时（5 分钟无人加入自动关闭）+ 满员处理（最多 3 人）
- ✅ 2 人全屏 + 可拖拽 PIP 小窗 / 3 人等分网格布局
- ✅ 底部控制栏 7 按钮（静音/补光/摄像头/扬声器/翻转/挂断/齿轮）
- ✅ iPhone 风格扬声器选择面板（扬声器/听筒/蓝牙）
- ✅ 通话菜单 + 名片条（3 秒自动消失，非好友可添加）
- ✅ 前置补光 + 视频静画（头像替代黑屏）
- ✅ 网络质量指示（绿/黄/红圆点，点击展开延迟丢包）
- ✅ 通话设置面板（视频 4 项 + 音频 5 项，即时生效）
- ✅ H.265 检测与切换（不支持时开关置灰）
- ✅ 摄像头档位记忆（SharedPreferences 持久化全部设置）
- ✅ 挂断动画（350ms ScaleTransition + FadeTransition）
- ✅ 画中画（PiP）模式（按 Home 键自动悬浮窗）
- ✅ 蓝牙耳机自动检测
- ✅ 通话记录本地存储（sqflite + 列表 + 长按删除）
- ✅ 呼叫铃声音效 + 接通/挂断通知音效
- ✅ 通话结束报告（对象/时长/质量评级/流量/建议）
- ✅ 流量警告弹窗（首次移动数据通话，可不再提醒）
- ✅ 权限降级（摄像头拒绝→纯音频 / 麦克风拒绝→黄色提示）
- ✅ 高级调试面板（通话中浮动实时指标）

### 阶段 3：好友系统 + 在线呼叫 ✅
- ✅ Firebase 用户节点管理（`/users/{uid}/` 自动创建和维护）
- ✅ 在线状态管理（online/offline/in-call + onDisconnect 断连保护）
- ✅ 好友申请流程（发送申请 → 监听 → 同意/拒绝 → Firebase 双向写入）
- ✅ 个人二维码生成（`clearcall://friend/{uid}/{token}` 格式）
- ✅ 扫码添加好友（MobileScanner 自动检测 + 确认弹窗）
- ✅ 分享链接添加好友（SelectableText 可复制）
- ✅ 好友列表 UI（ColorAvatar + 状态圆点 🟢在线/🟠通话中/⚫离线 + 搜索过滤 + 离线半透明）
- ✅ 好友删除（长按确认 → 双向清理）
- ✅ FCM 推送服务（Token 获取 + 通知权限 + 前台/后台消息处理）
- ✅ 来电接听界面（深色全屏 + 头像/昵称 + SlideAnimation + 接听(绿)/拒绝(红)）
- ✅ 好友在线呼叫（点击好友 → RTDB 信令 → 对方收到来电）
- ✅ 呼叫超时（60s 无人接听自动挂断）/ 拒绝处理
- ✅ 好友请求管理（顶部横幅 + 底部弹窗列表同意/拒绝）
- ✅ 好友通话记录回拨（图标按钮 + 长按菜单）

---

## 📊 开发进度

| 阶段 | 名称 | 状态 | 关键产出 |
|------|------|------|------|
| 0 | 项目初始化与规范 | ✅ 完成 | 9 份标准文件 + CLAUDE.md |
| 1 | Flutter 项目 + 基础 UI | ✅ 完成 | App 壳 + Tab 导航 + 磨砂组件库 |
| 2 | 房间通话 + 完整通话功能 | ✅ 完成 | 2-3人 P2P/Mesh 通话 + 34 项功能 |
| 3 | 好友系统 + 在线呼叫 | ✅ 完成 | 好友添加/列表/状态/FCM 推送 + 14 项功能 |
| 4 | UI 打磨与动画 | 🔜 下一步 | 动效/过渡/异常状态/屏幕适配 |
| 5 | 测试与优化 | ⬜ 待开始 | 单元/集成测试 + 性能优化 + 多设备兼容 |
| 6 | 发布与后续迭代 | ⬜ 待开始 | Google Play 上架 + 用户反馈迭代 |

> 详见 [`04-development-plan.md`](clearcall-dev/04-development-plan.md)

---

## 📝 开发日志

所有开发过程记录在 [`dev-logs/`](dev-logs/) 目录，按日期归档。

- [2026-06-09](dev-logs/2026-06-09.md) — 阶段 1~3 全部完成（Flutter 初始化 + 34 项通话功能 + 14 项好友系统）

---

## 🔧 开发规范

本项目遵循严格的开发治理规范（详见 [09-dev-governance.md](clearcall-dev/09-dev-governance.md)）：

- 📋 **标准文件即宪法**：所有代码对齐 9 份标准文件，矛盾时改实现
- 📐 **一次一个阶段**：严格按 6 阶段顺序执行，不跳步
- ✅ **场景全覆盖**：每个功能覆盖正常/边界/异常/权限拒绝/空状态/并发
- 📝 **中文提交信息**：`[阶段X] 简短描述`
- 🔄 **每次任务后更新文档 + Git 推送**

---

## 📄 许可

本项目仅供学习和个人使用。
