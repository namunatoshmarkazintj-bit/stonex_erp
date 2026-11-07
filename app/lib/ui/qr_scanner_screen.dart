import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/barcode_decoder.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import '../state/cart_controller.dart';
import 'common.dart';
import 'receipt_dialog.dart';

String _u(String unit) => unit == 'm2' ? 'm²' : unit;

String? _decodeQrFromBytes(Uint8List bytes) {
  return BarcodeDecoder.decode(bytes);
}

class _ScannerHolePainter extends CustomPainter {
  _ScannerHolePainter({required this.holeRect, required this.borderRadius});
  final Rect holeRect;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.58);
    final bgPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(holeRect, Radius.circular(borderRadius)));
    final combined = Path.combine(PathOperation.difference, bgPath, holePath);
    canvas.drawPath(combined, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerHolePainter old) =>
      old.holeRect != holeRect || old.borderRadius != borderRadius;
}

class _ReticleCorner extends StatelessWidget {
  const _ReticleCorner({required this.isTop, required this.isLeft});
  final bool isTop;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    const double size = 26;
    const double thickness = 3.5;
    const color = AppColors.neonLime;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            top: isTop ? 0 : null,
            bottom: !isTop ? 0 : null,
            left: isLeft ? 0 : null,
            right: !isLeft ? 0 : null,
            child: Container(
              width: size,
              height: thickness,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            top: isTop ? 0 : null,
            bottom: !isTop ? 0 : null,
            left: isLeft ? 0 : null,
            right: !isLeft ? 0 : null,
            child: Container(
              width: thickness,
              height: size,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedCircleButton extends StatelessWidget {
  const _FrostedCircleButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20, color: color),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    );
  }
}

/// Mobil qurilmalar uchun to‘liq ekranli, keng va qulay QR kod kamera skaneri
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    required this.onCartUpdated,
    this.onGoToCart,
  });

  final VoidCallback onCartUpdated;
  final VoidCallback? onGoToCart;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _laserCtrl;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  bool _cameraInitializing = false;
  bool _hasCamera = false;
  bool _isScanningFrame = false;
  Timer? _scanTimer;
  bool _torchOn = false;

  String? _currentLockedCode;
  int _emptyFramesCount = 0;

  Product? _lastProduct;
  double _lastQty = 1.0;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _laserCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    // Ekranni to'sib qo'ymasligi uchun klaviatura AVTOMATIK OCHILMAYDI. Toza kamera ochiladi.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCamera();
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraController?.dispose();
    _laserCtrl.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (Platform.isWindows) {
      if (mounted) {
        setState(() {
          _hasCamera = false;
          _cameraInitializing = false;
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _cameraInitializing = true);
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty && mounted) {
        final backIdx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _currentCameraIndex = backIdx >= 0 ? backIdx : 0;
        await _setupController(_cameras[_currentCameraIndex]);
      } else {
        if (mounted) setState(() => _hasCamera = false);
      }
    } catch (_) {
      if (mounted) setState(() => _hasCamera = false);
    } finally {
      if (mounted) setState(() => _cameraInitializing = false);
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    try {
      _scanTimer?.cancel();
      await _cameraController?.dispose();
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _cameraController = controller;
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _hasCamera = true;
        _torchOn = false;
      });
      _startPeriodicScanning();
    } catch (_) {
      if (mounted) setState(() => _hasCamera = false);
    }
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      _torchOn = !_torchOn;
      await _cameraController!.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1) return;
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _setupController(_cameras[_currentCameraIndex]);
  }

  void _startPeriodicScanning() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      if (!_hasCamera || _cameraController == null || !_cameraController!.value.isInitialized) return;
      if (_isScanningFrame) return;
      _isScanningFrame = true;
      try {
        final xFile = await _cameraController!.takePicture();
        final bytes = await xFile.readAsBytes();
        try {
          File(xFile.path).deleteSync();
        } catch (_) {}

        final code = _decodeQrFromBytes(bytes);
        if (code != null && code.isNotEmpty) {
          _emptyFramesCount = 0;
          if (mounted) {
            _processCode(code);
          }
        } else {
          // Kamerada QR kod ko'rinmay qolganda (boshqa tovar olish uchun siljitilganda)
          _emptyFramesCount++;
          if (_emptyFramesCount >= 2) {
            _currentLockedCode = null;
          }
        }
      } catch (_) {
      } finally {
        _isScanningFrame = false;
      }
    });
  }

  Future<void> _processCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    // Bir marta skanerlangandan keyin kamera shu kod ustida tursa, qayta-qayta qo'shavermasin!
    if (_currentLockedCode == code) {
      return;
    }

    // 1. Agar skanerlangan kod CHEK (RECEIPT) QR-kodi bo'lsa:
    if (isReceiptQr(code)) {
      _currentLockedCode = code;
      final saleId = extractSaleId(code);
      if (saleId != null) {
        try {
          final repos = context.read<AppRepositories>();
          final sales = await repos.sales.listSales(limit: 500);
          final matched = sales.where((s) => s.id == saleId).firstOrNull;
          if (matched != null && mounted) {
            HapticFeedback.heavyImpact();
            SystemSound.play(SystemSoundType.click);
            setState(() {
              _isError = false;
              _statusMessage = 'Chek #${matched.id} rasmi va ma‘lumotlari ochildi';
            });
            await ReceiptDialog.show(context, matched);
            return;
          } else {
            HapticFeedback.vibrate();
            setState(() {
              _isError = true;
              _statusMessage = 'Chek #$saleId tizimdan topilmadi';
            });
            return;
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isError = true;
              _statusMessage = 'Chekni ochishda xatolik: $e';
            });
          }
          return;
        }
      }
    }

    try {
      final repo = context.read<AppRepositories>().products;
      final p = await repo.findByCode(code);
      if (!mounted) return;

      if (p != null) {
        _currentLockedCode = code; // Qulflanadi: kamera ushbu kod ustida turganda faqat 1 marta qo'shiladi

        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);

        context.read<CartController>().add(p, quantity: 1);
        widget.onCartUpdated();

        setState(() {
          _isError = false;
          _statusMessage = '“${p.name}” savatga qo‘shildi';
          _lastProduct = p;
          _lastQty = 1.0;
        });
      } else {
        _currentLockedCode = code;
        HapticFeedback.vibrate();
        setState(() {
          _isError = true;
          _statusMessage = 'Kod o‘qildi: "$code" (Bazada bu kodga ega mahsulot topilmadi)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _statusMessage = 'Xatolik: $e';
        });
      }
    }
  }

  void _updateLastQty(double delta) {
    if (_lastProduct == null) return;
    final cart = context.read<CartController>();
    final p = _lastProduct!;

    if (delta > 0) {
      cart.add(p, quantity: delta);
      setState(() {
        _lastQty += delta;
        _statusMessage = '“${p.name}” miqdori: ${qty(_lastQty)} ${_u(p.unit)}';
      });
    } else if (delta < 0) {
      final existing = cart.lines.where((l) => l.product.id == p.id);
      if (existing.isNotEmpty) {
        final l = existing.first;
        if (l.quantity + delta > 0.001) {
          cart.update(l, quantity: l.quantity + delta);
          setState(() {
            _lastQty += delta;
            _statusMessage = '“${p.name}” miqdori: ${qty(_lastQty)} ${_u(p.unit)}';
          });
        } else {
          cart.remove(l);
          setState(() {
            _lastProduct = null;
            _lastQty = 1.0;
            _statusMessage = '“${p.name}” savatdan olindi';
          });
        }
      }
    }
    widget.onCartUpdated();
  }

  void _showManualInputDialog() {
    final textCtrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.dialogBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(bCtx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.keyboard_alt_outlined, color: AppColors.green),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Kodni qo‘lda kiritish',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(bCtx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: 14, color: bCtx.inkColor, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Masalan: STX-ANGOLA yoki raqam...',
                  hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
                  filled: true,
                  fillColor: bCtx.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: bCtx.borderColor),
                  ),
                ),
                onSubmitted: (val) {
                  Navigator.pop(bCtx);
                  _processCode(val);
                },
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  final txt = textCtrl.text;
                  Navigator.pop(bCtx);
                  _processCode(txt);
                },
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('Savatga qo‘shish', style: TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScannedProductCard(Product p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131D17),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.green.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 14, color: AppColors.green),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Oxirgi skanerlangan mahsulot',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () => showProductImagePreview(
                  context,
                  imageUrl: p.imageUrl,
                  name: p.name,
                  subtitle: '${money(p.price)} / ${p.unit} • Qoldiq: ${qty(p.stock)} ${p.unit}',
                ),
                child: ProductThumbnail(
                  imageUrl: p.imageUrl,
                  name: p.name,
                  size: 50,
                  borderRadius: 12,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${money(p.price)} / ${_u(p.unit)} • Qoldiq: ${qty(p.stock)} ${_u(p.unit)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFA9BDB0)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // [ - ] Qty [ + ]
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E2218),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF1E382A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, size: 16, color: Colors.white),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      splashRadius: 14,
                      onPressed: () => _updateLastQty(-1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        qty(_lastQty),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      splashRadius: 14,
                      onPressed: () => _updateLastQty(1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(CartController cart) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1015),
        border: Border(top: BorderSide(color: Color(0xFF1C2530))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(Icons.shopping_bag_outlined, color: AppColors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cart.lines.isNotEmpty ? '${cart.lines.length} ta tovar' : 'Savat bo‘sh',
                          style: const TextStyle(color: Color(0xFFA9BDB0), fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          money(cart.total),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.neonLime,
                foregroundColor: AppColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const Text('Tayyor (Yopish)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final size = MediaQuery.sizeOf(context);
    final double holeSize = (size.width * 0.68).clamp(220.0, 300.0);
    final Rect holeRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.38),
      width: holeSize,
      height: holeSize,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Kamera tasviri yoki holat
          if (_hasCamera && _cameraController != null && _cameraController!.value.isInitialized) ...[
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? size.width,
                  height: _cameraController!.value.previewSize?.width ?? size.height,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
            // Qoraytirilgan oyna va o'rtadagi shaffof tuynuk
            CustomPaint(
              size: size,
              painter: _ScannerHolePainter(holeRect: holeRect, borderRadius: 24),
            ),
            // 4 ta burchak mo‘ljali
            Positioned(
              left: holeRect.left,
              top: holeRect.top,
              child: const _ReticleCorner(isTop: true, isLeft: true),
            ),
            Positioned(
              left: holeRect.right - 26,
              top: holeRect.top,
              child: const _ReticleCorner(isTop: true, isLeft: false),
            ),
            Positioned(
              left: holeRect.left,
              top: holeRect.bottom - 26,
              child: const _ReticleCorner(isTop: false, isLeft: true),
            ),
            Positioned(
              left: holeRect.right - 26,
              top: holeRect.bottom - 26,
              child: const _ReticleCorner(isTop: false, isLeft: false),
            ),
            // Lazer nuri
            AnimatedBuilder(
              animation: _laserCtrl,
              builder: (ctx, _) {
                return Positioned(
                  left: holeRect.left + 10,
                  width: holeRect.width - 20,
                  top: holeRect.top + 8 + (_laserCtrl.value * (holeRect.height - 20)),
                  child: Container(
                    height: 2.8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.neonLime,
                          Colors.white,
                          AppColors.neonLime,
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonLime.withValues(alpha: 0.9),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // Ramka ostidagi eslatma
            Positioned(
              top: holeRect.bottom + 16,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppColors.neonLime),
                      SizedBox(width: 8),
                      Text(
                        'QR yoki shtrix-kodni ramkaga to‘g‘rilang',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else if (_cameraInitializing) ...[
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.neonLime),
                  SizedBox(height: 14),
                  Text(
                    'Kamera ishga tushirilmoqda...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2835),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.videocam_off_rounded, size: 36, color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Kamera topilmadi yoki ruxsat yo‘q',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Telefonda kameraga ruxsat bering yoki kodni qo‘lda kiriting',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _initCamera,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Qayta urinish'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.neonLime,
                            foregroundColor: AppColors.ink,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _showManualInputDialog,
                          icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                          label: const Text('Qo‘lda kiritish'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 2. Yuqori panel: Orqaga, Chiroq, Kamera almashtirish, Qo'lda kiritish
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _FrostedCircleButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Orqaga',
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'QR Skaner',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _FrostedCircleButton(
                      icon: Icons.keyboard_alt_outlined,
                      onPressed: _showManualInputDialog,
                      tooltip: 'Kodni qo‘lda yozish',
                    ),
                    if (_hasCamera) ...[
                      const SizedBox(width: 8),
                      _FrostedCircleButton(
                        icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: _torchOn ? AppColors.neonLime : Colors.white,
                        onPressed: _toggleTorch,
                        tooltip: 'Chiroq (Fonarik)',
                      ),
                      if (_cameras.length > 1) ...[
                        const SizedBox(width: 8),
                        _FrostedCircleButton(
                          icon: Icons.flip_camera_ios_rounded,
                          onPressed: _switchCamera,
                          tooltip: 'Kamerani almashtirish',
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),

          // 3. Pastki qism: Skanerlangan mahsulot kartasi va Savat paneli
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_statusMessage != null && _isError) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B1515),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                if (_lastProduct != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _buildScannedProductCard(_lastProduct!),
                  ),
                ],

                _buildBottomBar(cart),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
