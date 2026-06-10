# ClearCall — ProGuard 混淆规则

# 通用优化
-optimizationpasses 5
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-verbose

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# WebRTC
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# 第三方库
-keep class com.baseflow.permissionhandler.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }

# 通用保持
-keepattributes Signature
-keepattributes *Annotation*

# Google Play Core（Flutter 引用但未使用，忽略缺失类）
-dontwarn com.google.android.play.core.**
