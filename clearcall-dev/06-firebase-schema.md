# 06 — Firebase Realtime Database 数据 Schema

> **数据库**：Firebase Realtime Database（NoSQL JSON 树）  
> **安全规则**：仅允许已认证的写入（基于 uid + 验证 token）

---

## 数据结构总览

```
firebase-realtime-db/
├── rooms/              # 临时房间（信令交换）
│   └── {roomId}/       # 6 位数字房间号
│       ├── creator/    # 创建者 uid
│       ├── createdAt/  # 创建时间戳
│       ├── status/     # waiting | active | closed
│       └── participants/
│           └── {uid}/
│               ├── joinedAt/
│               ├── sdp/          # SDP offer/answer
│               └── candidates/   # ICE candidates
│                   └── {index}/
│                       ├── candidate/
│                       └── sdpMid/
│
├── users/              # 用户公开信息
│   └── {uid}/
│       ├── nickname/
│       ├── status/     # online | offline | in-call
│       ├── lastSeen/   # 最后在线时间戳
│       └── friends/
│           └── {friendUid}/ true  # 好友关系的单向记录
│
├── calls/              # 呼叫信令
│   └── {targetUid}/    # 被叫方 uid
│       ├── callerUid/
│       ├── callerName/
│       ├── callType/   # video
│       ├── timestamp/
│       └── status/     # ringing | answered | rejected | timeout
│
└── friendRequests/     # 好友申请
    └── {targetUid}/    # 被申请方 uid
        └── from/
            └── {requesterUid}/
                ├── nickname/
                ├── token/       # 一次性验证码
                ├── timestamp/
                └── status/     # pending | accepted | rejected
```

---

## 节点详细说明

### /rooms/{roomId}/

```json
{
  "creator": "a1b2c3d4e5f6",
  "createdAt": 1717800000000,
  "status": "waiting",
  "participants": {
    "a1b2c3d4e5f6": {
      "joinedAt": 1717800001000,
      "sdp": {
        "type": "offer",
        "sdp": "v=0\r\no=- ..."
      },
      "candidates": {
        "0": {
          "candidate": "candidate:...",
          "sdpMid": "0",
          "sdpMLineIndex": 0
        }
      }
    },
    "b2c3d4e5f6a1": {
      "joinedAt": 1717800005000,
      "sdp": {
        "type": "answer",
        "sdp": "v=0\r\no=- ..."
      },
      "candidates": {}
    }
  }
}
```

**规则**：
- 房间创建者离开后，如果房间仍有其他人 → 随机迁移 creator
- 所有人离开后 → status 改为 closed → 30 分钟后 Firebase Cloud Function 清理（可选，或用客户端删除）
- 最多 3 个参与者（客户端强制检查），超出时返回 `{"error": "room_full", "max": 3}`
- 创建后 5 分钟内无其他参与者加入 → 客户端自动关闭房间，status 改为 closed
- 3 人 Mesh 组网时，每个参与者与另外两人分别交换 SDP 和 ICE（不共享连接）

### /users/{uid}/

```json
{
  "nickname": "张三",
  "status": "online",
  "lastSeen": 1717800000000,
  "friends": {
    "b2c3d4e5f6a1": true,
    "c3d4e5f6a1b2": true
  }
}
```

**规则**：
- uid 为本地生成的全局唯一 ID（16 位十六进制）
- status 由客户端写入，使用 `onDisconnect` 自动删除/更新
- friends 存储好友 uid → true 的映射，用于双向查找在线状态
- 不存储真实个人身份信息

**onDisconnect 配置**（客户端设置）：
```dart
final userRef = db.ref('users/$uid');
userRef.child('status').onDisconnect.set('offline');
userRef.child('lastSeen').onDisconnect.set(ServerValue.timestamp);
```

### /calls/{targetUid}/

```json
{
  "callerUid": "a1b2c3d4e5f6",
  "callerName": "张三",
  "callType": "video",
  "timestamp": 1717800000000,
  "status": "ringing"
}
```

**规则**：
- 被叫方监听 `/calls/{自己的UID}/` 节点变化
- 被叫接听 → 修改 status 为 `answered`
- 被叫拒绝 → 修改 status 为 `rejected`
- 主叫超时（60s）→ 主叫端删除该节点
- 通话结束 → 任意一方删除该节点

**呼叫流程**：
```
主叫方写 /calls/{被叫UID}/ ──→ 被叫方监听到变化
被叫方接听 → 更新 status=answered → 主叫方监听到 → 开始 WebRTC 连接
被叫方拒绝 → 更新 status=rejected → 主叫方监听到 → 显示"对方忙"
```

### /friendRequests/{targetUid}/from/{requesterUid}/

```json
{
  "nickname": "李四",
  "token": "a8f3c1e9",
  "timestamp": 1717800000000,
  "status": "pending"
}
```

**规则**：
- token 为 8 位随机十六进制，由申请方生成并嵌入二维码
- 被申请方监听到新请求 → 弹出申请 UI
- 同意 → status 改为 `accepted` → 双方写入 friends 节点
- 拒绝 → status 改为 `rejected` → 可被清理

---

## Firebase 安全规则

```json
{
  "rules": {
    "rooms": {
      "$roomId": {
        ".read": "auth != null",
        ".write": "auth != null",
        "participants": {
          "$uid": {
            ".write": "$uid === auth.uid"
          }
        }
      }
    },
    "users": {
      "$uid": {
        ".read": "auth != null",
        ".write": "$uid === auth.uid",
        "friends": {
          "$friendUid": {
            ".write": "$uid === auth.uid"
          }
        }
      }
    },
    "calls": {
      "$uid": {
        ".read": "auth != null",
        ".write": "auth != null"
      }
    },
    "friendRequests": {
      "$uid": {
        ".read": "auth != null",
        ".write": "auth != null"
      }
    }
  }
}
```

### 匿名认证（Firebase Anonymous Auth）
- 使用 Firebase Anonymous Auth 生成认证 token（不是账号，无需用户操作）
- 认证后 `auth.uid` = 用户的匿名 UID
- 不与任何个人信息绑定

---

## 数据量估算

| 节点 | 单次大小 | 并发量 | 月流量 |
|---|---|---|---|
| /rooms/{roomId} | ~10KB（含 SDP） | 50 房间/天 | ~15MB |
| /users/{uid} | ~500B | 1000 用户 | ~1.5MB |
| /calls/{uid} | ~200B | 200 次/天 | ~1.2MB |
| /friendRequests | ~300B | 50 次/天 | ~0.5MB |
| **总计** | | | **~18MB/月** |

> Firebase 免费配额：10GB/月下载、1GB 存储、100 并发连接  
> 结论：远在免费配额内
