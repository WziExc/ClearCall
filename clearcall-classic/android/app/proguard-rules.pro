# ClearCall — ProGuard 混淆规则（阶段5-5.12 优化）
# ═══════════════════════════════════════════════════════════
# 通用优化
# ═══════════════════════════════════════════════════════════
-optimizationpasses 5
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-verbose

# ═══════════════════════════════════════════════════════════
# Flutter（保持所有 Flutter 类不被混淆）
# ═══════════════════════════════════════════════════════════
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ═══════════════════════════════════════════════════════════
# WebRTC（flutter_webrtc）
# ═══════════════════════════════════════════════════════════
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# ═══════════════════════════════════════════════════════════
# Firebase（保持序列化类）
# ═══════════════════════════════════════════════════════════
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keepattributes Signature
-keepattributes *Annotation*

# ═══════════════════════════════════════════════════════════
# sqflite
# ═══════════════════════════════════════════════════════════
-keep class com.tekartik.sqflite.** { *; }

# ═══════════════════════════════════════════════════════════
# 第三方库
# ═══════════════════════════════════════════════════════════
# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }
# uuid
-keep class com.github.uuid.** { *; }
# mobile_scanner
-keep class dev.steenbakker.mobile_scanner.** { *; }
