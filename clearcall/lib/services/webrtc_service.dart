import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

/// WebRTC 媒体配置
///
/// 所有音视频编码参数，对齐 07-api-protocol.md 规格。
class MediaConfig {
  final int videoWidth;
  final int videoHeight;
  final int videoFps;
  final String videoCodec;
  final int videoMaxBitrate;
  final int audioSampleRate;
  final String audioCodec;
  final int audioBitrate;
  final String qualityPreference;
  final bool aecEnabled;
  final bool ansEnabled;
  final bool agcEnabled;
  final bool frontFlashEnabled;

  const MediaConfig({
    this.videoWidth = 1280,
    this.videoHeight = 720,
    this.videoFps = 30,
    this.videoCodec = 'H264',
    this.videoMaxBitrate = 2500000,
    this.audioSampleRate = 48000,
    this.audioCodec = 'opus',
    this.audioBitrate = 48000,
    this.qualityPreference = 'smooth',
    this.aecEnabled = true,
    this.ansEnabled = true,
    this.agcEnabled = true,
    this.frontFlashEnabled = false,
  });
}

/// WebRTC 通话统计
class WebRTCStats {
  final int rtt;
  final double packetLoss;
  final int videoSendBitrate;
  final int videoRecvBitrate;
  final int audioSendBitrate;
  final int audioRecvBitrate;
  final int videoSendFps;
  final int videoRecvFps;

  const WebRTCStats({
    this.rtt = 0,
    this.packetLoss = 0.0,
    this.videoSendBitrate = 0,
    this.videoRecvBitrate = 0,
    this.audioSendBitrate = 0,
    this.audioRecvBitrate = 0,
    this.videoSendFps = 0,
    this.videoRecvFps = 0,
  });
}

/// WebRTC 服务
///
/// 封装 flutter_webrtc（0.10.x）的底层操作：
/// - 本地媒体流采集（摄像头 + 麦克风）
/// - PeerConnection 创建、SDP 协商、ICE 候选交换
/// - 远端媒体流接收和渲染
/// - 通话质量统计
class WebRTCService {
  final Logger _log = Logger('WebRTCService');

  /// ICE 服务器配置
  final List<Map<String, dynamic>> _iceServers;

  /// 媒体配置
  final MediaConfig _config;

  /// 当前 PeerConnection
  RTCPeerConnection? _peerConnection;

  /// 本地媒体流
  MediaStream? _localStream;

  /// 远端视频渲染器
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  /// 本地视频渲染器
  RTCVideoRenderer? _localRenderer;

  /// 通话统计定时器
  Timer? _statsTimer;

  /// 远端流回调
  void Function(MediaStream stream, String participantId)? onRemoteStream;
  void Function(String participantId)? onRemoteStreamRemoved;

  /// 通话统计回调
  void Function(WebRTCStats stats)? onStatsUpdate;

  WebRTCService({
    required List<Map<String, dynamic>> iceServers,
    MediaConfig config = const MediaConfig(),
  })  : _iceServers = iceServers,
        _config = config;

  /// 默认 STUN/TURN 服务器
  static const defaultIceServers = [
    {
      'urls': 'stun:stun.l.google.com:19302',
    },
    {
      'urls': 'turn:openrelay.metered.ca:80',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];

  // ═══════════════════════════════════════════════════════════
  // 本地媒体
  // ═══════════════════════════════════════════════════════════

  /// 采集本地摄像头和麦克风流
  Future<MediaStream> getLocalStream() async {
    if (_localStream != null) return _localStream!;

    try {
      final mediaConstraints = <String, dynamic>{
        'audio': {
          'echoCancellation': _config.aecEnabled,
          'noiseSuppression': _config.ansEnabled,
          'autoGainControl': _config.agcEnabled,
        },
        'video': {
          'mandatory': {
            'minWidth': _config.videoWidth.toString(),
            'minHeight': _config.videoHeight.toString(),
            'maxWidth': _config.videoWidth.toString(),
            'maxHeight': _config.videoHeight.toString(),
            'minFrameRate': _config.videoFps.toString(),
            'maxFrameRate': _config.videoFps.toString(),
          },
          'facingMode': 'user',
        },
      };

      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _log.info('本地媒体流采集成功');
      return _localStream!;
    } catch (e) {
      _log.severe('本地媒体流采集失败', e);
      rethrow;
    }
  }

  /// 初始化本地视频渲染器
  Future<void> initLocalRenderer() async {
    _localRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();
  }

  /// 将本地流绑定到渲染器
  void attachLocalStream() {
    if (_localStream != null && _localRenderer != null) {
      _localRenderer!.srcObject = _localStream;
    }
  }

  RTCVideoRenderer? get localRenderer => _localRenderer;

  /// 开关摄像头
  void toggleCamera(bool enabled) {
    if (_localStream == null) return;
    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      videoTrack.enabled = enabled;
      _log.info('摄像头${enabled ? "已开启" : "已关闭"}');
    }
  }

  /// 开关麦克风
  void toggleMicrophone(bool enabled) {
    if (_localStream == null) return;
    final audioTrack = _localStream!.getAudioTracks().firstOrNull;
    if (audioTrack != null) {
      audioTrack.enabled = enabled;
      _log.info('麦克风${enabled ? "已开启" : "已关闭"}');
    }
  }

  /// 切换前后摄像头
  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      try {
        await Helper.switchCamera(videoTrack);
        _log.info('摄像头已翻转');
      } catch (e) {
        _log.warning('摄像头翻转失败: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PeerConnection
  // ═══════════════════════════════════════════════════════════

  /// 创建并初始化 PeerConnection
  Future<RTCPeerConnection> initPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration, {});
    _log.info('PeerConnection 创建成功');
    return _peerConnection!;
  }

  /// 添加本地流到 PeerConnection
  Future<void> addLocalStreamToPeer() async {
    if (_localStream == null || _peerConnection == null) return;

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
    _log.info('本地流已添加到 PeerConnection');
  }

  /// 创建 SDP Offer
  Future<RTCSessionDescription> createOffer() async {
    if (_peerConnection == null) {
      throw StateError('PeerConnection 未创建');
    }

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(offer);
    _log.info('SDP Offer 创建成功');
    return offer;
  }

  /// 创建 SDP Answer
  Future<RTCSessionDescription> createAnswer() async {
    if (_peerConnection == null) {
      throw StateError('PeerConnection 未创建');
    }

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(answer);
    _log.info('SDP Answer 创建成功');
    return answer;
  }

  /// 设置远端 SDP
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (_peerConnection == null) {
      throw StateError('PeerConnection 未创建');
    }

    await _peerConnection!.setRemoteDescription(description);
    _log.info('远端 SDP 已设置: ${description.type}');
  }

  /// 添加 ICE Candidate
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) {
      throw StateError('PeerConnection 未创建');
    }

    await _peerConnection!.addCandidate(candidate);
  }

  // ═══════════════════════════════════════════════════════════
  // 远端媒体
  // ═══════════════════════════════════════════════════════════

  /// 获取或创建远端视频渲染器
  Future<RTCVideoRenderer> getRemoteRenderer(String participantId) async {
    if (_remoteRenderers.containsKey(participantId)) {
      return _remoteRenderers[participantId]!;
    }

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _remoteRenderers[participantId] = renderer;
    return renderer;
  }

  RTCVideoRenderer? getRemoteRendererSync(String participantId) {
    return _remoteRenderers[participantId];
  }

  void removeRemoteRenderer(String participantId) {
    final renderer = _remoteRenderers.remove(participantId);
    renderer?.srcObject = null;
    renderer?.dispose();
  }

  /// 设置 PeerConnection 事件监听
  void setupPeerConnectionListeners({
    required void Function(RTCIceCandidate candidate) onIceCandidate,
    required void Function(MediaStream stream) onAddStream,
    required void Function(MediaStream stream) onRemoveStream,
    void Function(RTCIceConnectionState state)? onIceConnectionState,
  }) {
    if (_peerConnection == null) return;

    _peerConnection!.onIceCandidate = (candidate) {
      onIceCandidate(candidate);
    };

    _peerConnection!.onAddStream = (stream) {
      _log.info('收到远端流: ${stream.id}');
      onAddStream(stream);
    };

    _peerConnection!.onRemoveStream = (stream) {
      _log.info('远端流移除: ${stream.id}');
      onRemoveStream(stream);
    };

    if (onIceConnectionState != null) {
      _peerConnection!.onIceConnectionState = (state) {
        _log.info('ICE 连接状态: $state');
        onIceConnectionState(state);
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 通话统计
  // ═══════════════════════════════════════════════════════════

  /// 开始收集通话统计（每 2 秒）
  void startStatsCollection() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peerConnection == null) return;

      try {
        final stats = await _peerConnection!.getStats();
        int totalRtt = 0;
        int rttCount = 0;

        for (final report in stats) {
          if (report.type == 'candidate-pair') {
            final rtt = report.values['currentRoundTripTime'];
            if (rtt != null) {
              totalRtt += ((rtt as double) * 1000).toInt();
              rttCount++;
            }
          }
        }

        final avgRtt = rttCount > 0 ? (totalRtt ~/ rttCount) : 0;
        onStatsUpdate?.call(WebRTCStats(rtt: avgRtt));
      } catch (e) {
        _log.warning('获取通话统计失败: $e');
      }
    });
  }

  /// 停止通话统计收集
  void stopStatsCollection() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  // ═══════════════════════════════════════════════════════════
  // 扬声器控制
  // ═══════════════════════════════════════════════════════════

  /// 切换扬声器模式
  Future<void> enableSpeakerphone(bool enabled) async {
    try {
      await Helper.setSpeakerphoneOn(enabled);
      _log.info('扬声器${enabled ? "已开启" : "已关闭"}');
    } catch (e) {
      _log.warning('扬声器切换失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 资源释放
  // ═══════════════════════════════════════════════════════════

  /// 挂断，释放所有资源
  Future<void> hangUp() async {
    _log.info('释放 WebRTC 资源');

    stopStatsCollection();

    if (_peerConnection != null) {
      try {
        await _peerConnection!.close();
      } catch (e) {
        _log.warning('关闭 PeerConnection 失败: $e');
      }
      _peerConnection = null;
    }

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        try {
          await track.stop();
        } catch (e) {
          _log.warning('停止 track 失败: $e');
        }
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    _localRenderer?.srcObject = null;
    _localRenderer?.dispose();
    _localRenderer = null;

    for (final entry in _remoteRenderers.entries) {
      entry.value.srcObject = null;
      entry.value.dispose();
    }
    _remoteRenderers.clear();
  }
}
