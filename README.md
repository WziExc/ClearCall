# ClearCall — 极简视频通话

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.22+-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.4+-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-Android%208.0+-34A853?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/WebRTC-1.0-21C25E" alt="WebRTC">
  <img src="https://img.shields.io/badge/Firebase-Realtime%20DB-FFCA28?logo=firebase" alt="Firebase">
</p>

ClearCall 是一款极简风格的视频通话 App。不需要注册账号，不读取通讯录，通过 **6 位数字房间号** 或 **二维码** 即可快速发起 2-3 人视频通话。

---

## ✨ 核心卖点

| 卖点 | 说明 |
|------|------|
| 🔢 **房间号即开即用** | 生成 6 位随机房间号，告诉好友即可通话 |
| 📱 **扫码加入** | 房间号一键生成二维码，好友扫码自动加入 |
| 👤 **匿名优先** | 无需手机号、无需邮箱，非好友也能通话 |
| 🎨 **磨砂风格** | iOS 风格磨砂玻璃界面，简洁清爽 |
| 🌏 **国内优化** | Firebase 为主信令，新加坡节点低延迟；预留 Leancloud 适配 |

---

## 🚀 快速开始

### 环境要求

- **Flutter** 3.22+ / **Dart** 3.4+
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
    └── lib/
        ├── models/                      ← 数据模型
        ├── services/                    ← 业务服务（WebRTC / Firebase 信令）
        ├── providers/                   ← 状态管理（Riverpod）
        ├── screens/                     ← 页面
        ├── widgets/                     ← 可复用组件
        └── utils/                       ← 工具函数
```

---

## 🛠 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.22+ |
| 音视频 | WebRTC（flutter_webrtc） |
| 信令 | Firebase Realtime Database |
| 穿透 | Google STUN + Metered.ca TURN |
| 推送 | Firebase Cloud Messaging |
| 状态管理 | Riverpod |
| 本地存储 | sqflite + SharedPreferences |
| 二维码 | qr_flutter + mobile_scanner |
| 认证 | Firebase Anonymous Auth |

### 音视频规格

| 参数 | 默认值 |
|------|------|
| 视频分辨率 | 720p 自适应（最高 1080p） |
| 视频帧率 | 30fps（最高 60fps） |
| 视频编码 | H.264 硬编（H.265 可选） |
| 音频编码 | Opus 48kHz |
| 画质偏好 | 流畅优先 / 均衡 / 清晰优先（三档） |

---

## 📊 开发进度

| 阶段 | 名称 | 状态 |
|------|------|------|
| 0 | 项目初始化与规范 | ✅ 完成 |
| 1 | Flutter 项目 + 基础 UI | ✅ 完成 |
| 2-A | 信令与 WebRTC 基础 | ✅ 完成 |
| 2-B | 房间创建与加入 | ✅ 完成 |
| 2-C | 通话界面与交互 | 🔜 进行中 |
| 2-D | 通话记录、报告与权限 | ⬜ 待开始 |
| 3 | 好友系统 + 在线呼叫 | ⬜ 待开始 |
| 4 | UI 打磨与动画 | ⬜ 待开始 |
| 5 | 测试与优化 | ⬜ 待开始 |
| 6 | 发布与后续迭代 | ⬜ 待开始 |

> 详见 [`04-development-plan.md`](clearcall-dev/04-development-plan.md)

---

## 📝 开发日志

所有开发过程记录在 [`dev-logs/`](dev-logs/) 目录，按日期归档。

---

## 📄 许可

本项目仅供学习和个人使用。
