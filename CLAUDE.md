# CLAUDE.md — ClearCall 项目总指引

> **项目**：ClearCall — 极简视频通话 App（安卓 / Flutter）  
> **用户**：编程小白，需中文沟通、注释，按规范推进  
> **最后更新**：2026-06-10（双部署方案：本地 ngrok + Cloudflare Workers）  
> **当前阶段**：阶段 C — 真机测试 + 部署 + 发布准备

---

## 快速恢复（上下文重置后 5 分钟必读）

| 步骤 | 文件 | 获取信息 |
|---|---|---|
| 1 | 本文件 CLAUDE.md | 项目概览、文件索引、工作规则 |
| 2 | [clearcall-dev/00-overview.md](clearcall-dev/00-overview.md) | 项目定位、核心卖点、技术路线 |
| 3 | [clearcall-dev/04-development-plan.md](clearcall-dev/04-development-plan.md) | 当前阶段、任务清单、验收标准 |
| 4 | [dev-logs/](dev-logs/) 最新日志 | 最近完成、进行中、阻塞问题 |

---

## 标准文件索引（6 份核心文件）

| # | 文件 | 内容 | 何时查阅 |
|---|---|---|---|
| 00 | [00-overview.md](clearcall-dev/00-overview.md) | 项目全景、定位、卖点 | 首次上手 |
| 01 | [01-requirements.md](clearcall-dev/01-requirements.md) | 全部功能需求 + 状态标记 | 开发任何功能前 |
| 02 | [02-tech-architecture.md](clearcall-dev/02-tech-architecture.md) | 技术架构（WebSocket+QR/WebRTC/TURN） | 技术选型时 |
| 03 | [03-ui-design-spec.md](clearcall-dev/03-ui-design-spec.md) | UI 设计规范（颜色/字体/布局/组件） | 写 UI 代码前 |
| 04 | [04-development-plan.md](clearcall-dev/04-development-plan.md) | 分阶段开发计划 + 任务清单 | 确认进度 |
| 05 | [05-coding-standards.md](clearcall-dev/05-coding-standards.md) | 编码规范（命名/目录/注释/测试/Git） | 提交代码前 |

## 补充文件（按需查阅）

| # | 文件 | 内容 |
|---|---|---|
| 07 | [07-api-protocol.md](clearcall-dev/07-api-protocol.md) | WebSocket + QR 信令协议 + 音视频规格 |
| 09 | [09-dev-governance.md](clearcall-dev/09-dev-governance.md) | 开发治理规范（变更流程/质量/测试） |
| 10 | [10-implementation-plans.md](clearcall-dev/10-implementation-plans.md) | 实施方案存档 |

---

## 开发日志

每日日志：`dev-logs/YYYY-MM-DD.md`。每天开始：查看前一天日志 → 续写当天。

---

## 核心规则

### 1. 标准文件即宪法
- 代码必须对齐标准文件。标准 vs 实现矛盾 → **改实现**
- 标准本身需修改 → **先改标准，再改代码**
- C 类变更（需求变更）→ **必须先与用户确认**

### 2. 先规划、后执行
- ≥5 个文件或 ≥200 行新代码 → 先写方案到 `10-implementation-plans.md`
- 汇报方案 → 等待确认 → 执行 → 结案
- 例外（可直接执行）：纯查询 / 用户说"直接改" / 单行 bug 修复

### 3. 一次一个阶段
- 按 `04-development-plan.md` 阶段顺序执行
- 阶段验收通过后才进入下一阶段

### 4. 场景覆盖
每个功能覆盖：正常 / 边界 / 异常 / 权限拒绝 / 空状态

### 5. 任务完成后更新文档
- 日常：更新 `dev-logs/` + `04-development-plan.md` 任务勾选
- 阶段完成：额外更新 CLAUDE.md + README.md + 相关标准文件
- Git 推送：每完成一个有意义的里程碑推送一次

### 6. 问题分级
- 🟢 编码细节（标准已覆盖）→ 自行解决
- 🟡 标准未明确 → 参考架构判断，记录决策
- 🟠 标准间矛盾 → 停止，解决矛盾
- 🔴 核心功能无法实现 → 停止，报告用户

### 7. 资源回收
- 所有 `Timer` 在 `dispose()` 中 cancel
- 所有 `AnimationController` 在 `dispose()` 中 dispose
- 所有 `StreamSubscription` 在 `dispose()` 中 cancel

---

## 项目速查

### 核心参数

| 项目 | 值 |
|---|---|
| 技术栈 | Flutter 3.22+ / Dart 3.4+ |
| 平台 | Android 8.0+ (minSdk 26) |
| 信令 | WebSocket 中继（主力）+ QR 扫码（后备） |
| 中继部署 | Render.com 免费层 |
| 穿透 | Google STUN + Metered.ca TURN |
| 状态管理 | Riverpod |
| 本地存储 | SharedPreferences |

### 音视频默认值

| 参数 | 默认 |
|---|---|
| 视频分辨率 | 720p 自适应（最高 1080p 手动） |
| 视频帧率 | 30fps（最高 60fps 手动） |
| 视频编码 | H.264 硬编（H.265 可选） |
| 视频码率上限 | 10 Mbps |
| 音频编码 | Opus 48kHz |
| 音频码率 | 48 Kbps |
| 画质偏好 | 流畅优先（三档可选） |
| 带宽检测 | WebRTC GCC |

### 关键决策

| # | 决策 |
|---|---|
| 1 | Flutter（保留 iOS 扩展） |
| 2 | WebSocket 中继 + QR 扫码双信令方案 |
| 3 | Metered.ca 免费 TURN fallback |
| 4 | 信令中继部署 Render.com 免费层 |
| 5 | 离线添加好友 → 后期 |
| 6 | 自动颜色头像 |
| 7 | App 名称 ClearCall |
| 8 | 通话中名片 → 菜单触发 + 轻触触发 |
| 9 | 3 人通话 Mesh 组网 |
| 10 | 扬声器 → iPhone 风格磨砂面板 |
| 11 | 房间超时 → 5 分钟 |
| 12 | 房间满员 → 提示"最多 3 人" |
| 13 | 权限拒绝 → 降级可用 |
| 14 | 铃声音效 → 系统铃声 |
| 15 | 蓝牙 → 自动支持 |

---

## 项目目录结构

```
clearcall/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── models/                    # 数据模型
│   ├── services/                  # 业务服务
│   │   └── signaling/             # 信令抽象层（WebSocket + QR）
│   ├── providers/                 # Riverpod 状态管理
│   ├── screens/                   # 页面
│   ├── widgets/                   # 可复用 UI 组件
│   └── utils/                     # 工具函数
├── test/                          # 测试（172 项）
├── signaling_server/              # 信令中继服务器（独立部署）
└── clearcall-dev/                 # 6 份标准文件
```
