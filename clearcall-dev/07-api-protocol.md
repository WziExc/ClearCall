# 07 — 信令协议定义

> **协议类型**：WebSocket（主力·远程）+ QR SDP 交换（后备·面对面）  
> **编码**：UTF-8（JSON）  
> **传输**：仅控制面，媒体面走 SRTP（P2P 加密）

---

## 一、协议总览

| 模式 | 传输 | 房间管理 | 信令交换 | 适用场景 |
|------|------|----------|----------|----------|
| WebSocket 中继 | WebSocket + REST | 服务器管理 | 实时转发 | 远程通话（默认） |
| QR SDP 交换 | 二维码 | 本地生成 | 扫码注入 | 面对面 / 无网络 |

---

## 二、WebSocket 信令协议（主力）

### 2.1 REST API

| 方法 | 路径 | 功能 |
|------|------|------|
| POST | `/rooms` | 创建房间，返回 `{roomId, createdAt}` |
| GET | `/rooms/{roomId}` | 查询房间是否存在 |
| POST | `/rooms/{roomId}/join` | 加入房间 |
| DELETE | `/rooms/{roomId}` | 关闭房间 |

### 2.2 WebSocket 消息格式

**客户端 → 服务器**：

```json
{"type":"join","roomId":"123456","from":"uid_abc","data":{}}
{"type":"sdp","roomId":"123456","from":"uid_abc","to":"uid_def","data":{"type":"offer","sdp":"v=0\r\no=..."}}
{"type":"ice","roomId":"123456","from":"uid_abc","to":"uid_def","data":{"candidate":"...","sdpMid":"0","sdpMLineIndex":0}}
{"type":"leave","roomId":"123456","from":"uid_abc"}
{"type":"ping","from":"uid_abc"}
```

**服务器 → 客户端**：

```json
{"type":"joined","from":"server","data":{"roomId":"123456","participants":["uid_abc"]}}
{"type":"join","from":"uid_def","data":{}}
{"type":"leave","from":"uid_def","data":{}}
{"type":"sdp","from":"uid_abc","data":{"type":"offer","sdp":"v=0\r\no=..."}}
{"type":"ice","from":"uid_abc","data":{"candidate":"...","sdpMid":"0","sdpMLineIndex":0}}
{"type":"pong","from":"server"}
{"type":"error","from":"server","data":{"message":"房间不存在"}}
```

### 2.3 连接建立流程

```
主叫方(A)           信令中继(Render)            被叫方(B)
   │                     │                        │
   │ POST /rooms ───────>│                        │
   │<── {roomId:"123"} ──│                        │
   │ WS connect ────────>│                        │
   │ join ──────────────>│                        │
   │                     │                        │── POST /rooms/123/join
   │                     │                        │── WS connect + join
   │<── joined (B) ──────│                        │
   │                     │                        │
   │ 创建 PeerConnection  │                        │
   │ createOffer() → SDP │                        │
   │ sdp (offer) ───────>│── 转发 sdp ───────────>│
   │                     │                        │── setRemoteDesc(offer)
   │                     │                        │── createAnswer()
   │                     │<── sdp (answer) ────────│
   │<── 转发 sdp ────────│                        │
   │ setRemoteDesc(ans)  │                        │
   │                     │                        │
   │<════════ ICE Candidate (WebSocket) ══════════>│
   │                     │                        │
   │<══════════ P2P SRTP 媒体流 ══════════════════>│
```

---

## 三、QR SDP 交换协议（后备）

### 3.1 流程

```
设备A                            设备B
  │                                │
  │ 创建房间 + getLocalStream()    │
  │ createOffer() → SDP            │
  │ 生成 QR 码 (SDP)               │
  │                                │── 扫描 QR → 解码 Offer SDP
  │                                │── setRemoteDesc(offer)
  │                                │── getLocalStream()
  │                                │── createAnswer()
  │                                │── 生成 QR 码 (Answer SDP)
  │<── 扫描 QR → 解码 Answer SDP ──│
  │── setRemoteDesc(answer)        │
  │                                │
  │<══════ P2P SRTP 媒体流 ═══════>│
```

### 3.2 QR 数据格式

房间创建方 QR：`clearcall://room/{roomCode}` — 6 位房间号
SDP 交换 QR：直接包含 Base64 编码的 SDP（因 QR 容量有限，仅交换必要字段）

---

## 四、ICE 服务器配置

```dart
const iceServers = {
  'iceServers': [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
    {
      'urls': [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:443',
        'turn:openrelay.metered.ca:443?transport=tcp',
        'turns:openrelay.metered.ca:443?transport=tcp',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ],
  'iceTransportPolicy': 'all',
};
```

---

## 五、音视频规格

### 5.1 视频完整规格

#### 编码格式与分辨率档位

| 档位 | 分辨率 | 默认帧率 | 最高帧率 | 码率上限 | 适用网络 |
|---|---|---|---|---|---|
| 1080p | 1920×1080 | 30fps | 60fps | 4 Mbps | Wi-Fi（需手动开启） |
| 720p | 1280×720 | 30fps | 60fps | 2 Mbps | Wi-Fi 默认 |
| 480p | 854×480 | 24fps | 30fps | 1 Mbps | 4G/5G 默认 |
| 360p | 640×360 | 15fps | 24fps | 500 Kbps | 弱网 / 省流模式 |

#### 编码格式

| 编码 | 优先级 | 说明 |
|---|---|---|
| **H.264 (AVC)** | 🥇 默认 | 安卓 95%+ 硬编硬解支持 |
| **H.265 (HEVC)** | 🥈 可选 | 同等画质码率省 ~40%，需运行时检测 |
| **VP8** | 🥉 Fallback | H.264 不可用时的备选 |

#### 关键帧

| 参数 | 值 |
|---|---|
| 关键帧间隔（GOP） | **2 秒** |
| 关键帧请求（PLI） | 自动 |

### 5.2 音频完整规格

#### 编码格式选项

| 编码 | 选项名称 | 采样率 | 码率 | 说明 |
|---|---|---|---|---|
| **Opus** | 标准品质（默认） | 48kHz | **48 Kbps** | FaceTime 同级 |
| Opus | 高音质 | 48kHz | 64 Kbps | 音乐场景 |
| Opus | 省流 | 16kHz | 24 Kbps | 弱网保音频 |
| G.722 | 经典兼容 | 16kHz | 64 Kbps | 极老设备 |

#### 音频处理开关

| 功能 | 默认 | 说明 |
|---|---|---|
| 回声消除 (AEC) | ✅ 开 | 消除扬声器回声 |
| 噪声抑制 (ANS) | ✅ 开 | 消除背景噪声 |
| 自动增益 (AGC) | ✅ 开 | 自动调节麦克风音量 |

#### 音频路由

| 路由 | 触发方式 |
|---|---|
| 扬声器 | 默认 |
| 听筒 | 面板选择 |
| 蓝牙耳机 | 系统自动 |
| 有线耳机 | 系统自动 |

### 5.3 网络自适应策略

- **方式**：WebRTC 内置 GCC（Google Congestion Control）
- **自适应引擎**：QualityController（降级 6s 确认 / 升档 8s 确认 / 连续降级锁定 60s / 冷却 10s）

### 5.4 画质偏好（三档）

| 档位 | 策略 |
|---|---|
| **流畅优先**（默认） | 保帧率，优先降分辨率 |
| **均衡** | 等比下调 |
| **清晰优先** | 保分辨率，优先降帧率 |

### 5.5 网络质量指示

- 🟢 绿色（RTT < 100ms，丢包 < 2%）— 优秀
- 🟡 黄色（RTT 100-300ms，丢包 2-5%）— 一般
- 🔴 红色（RTT > 300ms 或丢包 > 5%）— 差

---

## 六、错误处理

| 错误场景 | 检测方式 | 处理 |
|---|---|---|
| STUN 超时 | ICE gathering > 30s | 提示"正在尝试中继连接…"，启用 TURN |
| ICE 连接失败 | `onIceConnectionFailed` | 提示"连接失败"，提供重试 |
| 远端无响应 | offer 后 60s 无 answer | 提示"对方无响应"，销毁房间 |
| 媒体权限拒绝 | `getUserMedia` 失败 | 引导到系统设置 |
| 房间不存在 | REST 404 / WS error | 提示"房间号无效或已过期" |
| WebSocket 断开 | onDone/onError | 自动提示切换到 QR 模式 |
