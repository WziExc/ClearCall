# 05 — 编码规范

> **语言**：Dart（Flutter）  
> **原则**：一致、可读、可维护。注释用中文。

---

## 一、命名规范

### 1.1 文件命名
- Dart 文件：`snake_case.dart`
- 测试文件：`xxx_test.dart`（放在 `test/` 对应目录）
- 资源文件：`snake_case.png`

```
// ✅ 正确
call_manager.dart
webrtc_service.dart
friend_list_item.dart

// ❌ 错误
CallManager.dart
webrtc-service.dart
friendListItem.dart
```

### 1.2 类/枚举/类型
- `UpperCamelCase`
```dart
class CallManager {}
enum OnlineStatus { online, offline, inCall }
```

### 1.3 变量/函数/方法
- `lowerCamelCase`
```dart
final isMuted = false;
void startCall() {}
```

### 1.4 常量
- `lowerCamelCase`（Dart 风格）或 `SCREAMING_SNAKE_CASE`（团队一致即可）
- 本项目统一用 `lowerCamelCase`
```dart
const primaryColor = Color(0xFF007AFF);
const maxParticipants = 3;
```

### 1.5 私有成员
- 前缀下划线 `_`
```dart
class CallScreen extends StatefulWidget {
  final _isDragging = false;    // 私有变量
  void _onHangUp() {}            // 私有方法
}
```

---

## 二、目录结构

```
lib/
├── main.dart                    # 入口，只做初始化
├── app.dart                     # MaterialApp 配置
├── models/                      # 纯数据类，无业务逻辑
├── services/                    # 业务服务，单例
│   └── signaling/               # 信令抽象层
├── providers/                   # Riverpod Provider 定义
├── screens/                     # 页面（每个文件一个页面）
├── widgets/                     # 可复用 UI 组件（无业务逻辑）
└── utils/                       # 纯函数工具
```

规则：
- `models/` 中的类只能有字段和 `fromJson`/`toJson`/`copyWith`，不允许有业务逻辑
- `services/` 中的类处理所有业务逻辑和外部 API 调用
- `screens/` 中的页面只做 UI 组合，不直接调 Firebase 或其他外部服务
- `widgets/` 中的组件纯展示，数据通过构造函数传入

---

## 三、代码风格

### 3.1 缩进与行长
- 2 空格缩进
- 最大行长 120 字符
- 使用 Dart 格式化工具（`dart format lib/`）

### 3.2 导入顺序
1. Dart SDK 库
2. Flutter SDK 库
3. 第三方包
4. 项目内文件

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clearcall/models/user.dart';
import 'package:clearcall/services/call_manager.dart';
```

### 3.3 Widget 结构
- 每个 Widget 类不超过 300 行
- 复杂 Widget 拆分为多个小 Widget 或私有方法
- Build 方法不超过 50 行
- 条件渲染用 `if` 而非三元嵌套

```dart
// ✅ 正确
Widget build(BuildContext context) {
  return Column(
    children: [
      if (isOnline) _buildOnlineIndicator(),
      if (isInCall) _buildCallStatus(),
      _buildMainContent(),
    ],
  );
}

// ❌ 避免
Widget build(BuildContext context) {
  return isOnline ? (isInCall ? widgetA : widgetB) : widgetC;
}
```

---

## 四、注释规范

- 公共 API/类/方法必须写文档注释 `///`
- 复杂逻辑写行内中文注释
- TODO 标记：`// TODO(用户名): 描述`

```dart
/// 通话状态管理器
///
/// 管理整个通话生命周期：空闲 → 等待连接 → 通话中 → 结束
/// 使用单例模式，确保全局只有一个通话实例。
class CallManager {
  /// 发起新的视频通话
  ///
  /// [targetUserId] 目标用户的本机唯一 ID
  /// 返回通话会话对象，失败时抛出 [CallException]
  Future<CallSession> startCall(String targetUserId) async {
    // 先检查当前是否已在通话中
    if (_currentSession != null) {
      throw CallException('已在通话中，请先挂断当前通话');
    }
    // TODO(dev): 添加超时处理逻辑
  }
}
```

---

## 五、状态管理（Riverpod）

- 全局状态用 `StateNotifierProvider`
- 简单状态用 `StateProvider`
- 服务类用 `Provider`（只暴露实例）

```dart
// 通话状态
final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  return CallNotifier(ref.read(signalingProvider));
});

// 好友列表
final friendsProvider = StateNotifierProvider<FriendsNotifier, List<Friend>>((ref) {
  return FriendsNotifier(ref.read(signalingProvider));
});
```

---

## 六、错误处理

```dart
// 所有异步操作必须有 try-catch
Future<void> connectToRoom(String roomId) async {
  try {
    await signalingService.joinRoom(roomId, userId);
  } on RoomNotFoundException {
    // 房间不存在 → 提示用户
    showError('房间号无效或已过期');
  } on NetworkException {
    // 网络错误 → 重试或提示
    showError('网络连接失败，请检查网络后重试');
  } catch (e) {
    // 未知错误 → 记录并提示
    log.severe('连接房间失败', e);
    showError('连接失败，请稍后重试');
  }
}
```

---

## 七、测试规范

- 文件位置：`test/单元测试路径/`，与被测文件路径对应
- 命名：`被测文件名_test.dart`
- 每个服务类必须有对应的单元测试
- 使用 `mockito` 或 `mocktail` 做依赖 Mock
- 关键 UI 流程有 Widget 测试

```dart
// test/services/call_manager_test.dart
void main() {
  group('CallManager', () {
    late CallManager callManager;
    late MockSignalingService mockSignaling;

    setUp(() {
      mockSignaling = MockSignalingService();
      callManager = CallManager(mockSignaling);
    });

    test('挂断当前通话后状态应变为空闲', () async {
      await callManager.startCall('user123');
      await callManager.hangUp();
      expect(callManager.state, equals(CallState.idle));
    });
  });
}
```

---

## 八、Git 提交规范

- 提交信息用中文
- 格式：`[阶段X] 简短描述`

```
[阶段1] 初始化 Flutter 项目并配置依赖
[阶段1] 实现磨砂卡片 GlassCard 组件
[阶段2] 实现 Firebase 创建房间信令流程
[阶段3] 实现好友申请弹窗 UI
```
