# CLAUDE.md — ClearCall 项目总指引

> **项目**：ClearCall — 极简视频通话 App（安卓 / Flutter）  
> **用户身份**：编程小白，需要用中文沟通、注释，按规范逐步推进  
> **最后更新**：2026-06-09  
> **当前阶段**：阶段 2 全部完成 ✅ → 阶段 3 待启动

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

### 每次完成任务后必须更新文档（铁律）
> **每次**完成一个或多个任务后，必须在提交代码前更新以下文件，不留遗漏：

| 优先级 | 文件 | 更新内容 |
|------|------|------|
| 🔴 必做 | `dev-logs/YYYY-MM-DD.md`（当天日志） | ✅完成事项（打勾）、📝新文件清单（路径+行数+说明）、🔧修改的文件（路径+改了什么）、📋新增/修改的方法或类、🐛修复的问题、💡决策记录、📋明天待办 |
| 🔴 必做 | `clearcall-dev/04-development-plan.md` | 对应任务的 `[ ]` 改为 `[x]`，阶段完成时更新验收标准勾选 |
| 🟡 按需 | `clearcall-dev/02-tech-architecture.md` | 如果新增了目录/服务/模块，更新目录结构图 |
| 🟡 按需 | `clearcall-dev/06-firebase-schema.md` | 如果修改了 Firebase 数据结构，更新节点路径 |
| 🟡 按需 | `clearcall-dev/07-api-protocol.md` | 如果修改了信令协议或音视频参数，更新对应章节 |
| 🟡 按需 | `clearcall-dev/01-requirements.md` | 如果需求有变更或补充，更新对应需求条目 |
| 🟡 按需 | `clearcall-dev/03-ui-design-spec.md` | 如果 UI 组件或页面设计有变更，更新对应章节 |
| 🟢 最后 | 本文件 `CLAUDE.md` | 更新"最后更新"日期和"当前阶段"状态 |

**日志记录格式要求：**
- 每个完成事项用 `[x]` 打勾
- 新文件用表格列出：路径 / 行数 / 说明
- 修改的文件列出：路径 + 具体改了什么（不要只写"修改了XX文件"）
- 修复的问题列出：文件:行号 + 问题描述
- 决策记录写清楚：为什么这样决定、有什么影响
- 明天待办要具体、可执行

**为什么必须这样做：**
- 用户是编程小白，需要通过文档了解项目进度
- 下次会话上下文丢失时，日志是唯一恢复来源
- 标准文件是项目的"宪法"，必须和代码保持同步
- 你（Claude）自己也会从准确的日志中受益

### 每次完成任务后必须 Git 推送（铁律）
> **每次**更新完文档和代码后，必须由 Claude 执行 Git 提交和推送。用户不需要手动操作。

**操作流程：**
1. `git status` — 查看所有变更文件，向用户展示变更清单
2. `git add -A` — 暂存所有变更（新增 + 修改 + 删除）
3. `git commit -m "[阶段X] 简短描述"` — 中文提交信息
4. `git push origin main` — 推送到 GitHub

**提交信息格式（中文）：**
```
[阶段2-B] 完成房间创建与加入（5项任务）
- 具体改动 1
- 具体改动 2
```

**推送前自检：**
- ✅ `flutter analyze` 无 error
- ✅ 开发日志已更新
- ✅ `04-development-plan.md` 任务勾选已更新
- ✅ 按需更新的标准文件已同步

**给用户的解释：**
- 每次推送前说明：哪些文件会提交、为什么
- `git status` 输出逐行解释每个文件的变化
- 如果 push 失败，解释原因和处理方法

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
