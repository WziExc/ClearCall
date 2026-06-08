# Firebase 配置指南

## 1. 创建 Firebase 项目

1. 前往 [Firebase Console](https://console.firebase.google.com/)
2. 点击 **添加项目** → 输入项目名称 "ClearCall"
3. 选择是否启用 Google Analytics（可选，建议关闭以减少包体积）
4. 创建项目

## 2. 添加 Android 应用

1. 在项目概览中点击 **Android 图标** 添加应用
2. 包名：`com.clearcall.app`
3. 调试 SHA-1：（可选，用于动态链接/手机验证，本 App 不需要）
4. 下载 `google-services.json`
5. 将文件复制到 `android/app/` 目录

## 3. 启用服务

在 Firebase Console 中启用以下服务：

### Realtime Database
1. 左侧菜单 → **Realtime Database** → **创建数据库**
2. 选择位置（亚洲建议 `asia-southeast1`）
3. **以测试模式启动**，然后将 `firebase/database.rules.json` 的内容复制到 **规则** 标签
4. 点击 **发布**

### Authentication
1. 左侧菜单 → **Authentication** → **开始**
2. **登录方式** → 启用 **匿名** 登录
3. 不需要启用其他方式

### Cloud Messaging（阶段 3 需要）
1. 左侧菜单 → **Cloud Messaging**
2. 稍后配置，阶段 3 才需要 FCM 推送

## 4. 验证配置

在项目目录运行：
```bash
flutter pub get
flutter run
```

如果看到 Firebase 匿名登录成功的日志，说明配置正确。

## 5. 免费配额

| 服务 | 免费配额 | ClearCall 预估 |
|---|---|---|
| Realtime DB 并发 | 100 | < 50 |
| Realtime DB 存储 | 1 GB | < 10 MB |
| Realtime DB 下载 | 10 GB/月 | ~18 MB |
| Auth 匿名 | 无限 | — |

均在免费配额内。
