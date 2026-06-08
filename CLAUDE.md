# CLAUDE.md — ClearCall 项目总指引

> **项目**：ClearCall — 极简视频通话 App（安卓 / Flutter）  
> **用户身份**：编程小白，需要用中文沟通、注释，按规范逐步推进  
> **最后更新**：2026-06-08  
> **当前阶段**：阶段 0 ✅ → 等待启动阶段 1

---

## 快速恢复（上下文重置后 5 分钟必读）

如果这是新的 Claude 会话，按此顺序快速恢复认知：

| 步骤 | 文件 | 获取信息 |
|---|---|---|
| 1 | 本文件 CLAUDE.md | 项目概览、文件索引、工作规则 |
| 2 | [clearcall-dev/00-overview.md](clearcall-dev/00-overview.md) | 项目定位、核心卖点、技术路线 |
| 3 | [clearcall-dev/04-development-plan.md](clearcall-dev/04-development-plan.md) | 当前阶段、任务清单、验收标准 |
| 4 | [dev-logs/](dev-logs/) 最新日志 | 最近完成事项、进行中、阻塞问题 |

完成恢复后直接继续当前阶段的工作。

---

## 标准文件索引

所有开发规范、需求和技术文档位于 `clearcall-dev/` 文件夹。

| # | 文件 | 内容 | 何时查阅 |
|---|---|---|---|
| 00 | [00-overview.md](clearcall-dev/00-overview.md) | 项目全景、定位、卖点 | 首次上手 |
| 01 | [01-requirements.md](clearcall-dev/01-requirements.md) | 全部功能需求 + 16 项确认决策 | 开发任何功能前 |
| 02 | [02-tech-architecture.md](clearcall-dev/02-tech-architecture.md) | 技术架构（Flutter/WebRTC/Firebase/PiP） | 技术选型时 |
| 03 | [03-ui-design-spec.md](clearcall-dev/03-ui-design-spec.md) | UI 设计规范（颜色/字体/布局/组件/18 个界面） | 写 UI 代码前 |
| 04 | [04-development-plan.md](clearcall-dev/04-development-plan.md) | 6 阶段开发计划 + 阶段 2 共 34 项任务 | 确认进度 |
| 05 | [05-coding-standards.md](clearcall-dev/05-coding-standards.md) | 编码规范（命名/目录/注释/测试/Git） | 提交代码前 |
| 06 | [06-firebase-schema.md](clearcall-dev/06-firebase-schema.md) | Firebase Realtime Database 数据结构 | 涉及信令/状态时 |
| 07 | [07-api-protocol.md](clearcall-dev/07-api-protocol.md) | WebRTC 信令协议 + 完整音视频规格 | 涉及通话/媒体时 |
| 08 | [08-leancloud-adapter.md](clearcall-dev/08-leancloud-adapter.md) | Leancloud 国内替代方案（后续实现） | 国内适配时 |
| 09 | [09-dev-governance.md](clearcall-dev/09-dev-governance.md) | 开发治理规范（铁律/变更流程/质量/测试矩阵） | 遇到问题或做变更时 |

---

## 开发日志

每日日志位于 `dev-logs/`，命名格式 `YYYY-MM-DD.md`。

每天开始工作：
1. 如果有前一天日志 → 查看"明天待办"，续写新日志
2. 如果是新一天 → 复制 `TEMPLATE.md`，填写当天日期
3. 记录：完成事项（打勾）、进行中、阻塞问题、备注/决策、明天待办

---

## 核心规则（不可违反）

### 标准文件即宪法
- 所有代码必须对齐标准文件。标准 vs 实现矛盾 → **改实现**。
- 标准本身需要修改 → **先改标准文件，再改代码**。
- 任何 C 类变更（需求变更）→ **必须先与用户确认**。

### 一次一个阶段
- 严格按 `04-development-plan.md` 的阶段顺序执行
- 阶段 N 的验收标准全部通过后，才能进入 N+1
- 不允许跨阶段开发

### 场景必须全覆盖
每个功能必须覆盖：正常 / 边界 / 异常 / 权限拒绝 / 空状态 / 并发

### 提交规范
- 中文提交信息
- 格式：`[阶段X] 简短描述`
- 提交前自查：flutter analyze 无 error / 新代码有测试 / 标准文件未过时

### 问题分级处理
- 🟢 编码细节（标准已覆盖）→ 自行解决
- 🟡 标准未明确 → 参考架构文档判断
- 🟠 标准间矛盾 → 停止，解决矛盾
- 🔴 核心功能无法实现 → 停止，报告用户

---

## 项目速查

### 核心参数

| 项目 | 值 |
|---|---|
| 技术栈 | Flutter 3.22+ / Dart 3.4+ |
| 平台 | Android 8.0+ (minSdk 26) |
| 信令 | Firebase Realtime DB（主）/ Leancloud（备） |
| 穿透 | Google STUN + Metered.ca TURN |
| 推送 | FCM |
| 状态管理 | Riverpod |
| 本地存储 | sqflite + SharedPreferences |

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
| GOP | 2 秒 |
| 带宽检测 | WebRTC GCC |

### 关键决策

| # | 决策 |
|---|---|
| 1 | Flutter（保留 iOS 扩展） |
| 2 | Firebase + Leancloud 双方案（抽象层切换） |
| 3 | Metered.ca 免费 TURN fallback |
| 4 | FCM 推送后台来电 |
| 5 | 离线添加好友 → 后期 |
| 6 | 自动颜色头像 + 可选照片 |
| 7 | App 名称 ClearCall |
| 8 | 通话中名片 → 菜单触发 + 轻触触发 |
| 9 | 3 人通话 → 阶段 2 同步实现（Mesh） |
| 10 | 扬声器 → iPhone 风格磨砂面板 |
| 11 | 房间超时 → 5 分钟 |
| 12 | 房间满员 → 提示"最多 3 人" |
| 13 | 权限拒绝 → 降级可用 |
| 14 | PiP 画中画 → 阶段 2 实现 |
| 15 | 铃声音效 → 系统 + 自定义 |
| 16 | 蓝牙 → 自动支持 |

### 功能分期

**当前（阶段 1-3）：**
1080p/60fps, H.264+H.265, Opus 48kHz, 网络质量指示, 通话菜单+名片, 设置面板, 💡补光, 静画头像, 挂断报告, 流量警告, 调试面板, 档位记忆, 2-3人通话, 好友系统

**后期（阶段 4-6）：**
自定义铃声, 画面适配, 音频效果, 人像居中, 屏幕共享, 闪光提醒, SFU 多人, iOS, Leancloud, 暗色模式

---

## 项目目录结构

```
First_Project/
├── CLAUDE.md                    ← 你在这里
├── clearcall-dev/               ← 9 份标准文件
├── dev-logs/                    ← 每日开发日志
└── clearcall/                   ← Flutter 项目（阶段 1 创建）
    └── 详见 02-tech-architecture.md 目录结构
```
