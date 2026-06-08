import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../providers/call_provider.dart';
import '../utils/constants.dart';
import '../widgets/glass_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/responsive_wrapper.dart';
import 'room_waiting_screen.dart';

/// 加入房间页面
///
/// 提供两种方式加入房间：
/// 1. 手动输入 6 位房间号
/// 2. 扫描二维码
///
/// 输入完成后自动去空格、转为大写，6 位填满后自动触发加入。
class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();

  /// 是否正在显示扫码器
  bool _showScanner = false;

  /// 扫码器控制器
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    // 自动聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);

    // 如果成功加入房间 → 跳转到等待页
    if (callState.phase == CallPhase.waiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // 替换当前路由，防止返回到加入页面
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const RoomWaitingScreen(),
            ),
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: colorBackground,
      body: SafeArea(
        child: ResponsiveWrapper(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
            child: Column(
            children: [
              const SizedBox(height: 16.0),

              // 顶部标题
              _buildHeader(),

              const SizedBox(height: 48.0),

              // 房间号输入区域
              _buildInputArea(),

              const SizedBox(height: 32.0),

              // 错误提示
              if (callState.errorMessage != null)
                _buildErrorBanner(callState.errorMessage!),

              // 加入按钮
              _buildJoinButton(callState),

              const SizedBox(height: 24.0),

              // 分割线 + 扫码入口
              _buildDividerWithScan(),
            ],
          ),
        ),
        ),
      ),

      // 扫码器弹出层
      bottomSheet: _showScanner ? _buildScannerSheet() : null,
    );
  }

  /// 顶部标题栏
  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 36.0,
            height: 36.0,
            decoration: BoxDecoration(
              color: colorGlassBackground,
              borderRadius: BorderRadius.circular(18.0),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: colorTextPrimary,
              size: 20.0,
            ),
          ),
        ),
        const SizedBox(width: spacingCompact),
        Text(
          '加入房间',
          style: styleTitle2.copyWith(color: colorTextPrimary),
        ),
      ],
    );
  }

  /// 房间号输入区域
  Widget _buildInputArea() {
    return Column(
      children: [
        Text(
          '输入 6 位房间号',
          style: styleCaption.copyWith(color: colorNeutral),
        ),
        const SizedBox(height: 16.0),
        // 大号输入框
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 12.0,
            ),
            child: TextField(
              controller: _codeController,
              focusNode: _focusNode,
              textAlign: TextAlign.center,
              maxLength: roomCodeLength,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(roomCodeLength),
              ],
              style: styleLargeTitle.copyWith(
                fontSize: 42.0,
                letterSpacing: 12.0,
                color: colorTextPrimary,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '', // 隐藏字数计数器
                hintText: '------',
                hintStyle: TextStyle(
                  color: Color.fromARGB(80, 142, 142, 147),
                  fontSize: 42.0,
                  letterSpacing: 12.0,
                ),
              ),
              onChanged: (_) {
                // 每次输入变化时清除错误
                if (ref.read(callProvider).errorMessage != null) {
                  ref.read(callProvider.notifier).clearError();
                }
                // 6 位输入完成 → 自动触发加入
                if (_codeController.text.length == roomCodeLength) {
                  _joinRoom();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 错误提示条
  Widget _buildErrorBanner(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 12.0,
        ),
        decoration: BoxDecoration(
          color: colorDanger.withAlpha(25),
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: colorDanger.withAlpha(77), width: 1.0),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: colorDanger, size: 20.0),
            const SizedBox(width: spacingCompact),
            Expanded(
              child: Text(
                message,
                style: styleCaption.copyWith(color: colorDanger),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 加入按钮
  Widget _buildJoinButton(CallState2 callState) {
    final code = _codeController.text;
    final canJoin = code.length == roomCodeLength &&
        callState.phase != CallPhase.connecting;

    return GlassButton(
      label: callState.phase == CallPhase.connecting ? '正在加入...' : '加入房间',
      icon: callState.phase == CallPhase.connecting
          ? null
          : Icons.login_rounded,
      type: GlassButtonType.accent,
      onPressed: canJoin ? _joinRoom : null,
    );
  }

  /// 分割线 + 扫码入口
  Widget _buildDividerWithScan() {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: colorDivider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                '或者',
                style: styleSmall.copyWith(color: colorNeutral),
              ),
            ),
            const Expanded(child: Divider(color: colorDivider)),
          ],
        ),
        const SizedBox(height: 16.0),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _showScanner = !_showScanner;
              if (_showScanner) {
                _scannerController = MobileScannerController();
              } else {
                _scannerController?.dispose();
                _scannerController = null;
              }
            });
          },
          icon: Icon(
            _showScanner ? Icons.qr_code_scanner_rounded : Icons.qr_code_rounded,
            color: colorAccent,
          ),
          label: Text(
            _showScanner ? '关闭扫码器' : '扫描二维码加入',
            style: styleBody.copyWith(color: colorAccent),
          ),
        ),
      ],
    );
  }

  /// 扫码器底部弹出层
  Widget _buildScannerSheet() {
    return Container(
      height: 300.0,
      decoration: const BoxDecoration(
        color: colorBlack,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radiusCard),
          topRight: Radius.circular(radiusCard),
        ),
      ),
      child: Column(
        children: [
          // 扫码器顶部控制栏
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '将二维码对准框内',
                  style: styleCaption.copyWith(color: colorWhite),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showScanner = false;
                      _scannerController?.dispose();
                      _scannerController = null;
                    });
                  },
                  icon: const Icon(Icons.close_rounded, color: colorWhite),
                ),
              ],
            ),
          ),
          // 扫码器画面
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(radiusCard),
                topRight: Radius.circular(radiusCard),
              ),
              child: _scannerController != null
                  ? MobileScanner(
                      controller: _scannerController!,
                      onDetect: (capture) {
                        final barcode = capture.barcodes.firstOrNull;
                        if (barcode != null &&
                            barcode.rawValue != null &&
                            barcode.rawValue!.startsWith('clearcall://room/')) {
                          // 从 URL 提取房间号
                          final roomCode =
                              barcode.rawValue!.replaceFirst('clearcall://room/', '').trim();
                          if (roomCode.length == roomCodeLength &&
                              int.tryParse(roomCode) != null) {
                            _codeController.text = roomCode;
                            setState(() {
                              _showScanner = false;
                              _scannerController?.dispose();
                              _scannerController = null;
                            });
                            _joinRoom();
                          }
                        }
                      },
                    )
                  : const Center(
                      child: Text(
                        '相机权限未授权',
                        style: TextStyle(color: colorNeutral),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 执行加入房间
  void _joinRoom() {
    final code = _codeController.text.trim();
    if (code.length != roomCodeLength) return;

    // 收起键盘
    _focusNode.unfocus();

    ref.read(callProvider.notifier).joinRoom(code);
  }
}
