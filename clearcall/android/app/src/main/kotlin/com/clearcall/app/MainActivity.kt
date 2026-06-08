package com.clearcall.app

import android.app.PictureInPictureParams
import android.content.Context
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// ClearCall 主 Activity
///
/// 支持画中画（PiP）、蓝牙音频和全屏视频通话。
/// 通过 MethodChannel 与 Flutter 通信控制原生功能。
class MainActivity : FlutterActivity() {
    private val PIP_CHANNEL = "com.clearcall/pip"
    private val AUDIO_CHANNEL = "com.clearcall/audio"

    private var ringtonePlayer: MediaPlayer? = null
    private var ringtoneUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ─── 画中画（PiP）Channel ─────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPiP" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(9, 16))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", "进入画中画失败: ${e.message}", null)
                        }
                    } else {
                        result.error("UNSUPPORTED", "画中画需要 Android 8.0+", null)
                    }
                }
                "isInPiP" -> {
                    result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
                            && isInPictureInPictureMode
                    )
                }
                "isPiPSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }
                else -> result.notImplemented()
            }
        }

        // ─── 音频 Channel（设备检测 + 铃声音效）─────────────────
        ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableAudioDevices" -> {
                    val devices = mutableListOf<String>()
                    devices.add("earpiece")
                    devices.add("speaker")

                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        if (audioManager.isBluetoothScoAvailableOffCall || audioManager.isBluetoothA2dpOn) {
                            devices.add("bluetooth")
                        }
                    } catch (e: Exception) {
                        // 蓝牙检测失败也不阻塞
                    }

                    result.success(devices)
                }
                "startRinging" -> {
                    try {
                        stopRingtone()
                        ringtonePlayer = MediaPlayer().apply {
                            setDataSource(this@MainActivity, ringtoneUri!!)
                            isLooping = true
                            setAudioStreamType(AudioManager.STREAM_RING)
                            prepare()
                            start()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RINGTONE_ERROR", "铃声播放失败: ${e.message}", null)
                    }
                }
                "stopRinging" -> {
                    stopRingtone()
                    result.success(true)
                }
                "playHangupSound" -> {
                    // 使用系统通知音效作为挂断音
                    try {
                        val notificationUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        val player = MediaPlayer().apply {
                            setDataSource(this@MainActivity, notificationUri)
                            setAudioStreamType(AudioManager.STREAM_NOTIFICATION)
                            setOnCompletionListener { it.release() }
                            prepare()
                            start()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "playConnectSound" -> {
                    try {
                        val notificationUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        val player = MediaPlayer().apply {
                            setDataSource(this@MainActivity, notificationUri)
                            setAudioStreamType(AudioManager.STREAM_NOTIFICATION)
                            setOnCompletionListener { it.release() }
                            prepare()
                            start()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "isOnMobileData" -> {
                    try {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        val network = cm.activeNetwork
                        val caps = cm.getNetworkCapabilities(network)
                        val isMobile = caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
                        result.success(isMobile)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun stopRingtone() {
        ringtonePlayer?.apply {
            if (isPlaying) stop()
            release()
        }
        ringtonePlayer = null
    }

    override fun onDestroy() {
        stopRingtone()
        super.onDestroy()
    }
}
