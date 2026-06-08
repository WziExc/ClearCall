import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/friend_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/constants.dart';
import '../utils/qr_utils.dart';
import '../widgets/glass_card.dart';
import '../widgets/responsive_wrapper.dart';

/// 添加好友页面
///
/// 包含三个 Tab：
/// - 我的二维码（供他人扫描添加）
/// - 扫描二维码（扫描他人 QR 添加好友）
/// - 分享链接（生成邀请文本分享）
class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// QR 扫描控制器
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: colorBackground,
      appBar: AppBar(
        title: const Text('添加好友'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorAccent,
          labelColor: colorAccent,
          unselectedLabelColor: colorNeutral,
          tabs: const [
            Tab(text: '我的二维码', icon: Icon(Icons.qr_code_2_rounded, size: 20)),
            Tab(text: '扫一扫', icon: Icon(Icons.camera_alt_rounded, size: 20)),
          ],
        ),
      ),
      body: ResponsiveWrapper(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildMyQrTab(settings),
            _buildScanTab(),
          ],
        ),
      ),
    );
  }

  /// Tab 1: 显示我的二维码
  Widget _buildMyQrTab(AppSettings settings) {
    // 生成验证 token（每次显示时重新生成）
    final token = QrUtils.generateFriendToken();
    final qrData = QrUtils.generateFriendQrData(settings.localId, token);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(paddingHorizontal),
      child: Column(
        children: [
          const SizedBox(height: 32.0),

          // 二维码说明
          const Text(
            '让对方扫描此二维码\n即可添加你为好友',
            style: styleCaption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24.0),

          // 二维码卡片
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200.0,
                    eyeStyle: const QrEyeStyle(color: colorTextPrimary),
                    dataModuleStyle:
                        const QrDataModuleStyle(color: colorTextPrimary),
                  ),
                  const SizedBox(height: 16.0),
                  Text(
                    '昵称: ${settings.nickname}',
                    style: styleCaption,
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'ID: ${settings.localId.substring(0, 8)}...',
                    style: styleSmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24.0),

          // 分享链接区域
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('邀请链接', style: styleTitle3),
                  const SizedBox(height: 8.0),
                  const Text(
                    '你也可以复制以下链接分享给好友',
                    style: styleSmall,
                  ),
                  const SizedBox(height: 12.0),
                  // 链接显示
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: colorGlassBackground,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: colorGlassBorder),
                    ),
                    child: SelectableText(
                      qrData,
                      style: styleSmall.copyWith(
                        color: colorTextPrimary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32.0),
        ],
      ),
    );
  }

  /// Tab 2: 扫描二维码
  Widget _buildScanTab() {
    return Column(
      children: [
        // 扫描区域
        Expanded(
          child: ClipRRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 摄像头预览
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onBarcodeDetected,
                ),
                // 扫描框覆盖层
                _buildScanOverlay(),
              ],
            ),
          ),
        ),

        // 底部提示
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24.0),
          color: colorGlassBackground,
          child: Column(
            children: [
              const Text(
                '将二维码对准框内即可自动扫描',
                style: styleCaption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16.0),
              // 手动输入按钮
              TextButton.icon(
                onPressed: () => _showManualInputDialog(),
                icon: const Icon(Icons.keyboard_rounded, size: 20),
                label: const Text('手动输入好友 ID'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 扫描框覆盖层
  Widget _buildScanOverlay() {
    return Center(
      child: Container(
        width: 240.0,
        height: 240.0,
        decoration: BoxDecoration(
          border: Border.all(
            color: colorAccent,
            width: 2.0,
          ),
          borderRadius: BorderRadius.circular(16.0),
        ),
      ),
    );
  }

  /// 扫描到二维码时调用
  void _onBarcodeDetected(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    // 解析二维码数据
    final data = QrUtils.parseQrData(barcode.rawValue!);
    if (data == null) return;

    // 停止扫描
    _scannerController?.stop();

    if (data['type'] == 'friend') {
      // 好友二维码 → 发送好友申请
      final uid = data['uid'] as String;
      final token = data['token'] as String;
      _confirmAddFriend(uid, token);
    } else if (data['type'] == 'room') {
      // 房间二维码 → 加入房间（在 JoinRoomScreen 中已经处理）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检测到房间号，请在通话 Tab 中扫描加入房间')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  /// 确认添加好友弹窗
  void _confirmAddFriend(String targetUid, String token) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加好友'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要向此用户发送好友申请吗？'),
            const SizedBox(height: 12.0),
            Text(
              '用户 ID: ${targetUid.substring(0, 8)}...',
              style: styleSmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // 重新开始扫描
              _scannerController?.start();
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _sendRequest(targetUid);
            },
            style: TextButton.styleFrom(foregroundColor: colorAccent),
            child: const Text('发送申请'),
          ),
        ],
      ),
    );
  }

  /// 发送好友申请
  Future<void> _sendRequest(String targetUid) async {
    try {
      await ref.read(friendProvider.notifier).sendFriendRequest(targetUid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('好友申请已发送'),
            backgroundColor: colorSuccess,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            backgroundColor: colorDanger,
          ),
        );
      }
    }
  }

  /// 手动输入好友 ID 弹窗
  void _showManualInputDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动添加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入好友的 16 位 ID：', style: styleCaption),
            const SizedBox(height: 12.0),
            TextField(
              controller: controller,
              maxLength: 16,
              decoration: const InputDecoration(
                hintText: '例如: a1b2c3d4e5f6g7h8',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final uid = controller.text.trim();
              if (uid.length == 16) {
                Navigator.of(ctx).pop();
                _sendRequest(uid);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
