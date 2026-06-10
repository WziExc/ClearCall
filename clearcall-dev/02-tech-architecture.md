# 02 — 技术架构

> **核心原则**：零自建服务器（信令中继使用免费云部署），所有后端能力来自免费第三方服务。

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
│                    │  ├─ WebSocketSignaling (主力·远程)   │
│                    │  └─ QrSignaling (后备·面对面)        │
│                    │  + WebRTCService                     │
├─────────────────────────────────────────────────────────┤
│  Platform Layer    │  flutter_webrtc / camera / mic       │
└─────────────────────────────────────────────────────────┘
                              │
                  ┌───────────┼───────────┐
                  ▼                       ▼
           ┌──────────────┐        ┌──────────┐
           │ 信令中继服务器 │        │  STUN/   │
           │ (Render.com   │        │  TURN    │
           │  免费部署)     │        │  Servers │
           └──────────────┘        └──────────┘
             WebSocket 转发           P2P穿透
```

## 信令双方案

| 模式 | 服务器 | 适用场景 | 默认 |
|------|--------|----------|------|
| WebSocket 中继 | Render.com 免费云 | 远程创建/加入房间 | ✅ 主力 |
| QR 扫码 SDP 交换 | 完全无服务器 | 面对面 / 应急 | 后备 |

用户可在设置中手动切换，默认使用 WebSocket 中继。

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
| WebSocket (shelf + shelf_web_socket) | 信令中继服务器 | Render.com 免费层 750h/月 |
| QR Code (qr_flutter + mobile_scanner) | 离线 SDP 交换 | 无限 |

### 本地存储
| 技术 | 用途 |
|---|---|
| shared_preferences | 用户设置、昵称、本地 ID |

### 二维码
| 技术 | 用途 |
|---|---|
| qr_flutter | 生成二维码（房间号、好友） |
| mobile_scanner | 扫描二维码 |

---

## 信令服务抽象层设计

```dart
// 信令服务接口 — WebSocket 和 QR 都实现此接口
abstract class SignalingService {
  // 房间管理
  Future<String> createRoom(String userId);
  Future<void> joinRoom(String roomId, String userId);
  Future<void> leaveRoom(String roomId, String userId);
  Future<void> closeRoom(String roomId);
  Stream<RoomEvent> onRoomEvent(String roomId);
  Future<List<String>> getRoomParticipants(String roomId);
  Future<bool> isRoomFull(String roomId);

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
  Future<List<Friend>> getFriends(String userId);

  // 在线状态
  Future<void> setOnlineStatus(String userId, OnlineStatus status);
  Future<void> setDisconnectCleanup(String userId);
  Future<OnlineStatus> getUserStatus(String userId);
  Stream<Map<String, OnlineStatus>> onFriendsStatusChange(List<String> friendUids);

  // 呼叫信令
  Future<void> sendCallOffer(String fromUid, String toUid, Map<String, dynamic> callData);
  Future<void> sendCallAnswer(String fromUid, String toUid);
  Future<void> sendCallReject(String fromUid, String toUid);
  Stream<Map<String, dynamic>> onIncomingCall(String userId);
  Future<void> clearCallNode(String targetUid);

  // 连接检测
  Future<bool> isAvailable();
  Future<void> initialize();
  String get serviceName;
}
```

## WebSocket 连接流程

```
呼叫方(A)              信令中继(Render)              被叫方(B)
   │                         │                         │
   │── POST /rooms (创建) ──>│                         │
   │<── {"roomId":"123456"}──│                         │
   │── WS connect ───────────>│                         │
   │── {"type":"join"} ──────>│                         │
   │                         │                         │── POST /rooms/123456/join
   │                         │                         │── WS connect
   │                         │<── {"type":"join"} ─────│
   │<── {"type":"joined"} ───│                         │
   │                         │                         │
   │── {"type":"sdp","data": │                         │
   │     {"type":"offer",    │                         │
   │      "sdp":"..."}} ────>│                         │
   │                         │── 转发 sdp ────────────>│
   │                         │                         │── setRemoteDesc(offer)
   │                         │                         │── createAnswer()
   │                         │<── {"type":"sdp","data": │
   │                         │     {"type":"answer",   │
   │<── 转发 sdp ────────────│      "sdp":"..."}} ─────│
   │                         │                         │
   │<═════════ ICE Candidate 交换 (WebSocket) ═══════════════>│
   │                         │                         │
   │<═══════════ P2P 音视频流 (SRTP) ════════════════════════>│
```

## QR 扫码 SDP 交换流程（后备方案）

```
设备A                       设备B
  │                           │
  │ 创建房间 + 生成 Offer SDP  │
  │ 将 SDP 编码为 QR 码       │
  │ 显示 QR 码                │
  │                           │── 扫描 QR 码
  │                           │── 解码得到 Offer SDP
  │                           │── setRemoteDesc(offer)
  │                           │── createAnswer()
  │                           │── 将 Answer SDP 编码为 QR
  │<── 扫描 QR 码 ────────────│
  │── 解码得到 Answer SDP     │
  │── setRemoteDesc(answer)   │
  │                           │
  │<═══════ P2P 音视频流 ══════>│
```

## 三人 Mesh 组网

3 人通话时，每个参与者与另外两人各建立一条 P2P 连接：
- 总连接数：3 × 2 / 2 = 3 条
- 每个端上载：2 路视频流
- 每个端下载：2 路视频流

流量估算（单路 720p ~1.5Mbps）：
- 每人上行：3Mbps
- 每人下行：3Mbps

> **未来扩展**：超过 3 人需要 SFU 服务器中转。

## 关键子系统

### 音频路由（扬声器/听筒/蓝牙）
- WebRTC 音频输出跟随系统音频路由
- 使用 `flutter_webrtc` 的 `enableSpeakerphone()` 切换扬声器/听筒
- 蓝牙设备连接时 Android 系统自动路由音频到蓝牙

### 信令中继服务器
- 框架：shelf + shelf_web_socket (Dart)
- 部署：Render.com 免费层（Docker）
- 功能：房间 REST API + WebSocket 消息转发 + 自动清理

## 目录结构

```
clearcall/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── models/
│   │   ├── user.dart
│   │   ├── friend.dart
│   │   ├── room.dart
│   │   └── quality_presets.dart
│   ├── services/
│   │   ├── signaling/
│   │   │   ├── signaling_service.dart    # 抽象接口
│   │   │   ├── websocket_signaling.dart  # WebSocket 实现
│   │   │   └── qr_signaling.dart         # QR 扫码实现
│   │   ├── webrtc_service.dart
│   │   ├── call_manager.dart
│   │   ├── quality_controller.dart
│   │   ├── ringtone_service.dart
│   │   ├── audio_device_service.dart
│   │   ├── connectivity_service.dart
│   │   └── friend_manager.dart
│   ├── providers/
│   │   ├── call_provider.dart
│   │   ├── friend_provider.dart
│   │   ├── signaling_provider.dart
│   │   └── settings_provider.dart
│   ├── screens/
│   │   ├── welcome_screen.dart
│   │   ├── home_screen.dart
│   │   ├── call_tab.dart
│   │   ├── friends_tab.dart
│   │   ├── profile_tab.dart
│   │   ├── room_waiting_screen.dart
│   │   ├── join_room_screen.dart
│   │   ├── call_screen.dart
│   │   ├── add_friend_screen.dart
│   │   └── settings_screen.dart
│   ├── widgets/
│   │   ├── glass_card.dart
│   │   ├── glass_button.dart
│   │   ├── color_avatar.dart
│   │   ├── call_controls.dart
│   │   ├── call_quick_settings.dart
│   │   ├── name_card_overlay.dart
│   │   ├── speaker_picker.dart
│   │   ├── debug_panel.dart
│   │   ├── connectivity_banner.dart
│   │   ├── status_widgets.dart
│   │   ├── scale_tap.dart
│   │   └── responsive_wrapper.dart
│   └── utils/
│       ├── id_generator.dart
│       ├── qr_utils.dart
│       ├── dialogs.dart
│       └── constants.dart
├── test/
├── assets/
├── signaling_server/              # 信令中继服务器（独立部署）
│   ├── server.dart
│   ├── pubspec.yaml
│   ├── Dockerfile
│   └── render.yaml
└── pubspec.yaml
```
