package com.clearcall.app

import io.flutter.embedding.android.FlutterActivity

/// ClearCall 主 Activity
///
/// 使用 Flutter 默认的 FlutterActivity，
/// 支持画中画（PiP）和全屏视频通话。
class MainActivity : FlutterActivity() {
    // PiP 和全屏配置在 AndroidManifest.xml 中声明
    // 后续阶段通过 MethodChannel 控制 PiP 行为
}
