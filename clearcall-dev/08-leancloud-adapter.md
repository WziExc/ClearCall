# 08 — Leancloud 适配器规范

> **目的**：为国内用户提供 Firebase 的替代信令方案。  
> **原则**：与 Firebase 实现共享同一套 `SignalingService` 抽象接口，上层业务代码无需修改。

---

## 一、Leancloud 简介

| 项目 | 说明 |
|---|---|
| 产品 | Leancloud 开发版（免费） |
| 用途 | 替代 Firebase Realtime Database 做信令 |
| 优势 | 国内网络稳定，无需 Google Play 服务 |
| 限制 | 免费版 API 调用 3 万次/天，并发连接 500 |
| SDK | `leancloud_official_plugin` 或直接调 REST API |

---

## 二、Leancloud 数据模型映射

### Firebase → Leancloud 对应关系

| Firebase | Leancloud | 说明 |
|---|---|---|
| Realtime Database | Leancloud 云引擎（LiveQuery） 或 REST API | 实时数据同步 |
| `/rooms/{roomId}/` | `Room` Class（objectId = roomId） | 房间信息 |
| `/users/{uid}/` | `_User` 表 或自定义 `UserProfile` Class | 用户公开信息 |
| `/calls/{uid}/` | `Call` Class | 呼叫信令 |
| `/friendRequests/{uid}/` | `FriendRequest` Class | 好友申请 |
| Anonymous Auth | Leancloud 匿名登录 | 生成 sessionToken |
| FCM | 无需替代（国内不用 FCM 推送） | 国内用户来信通知依赖 App 前台或系统级权限 |

### Class 设计

#### Room
```json
{
  "roomId": "824917",
  "creatorId": "a1b2c3d4e5f6",
  "status": "waiting",
  "participants": ["a1b2c3d4e5f6", "b2c3d4e5f6a1"],
  "signals": {
    "a1b2c3d4e5f6": {
      "sdp": "{...}",
      "candidates": ["...", "..."]
    }
  },
  "createdAt": "2026-06-08T12:00:00Z",
  "updatedAt": "2026-06-08T12:01:00Z"
}
```

#### UserProfile
```json
{
  "uid": "a1b2c3d4e5f6",
  "nickname": "张三",
  "status": "online",
  "lastSeen": "2026-06-08T12:00:00Z",
  "friends": ["b2c3d4e5f6a1"]
}
```

#### CallSignal
```json
{
  "targetUid": "b2c3d4e5f6a1",
  "callerUid": "a1b2c3d4e5f6",
  "callerName": "张三",
  "status": "ringing",
  "createdAt": "2026-06-08T12:00:00Z"
}
```

---

## 三、实时通知方案

Firebase Realtime Database 的实时监听能力在 Leancloud 需要替代方案：

### 方案 A：LiveQuery（推荐）
- Leancloud 的 LiveQuery 提供实时数据变更推送
- 房间信令变化、好友请求变更、在线状态变更均通过 LiveQuery 监听
- 限制：同一客户端最多订阅 5 个 LiveQuery

### 方案 B：轮询 + 推送（降级方案）
- 当 LiveQuery 不可用时，退化为 REST API 定时轮询（间隔 3 秒）
- 呼叫信令使用更高频率轮询（1 秒）

---

## 四、Leancloud 匿名登录

```dart
// 首次启动自动匿名登录
await Leancloud.initialize(
  appId: 'YOUR_APP_ID',
  appKey: 'YOUR_APP_KEY',
  server: 'https://your-app-id.api.lncldglobal.com',
);

// 匿名登录（无需用户操作）
final user = await Leancloud.User.loginAnonymously();
final sessionToken = user.sessionToken; // 用于后续 API 请求认证
```

---

## 五、信令服务切换逻辑

```dart
class SignalingServiceFactory {
  static Future<SignalingService> create() async {
    // 1. 检查用户手动设置
    final prefs = await SharedPreferences.getInstance();
    final preferredService = prefs.getString('signaling_service');

    if (preferredService == 'leancloud') {
      return LeancloudSignaling();
    }
    if (preferredService == 'firebase') {
      return FirebaseSignaling();
    }

    // 2. 自动检测：先尝试 Firebase
    final firebase = FirebaseSignaling();
    if (await firebase.isAvailable()) {
      return firebase;
    }

    // 3. Firebase 不可用 → 降级到 Leancloud
    final leancloud = LeancloudSignaling();
    if (await leancloud.isAvailable()) {
      return leancloud;
    }

    // 4. 两者皆不可用 → 仅本地模式（仅房间号通话可用，无好友系统）
    throw SignalingUnavailableException('信令服务不可用');
  }
}
```

---

## 六、优先级与实施策略

| 阶段 | Firebase | Leancloud |
|---|---|---|
| 阶段 1-5 | ✅ 主实现 | ❌ 暂不实现 |
| 阶段 6（后续迭代） | ✅ 已上线 | ✅ 适配器实现 |

**理由**：
1. 优先保证核心功能在 Firebase 上稳定运行
2. Firebase 有更成熟的 Flutter 生态和文档
3. Leancloud 适配器在 Firebase 版本稳定后再实现
4. 两套方案共享抽象接口，后期切换成本极低

---

## 七、国内用户特殊考虑

### 推送替代方案
- 国内无法使用 FCM，需集成厂商推送（华为 HMS Push / 小米 MiPush / OPPO Push 等）
- 可统一封装为 `PushService` 抽象接口
- 优先实现"App 前台接收呼叫"（不依赖推送）

### 网络检测优化
- 首次启动测试 `firebaseio.com` 连通性
- 超时 3 秒 → 判定不可用 → 提示用户切换 Leancloud
- 后续可在设置中手动切换
