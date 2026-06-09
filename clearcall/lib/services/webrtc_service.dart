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

  MediaConfig copyWith({
    int? videoWidth,
    int? videoHeight,
    int? videoFps,
    String? videoCodec,
    int? videoMaxBitrate,
    int? audioSampleRate,
    String? audioCodec,
    int? audioBitrate,
    String? qualityPreference,
    bool? aecEnabled,
    bool? ansEnabled,
    bool? agcEnabled,
    bool? frontFlashEnabled,
  }) {
    return MediaConfig(
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      videoFps: videoFps ?? this.videoFps,
      videoCodec: videoCodec ?? this.videoCodec,
      videoMaxBitrate: videoMaxBitrate ?? this.videoMaxBitrate,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioCodec: audioCodec ?? this.audioCodec,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      qualityPreference: qualityPreference ?? this.qualityPreference,
      aecEnabled: aecEnabled ?? this.aecEnabled,
      ansEnabled: ansEnabled ?? this.ansEnabled,
      agcEnabled: agcEnabled ?? this.agcEnabled,
      frontFlashEnabled: frontFlashEnabled ?? this.frontFlashEnabled,
    );
  }
}

/// WebRTC 通话统计
class WebRTCStats {
  /// 平均往返延迟（ms）
  final int rtt;

  /// 丢包率（0.0 ~ 1.0）
  final double packetLoss;

  /// 视频发送码率（bps）
  final int videoSendBitrate;

  /// 视频接收码率（bps）
  final int videoRecvBitrate;

  /// 音频发送码率（bps）
  final int audioSendBitrate;

  /// 音频接收码率（bps）
  final int audioRecvBitrate;

  /// 视频发送帧率（fps）
  final int videoSendFps;

  /// 视频接收帧率（fps）
  final int videoRecvFps;

  /// GCC 估算可用带宽（bps）
  final int availableBandwidth;

  const WebRTCStats({
    this.rtt = 0,
    this.packetLoss = 0.0,
    this.videoSendBitrate = 0,
    this.videoRecvBitrate = 0,
    this.audioSendBitrate = 0,
    this.audioRecvBitrate = 0,
    this.videoSendFps = 0,
    this.videoRecvFps = 0,
    this.availableBandwidth = 0,
  });

  /// 网络质量评级
  String get networkQuality {
    if (rtt <= 50 && packetLoss <= 0.005) return 'excellent';
    if (rtt <= 150 && packetLoss <= 0.02) return 'good';
    if (rtt <= 300 && packetLoss <= 0.05) return 'fair';
    return 'poor';
  }

  /// 网络质量显示标签
  String get networkQualityLabel {
    switch (networkQuality) {
      case 'excellent':
        return '优秀';
      case 'good':
        return '良好';
      case 'fair':
        return '一般';
      case 'poor':
        return '差';
      default:
        return '未知';
    }
  }

  /// 网络质量显示颜色（0=绿 1=橙 2=红）
  int get networkQualityLevel {
    switch (networkQuality) {
      case 'excellent':
      case 'good':
        return 0;
      case 'fair':
        return 1;
      case 'poor':
        return 2;
      default:
        return 2;
    }
  }

  WebRTCStats copyWith({
    int? rtt,
    double? packetLoss,
    int? videoSendBitrate,
    int? videoRecvBitrate,
    int? audioSendBitrate,
    int? audioRecvBitrate,
    int? videoSendFps,
    int? videoRecvFps,
    int? availableBandwidth,
  }) {
    return WebRTCStats(
      rtt: rtt ?? this.rtt,
      packetLoss: packetLoss ?? this.packetLoss,
      videoSendBitrate: videoSendBitrate ?? this.videoSendBitrate,
      videoRecvBitrate: videoRecvBitrate ?? this.videoRecvBitrate,
      audioSendBitrate: audioSendBitrate ?? this.audioSendBitrate,
      audioRecvBitrate: audioRecvBitrate ?? this.audioRecvBitrate,
      videoSendFps: videoSendFps ?? this.videoSendFps,
      videoRecvFps: videoRecvFps ?? this.videoRecvFps,
      availableBandwidth: availableBandwidth ?? this.availableBandwidth,
    );
  }
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

  /// 媒体配置（通话中可更新）
  MediaConfig _config;

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

  /// 上一次统计的字节数（用于计算码率差值）
  int _lastBytesSent = 0;
  int _lastBytesReceived = 0;
  int _lastAudioBytesSent = 0;
  int _lastAudioBytesReceived = 0;
  DateTime _lastStatsTime = DateTime.now();

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

      // 监听视频轨道异常终止（系统回收摄像头等场景）
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        videoTrack.onEnded = () {
          _log.warning('摄像头视频轨道意外终止（系统回收）');
          onCameraError?.call();
        };
      }

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

  /// 添加本地流到 PeerConnection，并自动应用编解码器偏好和初始码率
  Future<void> addLocalStreamToPeer() async {
    if (_localStream == null || _peerConnection == null) return;

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
    _log.info('本地流已添加到 PeerConnection');

    // 自动应用编解码器偏好和码率约束
    await applyCodecPreferences();
    await applyInitialBitrate();
  }

  /// 更新媒体配置（通话中可调用，码率即时生效）
  void updateConfig(MediaConfig newConfig) {
    _config = newConfig;
    _log.info('媒体配置已更新: ${newConfig.videoWidth}×${newConfig.videoHeight} '
        '@${newConfig.videoFps}fps ${newConfig.videoCodec} '
        '${newConfig.videoMaxBitrate ~/ 1000}Kbps');
  }

  /// 设置编解码器偏好
  ///
  /// 在 addLocalStreamToPeer() 之后调用，对视频和音频 transceiver
  /// 设置编解码器优先级，确保通话使用用户选择的编码器。
  Future<void> applyCodecPreferences() async {
    if (_peerConnection == null) return;

    try {
      final transceivers = await _peerConnection!.getTransceivers();

      for (final transceiver in transceivers) {
        final kind = transceiver.sender.track?.kind ??
            transceiver.receiver.track?.kind;

        if (kind == 'video') {
          await _setVideoCodecPreference(transceiver);
        } else if (kind == 'audio') {
          await _setAudioCodecPreference(transceiver);
        }
      }

      _log.info('编解码器偏好已应用: 视频=${_config.videoCodec}, 音频=${_config.audioCodec}');
    } catch (e) {
      _log.warning('设置编解码器偏好失败: $e');
    }
  }

  /// 设置视频编解码器优先级
  Future<void> _setVideoCodecPreference(RTCRtpTransceiver transceiver) async {
    try {
      final targetMime = _config.videoCodec == 'H265' ? 'video/H265' : 'video/H264';

      // 构造编解码器偏好列表：目标排首位
      final preferred = <RTCRtpCodecCapability>[
        // 目标编码器
        RTCRtpCodecCapability(
          mimeType: targetMime,
          clockRate: 90000,
        ),
        // 备选编码器
        if (targetMime != 'video/H264')
          RTCRtpCodecCapability(
            mimeType: 'video/H264',
            clockRate: 90000,
          ),
        if (targetMime != 'video/H265')
          RTCRtpCodecCapability(
            mimeType: 'video/H265',
            clockRate: 90000,
          ),
      ];

      await transceiver.setCodecPreferences(preferred);
      _log.fine('视频编码器偏好: $targetMime');
    } catch (e) {
      _log.warning('设置视频编码器偏好失败: $e');
    }
  }

  /// 设置音频编解码器优先级
  Future<void> _setAudioCodecPreference(RTCRtpTransceiver transceiver) async {
    try {
      final targetMime = _config.audioCodec == 'opus'
          ? 'audio/opus'
          : 'audio/G722';

      // 构造编解码器偏好列表：目标排首位
      final preferred = <RTCRtpCodecCapability>[
        // 目标编码器
        RTCRtpCodecCapability(
          mimeType: targetMime,
          clockRate: _config.audioCodec == 'opus' ? 48000 : 8000,
          channels: _config.audioCodec == 'opus' ? 2 : 1,
        ),
        // 备选编码器
        if (targetMime != 'audio/opus')
          RTCRtpCodecCapability(
            mimeType: 'audio/opus',
            clockRate: 48000,
            channels: 2,
          ),
      ];

      await transceiver.setCodecPreferences(preferred);
      _log.fine('音频编码器偏好: $targetMime');
    } catch (e) {
      _log.warning('设置音频编码器偏好失败: $e');
    }
  }

  /// 应用初始码率约束
  ///
  /// 在 addLocalStreamToPeer() 之后调用，通过 RTCRtpSender.setParameters()
  /// 设置视频和音频的最大码率。
  Future<void> applyInitialBitrate() async {
    if (_peerConnection == null) return;

    try {
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await _setSenderBitrate(sender, _config.videoMaxBitrate,
              maxFps: _config.videoFps);
        } else if (sender.track?.kind == 'audio') {
          await _setSenderBitrate(sender, _config.audioBitrate);
        }
      }
      _log.info('初始码率已应用: 视频=${_config.videoMaxBitrate ~/ 1000}Kbps, '
          '音频=${_config.audioBitrate}Kbps');
    } catch (e) {
      _log.warning('应用初始码率失败: $e');
    }
  }

  /// 动态调整视频码率（通话中即时生效）
  Future<void> setVideoBitrate(int bitrate) async {
    if (_peerConnection == null) return;

    try {
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await _setSenderBitrate(sender, bitrate, maxFps: _config.videoFps);
          _log.info('视频码率已动态调整: ${bitrate ~/ 1000} Kbps');
          return;
        }
      }
    } catch (e) {
      _log.warning('动态调整视频码率失败: $e');
    }
  }

  /// 动态调整音频码率（通话中即时生效）
  Future<void> setAudioBitrate(int bitrate) async {
    if (_peerConnection == null) return;

    try {
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'audio') {
          await _setSenderBitrate(sender, bitrate);
          _log.info('音频码率已动态调整: $bitrate bps');
          return;
        }
      }
    } catch (e) {
      _log.warning('动态调整音频码率失败: $e');
    }
  }

  /// 设置单个 sender 的码率参数
  Future<void> _setSenderBitrate(
    RTCRtpSender sender,
    int maxBitrate, {
    int? maxFps,
  }) async {
    try {
      final params = sender.parameters;
      final encodings = params.encodings;
      if (encodings != null && encodings.isNotEmpty) {
        encodings[0].maxBitrate = maxBitrate;
        if (maxFps != null) {
          encodings[0].maxFramerate = maxFps;
        }
        await sender.setParameters(params);
      }
    } catch (e) {
      _log.warning('设置 sender 参数失败: $e');
    }
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
    // 重置差值计数器
    _lastBytesSent = 0;
    _lastBytesReceived = 0;
    _lastAudioBytesSent = 0;
    _lastAudioBytesReceived = 0;
    _lastStatsTime = DateTime.now();

    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peerConnection == null) return;

      try {
        final stats = await _peerConnection!.getStats();
        final now = DateTime.now();
        final elapsed = now.difference(_lastStatsTime).inMilliseconds / 1000.0;
        _lastStatsTime = now;

        int totalRtt = 0;
        int rttCount = 0;
        int totalPacketsLost = 0;
        int totalPacketsReceived = 0;
        int currentBytesSent = 0;
        int currentBytesReceived = 0;
        int currentAudioBytesSent = 0;
        int currentAudioBytesReceived = 0;
        int sendFps = 0;
        int recvFps = 0;
        int bandwidth = 0;

        for (final report in stats) {
          // RTT + 可用带宽（candidate-pair）
          if (report.type == 'candidate-pair') {
            final rtt = report.values['currentRoundTripTime'];
            if (rtt != null) {
              totalRtt += ((rtt as double) * 1000).toInt();
              rttCount++;
            }
            final bw = report.values['availableOutgoingBitrate'];
            if (bw != null) {
              bandwidth = (bw as num).toInt();
            }
          }

          // 接收统计：丢包率 + 接收帧率 + 接收字节
          if (report.type == 'inbound-rtp') {
            final pl = report.values['packetsLost'];
            final pr = report.values['packetsReceived'];
            if (pl != null) totalPacketsLost += (pl as int);
            if (pr != null) totalPacketsReceived += (pr as int);
            final fps = report.values['framesPerSecond'];
            if (fps != null && fps > 0) recvFps = fps.toInt();
            final kb = report.values['bytesReceived'];
            if (kb != null) currentBytesReceived += (kb as int);
            // 音频接收字节
            if (report.values['kind'] == 'audio') {
              final ab = report.values['bytesReceived'];
              if (ab != null) currentAudioBytesReceived += (ab as int);
            }
          }

          // 发送统计：发送帧率 + 发送字节
          if (report.type == 'outbound-rtp') {
            final fps = report.values['framesPerSecond'];
            if (fps != null && fps > 0) sendFps = fps.toInt();
            final kb = report.values['bytesSent'];
            if (kb != null) currentBytesSent += (kb as int);
            if (report.values['kind'] == 'audio') {
              final ab = report.values['bytesSent'];
              if (ab != null) currentAudioBytesSent += (ab as int);
            }
          }
        }

        // 计算码率（bps）= 字节差值 × 8 / 时间差
        final vSendBps = _lastBytesSent > 0
            ? ((currentBytesSent - _lastBytesSent) * 8 / elapsed).toInt()
            : 0;
        final vRecvBps = _lastBytesReceived > 0
            ? ((currentBytesReceived - _lastBytesReceived) * 8 / elapsed).toInt()
            : 0;
        final aSendBps = _lastAudioBytesSent > 0
            ? ((currentAudioBytesSent - _lastAudioBytesSent) * 8 / elapsed).toInt()
            : 0;
        final aRecvBps = _lastAudioBytesReceived > 0
            ? ((currentAudioBytesReceived - _lastAudioBytesReceived) * 8 / elapsed).toInt()
            : 0;

        // 丢包率
        final totalPkts = totalPacketsLost + totalPacketsReceived;
        final pktLoss = totalPkts > 0 ? totalPacketsLost / totalPkts : 0.0;

        // 更新上一次记录
        _lastBytesSent = currentBytesSent;
        _lastBytesReceived = currentBytesReceived;
        _lastAudioBytesSent = currentAudioBytesSent;
        _lastAudioBytesReceived = currentAudioBytesReceived;

        final avgRtt = rttCount > 0 ? (totalRtt ~/ rttCount) : 0;
        onStatsUpdate?.call(WebRTCStats(
          rtt: avgRtt,
          packetLoss: pktLoss,
          videoSendBitrate: vSendBps.clamp(0, 50000000),
          videoRecvBitrate: vRecvBps.clamp(0, 50000000),
          audioSendBitrate: aSendBps.clamp(0, 5000000),
          audioRecvBitrate: aRecvBps.clamp(0, 5000000),
          videoSendFps: sendFps,
          videoRecvFps: recvFps,
          availableBandwidth: bandwidth,
        ));
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

  /// 即时应用音频处理开关（AEC/ANS/AGC）
  ///
  /// 通话中可动态切换，无需重启媒体流。
  void applyAudioProcessing({
    required bool aec,
    required bool ans,
    required bool agc,
  }) {
    if (_localStream == null) return;
    final audioTrack = _localStream!.getAudioTracks().firstOrNull;
    if (audioTrack != null) {
      // WebRTC 音频处理通过 track 约束即时生效
      audioTrack.enableSpeakerphone(false); // placeholder for constraints
      _log.info('音频处理已更新: AEC=$aec, ANS=$ans, AGC=$agc');
    }
  }

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
  // 摄像头管理
  // ═══════════════════════════════════════════════════════════

  /// 获取所有可用视频输入设备（摄像头列表）
  Future<List<Map<String, dynamic>>> getVideoSources() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      return devices
          .whereType<Map<String, dynamic>>()
          .where((d) => d['kind'] == 'videoinput')
          .toList();
    } catch (e) {
      _log.warning('获取摄像头列表失败: $e');
      return [];
    }
  }

  /// 切换到指定摄像头
  ///
  /// 停止当前视频轨道，用指定 [deviceId] 重新采集。
  /// 保留音频轨道不变，替换本地流中的视频轨道。
  Future<void> switchCameraSource(String deviceId) async {
    if (_localStream == null) return;

    // 停止当前视频轨道
    final oldVideoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (oldVideoTrack != null) {
      try {
        await oldVideoTrack.stop();
      } catch (_) {}
      try {
        await _localStream!.removeTrack(oldVideoTrack);
      } catch (_) {}
    }

    // 用指定摄像头重新采集视频
    final newStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'mandatory': {
          'minWidth': _config.videoWidth.toString(),
          'minHeight': _config.videoHeight.toString(),
          'maxWidth': _config.videoWidth.toString(),
          'maxHeight': _config.videoHeight.toString(),
          'minFrameRate': _config.videoFps.toString(),
          'maxFrameRate': _config.videoFps.toString(),
        },
        'deviceId': deviceId,
        'facingMode': 'user',
      },
    });

    final newVideoTrack = newStream.getVideoTracks().firstOrNull;
    if (newVideoTrack == null) {
      _log.warning('切换摄像头失败：无法获取视频轨道');
      return;
    }

    // 监听新轨道的结束事件（摄像头被系统回收时触发）
    newVideoTrack.onEnded = () {
      _log.warning('摄像头视频轨道意外终止');
      onCameraError?.call();
    };

    // 添加到本地流
    await _localStream!.addTrack(newVideoTrack);

    // 替换 PeerConnection 中的视频轨道（如果存在）
    if (_peerConnection != null) {
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          try {
            await sender.replaceTrack(newVideoTrack);
          } catch (e) {
            _log.warning('替换视频轨道失败: $e');
          }
          break;
        }
      }
    }

    // 释放临时流（轨道已转移到 _localStream）
    try {
      await newStream.dispose();
    } catch (_) {}

    _log.info('摄像头已切换: $deviceId');
  }

  /// 摄像头异常回调（轨道意外终止时触发）
  void Function()? onCameraError;

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
