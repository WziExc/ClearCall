# 02 — 技术架构

> **核心原则**：零自建服务器，所有后端能力来自免费第三方服务。

---

## 架构总览

```
┌─────────────────────────────────────────────────────────┐
│                    ClearCall App (Flutter)               │
├─────────────────────────────────────────────────────────┤
│  UI Layer          │  毛玻璃组件 / 通话界面 / 好友列表    │
├─────────────────────────────────────────────────────────┤
│  Business Layer    │  通话管理 / 好友管理 / 状态管理      │
├─────────────────────────────────────────────────────────┤
│  Service Layer     │  SignalingService (抽象)             │
│                    │  ├─ FirebaseSignaling (主)          │
│                    │  └─ LeancloudSignaling (备)         │
│                    │  + WebRTCService / FCMService        │
├─────────────────────────────────────────────────────────┤
│  Platform Layer    │  flutter_webrtc / camera / mic       │
└─────────────────────────────────────────────────────────┘
                              │
                  ┌───────────┼───────────┐
                  ▼           ▼           ▼
           ┌──────────┐ ┌──────────┐ ┌──────────┐
           │ Firebase │ │ Leancloud│ │  STUN/   │
           │ Realtime │ │ (备用)   │ │  TURN    │
           │ Database │ │          │ │  Servers │
           └──────────┘ └──────────┘ └──────────┘
            信令/状态    信令/状态       P2P穿透
```

---

## 技术栈

### 核心框架
| 技术 | 版本 | 用途 |
|---|---|---|
| Flutter | 3.22+ | 跨平台 UI 框架 |
| Dart | 3.4+ | 开发语言 |
| Android SDK | min 26 (8.0) | 目标安卓版本 |

### 音视频
| 技术 | 用途 |
|---|---|
| flutter_webrtc | WebRTC Flutter 绑定 |
| Google STUN | 免费 NAT 穿透（stun:stun.l.google.com:19302） |
| Metered.ca TURN | 免费 TURN 中继 fallback（turn:openrelay.metered.ca:80） |

### 信令与数据
| 技术 | 用途 | 免费配额 |
|---|---|---|
| Firebase Realtime Database | 信令交换、在线状态、好友关系 | 100 并发 / 1GB / 10GB 月下载 |
| Firebase Cloud Messaging | 来电推送通知 | 免费无限 |
| Leancloud | 国内备选方案 | 开发版免费 |

### 本地存储
| 技术 | 用途 |
|---|---|
| sqflite | 通话记录本地持久化 |
| shared_preferences | 用户设置、昵称、本地 ID |

### 二维码
| 技术 | 用途 |
|---|---|
| qr_flutter | 生成二维码（房间号、好友） |
| mobile_scanner | 扫描二维码 |

---

## 信令服务抽象层设计

```dart
// 信令服务接口 — Firebase 和 Leancloud 都实现此接口
abstract class SignalingService {
  // 房间管理
  Future<String> createRoom(String userId);
  Future<void> joinRoom(String roomId, String userId);
  Future<void> leaveRoom(String roomId, String userId);
  Stream<RoomEvent> onRoomEvent(String roomId);

  // WebRTC 信令
  Future<void> sendOffer(String roomId, String userId, RTCSessionDescription offer);
  Future<void> sendAnswer(String roomId, String userId, RTCSessionDescription answer);
  Future<void> sendCandidate(String roomId, String userId, RTCIceCandidate candidate);

  // 好友系统
  Future<void> sendFriendRequest(String fromUid, String toUid, String nickname, String token);
  Stream<FriendRequest> onFriendRequest(String userId);
  Future<void> acceptFriendRequest(String fromUid, String toUid);
  Future<void> rejectFriendRequest(String fromUid, String toUid);
  Future<void> removeFriend(String uid, String friendUid);

  // 在线状态
  Future<void> setOnlineStatus(String userId, OnlineStatus status);
  Stream<OnlineStatus> onFriendStatusChange(String userId);

  // 呼叫信令
  Future<void> sendCallOffer(String fromUid, String toUid, Map<String, dynamic> callData);
  Future<void> sendCallAnswer(String fromUid, String toUid, Map<String, dynamic> answerData);
  Future<void> sendCallReject(String fromUid, String toUid);

  // 连接检测
  Future<bool> isAvailable();
}
```

## WebRTC 连接流程

```
呼叫方(A)                          Firebase                         被叫方(B)
   │                                  │                                │
   │── createRoom/offer ─────────────>│                                │
   │                                  │──── onCallOffer ──────────────>│
   │                                  │                                │── 弹出接听界面
   │                                  │                                │── 用户点击接听
   │                                  │<─── createAnswer ──────────────│
   │<── onCallAnswer ─────────────────│                                │
   │                                  │                                │
   │<══════════ ICE Candidate 交换 ════════════════════════════════>│
   │                                  │                                │
   │<═══════════ P2P 音视频流 (SRTP) ══════════════════════════════>│
   │                                  │                                │
```

## 三人 Mesh 组网（阶段 2 实现）

3 人通话时，每个参与者与另外两人各建立一条 P2P 连接：
- 总连接数：3 × 2 / 2 = 3 条
- 每个端上载：2 路视频流
- 每个端下载：2 路视频流

流量估算（单路 720p ~1.5Mbps）：
- 每人上行：3Mbps
- 每人下行：3Mbps
- 总计：约 9Mbps 全局

> **未来扩展**：超过 3 人需要 SFU（Selective Forwarding Unit）服务器中转，届时架构从 Mesh 切换到 SFU 模式。目录结构预留 `services/sfu/` 扩展点。

## 关键子系统

### 画中画（PiP）
- 使用 Flutter `pip_mode` 或原生 Android PictureInPicture API
- 通话 Activity 进入后台时自动触发
- PiP 窗口显示对方视频流 + 静音/挂断最小控制
- Android 8.0+ 原生支持

### 音频路由（扬声器/听筒/蓝牙）
- WebRTC 音频输出跟随系统音频路由
- 使用 `flutter_webrtc` 的 `enableSpeakerphone()` 切换扬声器/听筒
- 蓝牙设备连接时 Android 系统自动路由音频到蓝牙
- UI 面板通过查询系统音频设备列表展示可选路由

## 目录结构（计划）

```
clearcall/
├── lib/
│   ├── main.dart
│   ├── app.dart                          # MaterialApp 配置
│   ├── models/                           # 数据模型
│   │   ├── user.dart
│   │   ├── friend.dart
│   │   ├── room.dart
│   │   ├── call_record.dart
│   │   └── friend_request.dart
│   ├── services/                         # 业务服务
│   │   ├── signaling/
│   │   │   ├── signaling_service.dart    # 抽象接口
│   │   │   ├── firebase_signaling.dart   # Firebase 实现
│   │   │   └── leancloud_signaling.dart  # Leancloud 实现（后续）
│   │   ├── webrtc_service.dart
│   │   ├── call_manager.dart             # 通话状态机 + 铃声音效 + 统计收集 + 好友呼叫
│   │   ├── call_history_db.dart          # sqflite 通话记录数据库
│   │   ├── ringtone_service.dart         # 系统铃声音效（MethodChannel）
│   │   ├── pip_service.dart              # 画中画服务（MethodChannel）
│   │   ├── audio_device_service.dart     # 音频设备检测（含蓝牙）
│   │   ├── connectivity_service.dart     # 网络类型检测（Wi-Fi/移动数据）
│   │   ├── fcm_service.dart              # FCM 推送服务
│   │   ├── friend_manager.dart           # 好友系统管理（用户节点/在线状态/申请/删除）
│   │   ├── audio_router.dart             # 扬声器/听筒/蓝牙路由
│   │   ├── pip_manager.dart              # 画中画管理
│   │   └── permissions_service.dart      # 权限管理
│   ├── providers/                        # 状态管理（Riverpod）
│   │   ├── call_provider.dart            # 通话状态 + 好友呼叫
│   │   ├── call_history_provider.dart    # 通话记录列表状态
│   │   ├── friend_provider.dart          # 好友列表 + 申请状态
│   │   ├── signaling_provider.dart       # 共享信令服务实例
│   │   └── settings_provider.dart
│   ├── screens/                          # 页面
│   │   ├── welcome_screen.dart            # 首次启动欢迎页 + 昵称输入
│   │   ├── home_screen.dart              # 主界面（Tab 切换）
│   │   ├── call_tab.dart                 # 通话 Tab（含通话记录列表）
│   │   ├── friends_tab.dart              # 好友 Tab
│   │   ├── profile_tab.dart              # 我 Tab
│   │   ├── room_waiting_screen.dart       # 房间等待页（房间号/二维码/倒计时）
│   │   ├── join_room_screen.dart          # 加入房间（输入房间号/扫码）
│   │   ├── call_screen.dart              # 通话中界面（含挂断动画/PiP/补光/调试面板/权限降级）
│   │   ├── incoming_call_screen.dart     # 来电接听界面
│   │   ├── add_friend_screen.dart        # 添加好友
│   │   └── settings_screen.dart          # 设置
│   ├── widgets/                          # 可复用组件
│   │   ├── glass_card.dart              # 磨砂卡片
│   │   ├── glass_button.dart            # 磨砂按钮
│   │   ├── color_avatar.dart            # 自动生成头像
│   │   ├── draggable_pip.dart           # 可拖拽小窗
│   │   ├── call_controls.dart           # 通话控制栏（7 按钮）
│   │   ├── name_card_overlay.dart       # 通话中名片条
│   │   ├── speaker_picker.dart          # 扬声器选择面板（含蓝牙）
│   │   ├── debug_panel.dart             # 开发者调试面板
│   │   ├── friend_list_item.dart        # 好友列表项
│   │   └── permission_prompt.dart       # 权限提示组件
│   └── utils/                            # 工具函数
│       ├── id_generator.dart             # 唯一 ID 生成
│       ├── qr_utils.dart                 # 二维码工具
│       └── constants.dart               # 常量定义
├── test/                                 # 测试
│   ├── unit/
│   └── widget/
├── assets/
│   ├── fonts/                            # SF Symbol 风格图标字体
│   └── sounds/                           # 通话铃声
└── pubspec.yaml
```
