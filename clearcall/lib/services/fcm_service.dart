import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logging/logging.dart';

/// FCM 推送服务
///
/// 负责：
/// - Firebase Cloud Messaging 初始化
/// - FCM Token 获取（用于后台来电推送）
/// - 前台消息处理（显示系统通知）
/// - 后台消息处理（通过系统托盘唤醒 App）
///
/// 注意：
/// - 应用内来电监听通过 Firebase RTDB 的 onIncomingCall 实现（实时 + 低延迟）
/// - FCM 用于后台唤醒（App 不在前台时收到来电通知）
/// - 完整的 FCM 推送需要服务端/Cloud Function 配合发送消息
class FcmService {
  final Logger _log = Logger('FcmService');

  /// Firebase Messaging 实例
  final FirebaseMessaging _messaging;

  /// 当前 FCM Token
  String? _token;

  /// 来电通知回调（App 在后台时收到 FCM 推送）
  void Function(String callerUid, String callerName)? onBackgroundCall;

  FcmService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  /// FCM Token
  String? get token => _token;

  /// 初始化 FCM
  Future<void> initialize() async {
    try {
      // 1. 请求通知权限（Android 13+）
      await _requestPermission();

      // 2. 获取 FCM Token
      await _getToken();

      // 3. 监听 Token 刷新
      _messaging.onTokenRefresh.listen((newToken) {
        _token = newToken;
        _log.info('FCM Token 已刷新: ${newToken.substring(0, 10)}...');
      });

      // 4. 前台消息处理（显示通知）
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 5. 后台消息点击处理（用户点击通知打开 App）
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpened);

      // 6. 检查是否从通知启动
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpened(initialMessage);
      }

      _log.info('FCM 初始化完成');
    } catch (e) {
      _log.severe('FCM 初始化失败', e);
    }
  }

  /// 请求通知权限
  Future<void> _requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      _log.info('通知权限状态: ${settings.authorizationStatus}');
    } catch (e) {
      _log.warning('通知权限请求失败: $e');
    }
  }

  /// 获取 FCM Token
  Future<void> _getToken() async {
    try {
      _token = await _messaging.getToken();
      _log.info('FCM Token: ${_token?.substring(0, 10)}...');
    } catch (e) {
      _log.severe('FCM Token 获取失败', e);
    }
  }

  /// 处理前台消息
  void _handleForegroundMessage(RemoteMessage message) {
    _log.info('收到前台消息: ${message.data}');

    final data = message.data;
    final type = data['type'];

    if (type == 'call') {
      final callerUid = data['callerUid'] ?? '';
      final callerName = data['callerName'] ?? '未知来电';
      onBackgroundCall?.call(callerUid, callerName);
    }
  }

  /// 处理通知点击
  void _handleMessageOpened(RemoteMessage message) {
    _log.info('通知已打开: ${message.data}');
  }

  /// 清理资源
  void dispose() {
    _log.info('FcmService 已清理');
  }
}
