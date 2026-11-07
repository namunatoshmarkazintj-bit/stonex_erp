import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/local_image_store.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import '../state/cart_controller.dart';
import '../state/currency_controller.dart';
import 'camera_capture_dialog.dart';
import 'common.dart';
import 'qr_scanner_screen.dart';
import '../state/auth_controller.dart';
import 'receipt_dialog.dart';
import 'stone_services_dialog.dart';

String _u(String unit) => unit == 'm2' ? 'm²' : unit;

double _roundClean(double val) {
  if ((val - val.round()).abs() < 0.01) {
    return val.roundToDouble();
  }
  return double.parse(val.toStringAsFixed(3));
}

BoxDecoration _cardBox({Color? color, double radius = 22}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4))],
    );

ShapeBorder get _dialogShape => RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));


bool _isCategoryMatch(Product p, String selectedCategory) {
  if (p.isService) return false;
  if (selectedCategory == 'Barchasi') return true;

  String norm(String s) => s
      .toLowerCase()
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('ʻ', "'")
      .replaceAll('ʼ', "'")
      .replaceAll('`', "'")
      .trim();

  final sel = norm(selectedCategory);

  // 1. Mahsulotning o'z kategoriyasi bilan solishtirish
  if (p.category != null && p.category!.trim().isNotEmpty) {
    final cat = norm(p.category!);
    if (cat == sel) return true;
    if (sel == 'kerama granit' && (cat.contains('keramo') || cat.contains('kerama') || cat.contains('plitka'))) return true;
    if (sel == 'granit' && cat.contains('granit') && !cat.contains('kerama') && !cat.contains('keramo')) return true;
    if (sel.startsWith("qo'shimcha") && (cat.contains("qo'shimcha") || cat.contains('material') || cat.contains('aksessuar') || cat.contains('kley'))) return true;
    if (sel == 'kafel' && (cat.contains('kafel') || cat.contains('plita'))) return true;
    if (sel == 'marmar' && cat.contains('marmar')) return true;
    if (sel == 'xomashyo' && cat.contains('xomashyo')) return true;
    if (sel.startsWith('tayyor') && cat.contains('tayyor')) return true;
  }

  // 2. Mahsulot nomi bo'yicha intellektual moslik
  final n = norm(p.name);
  if (n.contains(sel)) return true;

  if (sel == 'kerama granit' && (n.contains('keramogranit') || n.contains('keramo') || n.contains('kerama'))) return true;
  if (sel == 'granit' && (n.contains('angola') || n.contains('tan brown') || n.contains('black crystal') || n.contains('granit'))) {
    if (p.category == null || !norm(p.category!).contains('keram')) return true;
  }
  if (sel == 'marmar' && (n.contains('miramir') || n.contains('marmar') || n.contains('travertin'))) return true;
  if (sel == 'kafel' && (n.contains('kafel') || n.contains('plita'))) return true;
  if (sel.startsWith("qo'shimcha") && (n.contains('kley') || n.contains('akfix') || n.contains('disk') || n.contains('cherepashka') || n.contains("chizg'ich") || n.contains('qalamtarosh') || n.contains('qalamqosh') || n.contains('rizak'))) return true;
  if (sel == 'xomashyo' && (n.contains('sim') || n.contains('blok') || n.contains('xomashyo'))) return true;

  return false;
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _search = TextEditingController();
  late Future<List<Product>> _future;
  String _selectedCategory = 'Barchasi';
  int _mobileTab = 0; // 0: Katalog, 1: Savat
  bool _isScannerOpen = false;

  static const _categories = [
    'Barchasi',
    'Granit',
    'Kerama granit',
    'Kafel',
    'Marmar',
    'Tayyor mahsulot',
    'Xomashyo',
    'Qo‘shimcha',
  ];

  ProductRepository get _repo => context.read<AppRepositories>().products;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _future = context.read<AppRepositories>().products.list();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _search.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f2) {
      if (!_isScannerOpen && mounted) {
        _openQrScanner();
      }
      return true;
    }
    return false;
  }

  void _reload() {
    setState(() {
      _future = _repo.list();
    });
  }

  Future<void> _openQrScanner() async {
    if (_isScannerOpen) return;
    _isScannerOpen = true;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide && Platform.isWindows) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => _DesktopQrScannerDialog(
          onCartUpdated: () {
            if (mounted) setState(() {});
          },
        ),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (ctx) => QrScannerScreen(
            onCartUpdated: () {
              if (mounted) setState(() {});
            },
            onGoToCart: () {
              if (mounted) {
                setState(() {
                  _mobileTab = 1;
                });
              }
            },
          ),
        ),
      );
    }
    _isScannerOpen = false;
    if (mounted) _reload();
  }

  Future<void> _onSubmit(String text) async {
    final code = text.trim();
    if (code.isEmpty) return;

    if (isReceiptQr(code)) {
      final saleId = extractSaleId(code);
      if (saleId != null) {
        try {
          final sales = await context.read<AppRepositories>().sales.listSales(limit: 500);
          final matched = sales.where((s) => s.id == saleId).firstOrNull;
          if (matched != null && mounted) {
            _search.clear();
            await ReceiptDialog.show(context, matched);
            return;
          }
        } catch (_) {}
      }
    }

    try {
      final p = await _repo.findByCode(code);
      if (!mounted) return;
      if (p != null) {
        context.read<CartController>().add(p);
        _search.clear();
        _reload();
      } else {
        showMessage(context, 'Bu kod bo‘yicha mahsulot topilmadi', error: true);
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartController = context.watch<CartController>();
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final searchAndFilter = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Vault qidiruv paneli va QR Skaner
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _search,
                  autofocus: wide,
                  style: TextStyle(fontSize: 13, color: context.inkColor, fontWeight: FontWeight.w500),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: context.cardColor,
                    isDense: true,
                    hintText: 'Qidirish yoki kod yozing...',
                    hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: context.borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: context.borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: context.isDark ? AppColors.neonLime : AppColors.ink, width: 1.5)),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _onSubmit,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: _openQrScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                label: Text(
                  wide ? 'QR Skaner (F2)' : 'QR',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                  foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 14),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Kategoriya pill chiplari
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((c) {
              final sel = _selectedCategory == c;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    c,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? (context.isDark ? AppColors.ink : Colors.white) : context.inkColor,
                    ),
                  ),
                  selected: sel,
                  selectedColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                  backgroundColor: context.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: sel ? (context.isDark ? AppColors.neonLime : AppColors.darkCard) : context.borderColor),
                  ),
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = c;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );

    final products = Column(children: [
      searchAndFilter,
      const SizedBox(height: 14),
      Expanded(
        child: FutureBuilder<List<Product>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: snap.error.toString(), onRetry: _reload);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var items = snap.data!.where((p) => !p.isService).toList();

            final query = _search.text.trim().toLowerCase();
            if (query.isNotEmpty) {
              items = items.where((p) {
                final n = p.name.toLowerCase();
                final sku = p.sku.toLowerCase();
                final qr = p.qrCode.toLowerCase();
                return n.contains(query) || sku.contains(query) || qr.contains(query);
              }).toList();
            }

            if (_selectedCategory != 'Barchasi') {
              items = items.where((p) => _isCategoryMatch(p, _selectedCategory)).toList();
            }

            if (items.isEmpty) {
              return const _EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Mahsulot topilmadi',
                hint: 'Boshqa nom yoki kod bilan urinib ko‘ring',
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 214,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => _ProductCard(
                key: ValueKey(items[i].id),
                product: items[i],
                index: i,
                onTap: () {
                  context.read<CartController>().add(items[i]);
                  if (!wide) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        content: Text('${items[i].name} savatga qo‘shildi'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
            );
          },
        ),
      ),
    ]);

    final cart = _CartPanel(onSold: _reload);

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 5, child: products),
          const SizedBox(width: 20),
          Expanded(flex: 3, child: cart),
        ]),
      );
    }

    // Mobil qurilmalar (Smartfonlar) uchun toza tabli ko'rinish
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        children: [
          // Mobil tab tugmalari
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _mobileTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _mobileTab == 0
                            ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Katalog',
                        style: TextStyle(
                          color: _mobileTab == 0
                              ? (context.isDark ? AppColors.ink : Colors.white)
                              : context.mutedColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _mobileTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _mobileTab == 1
                            ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Savat',
                            style: TextStyle(
                              color: _mobileTab == 1
                                  ? (context.isDark ? AppColors.ink : Colors.white)
                                  : context.mutedColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          if (cartController.lines.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: _mobileTab == 1
                                    ? (context.isDark ? AppColors.ink : AppColors.neonLime)
                                    : (context.isDark ? AppColors.neonLime.withValues(alpha: 0.2) : AppColors.greenSoft),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${cartController.lines.length}',
                                style: TextStyle(
                                  color: _mobileTab == 1 && context.isDark ? AppColors.neonLime : AppColors.ink,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                          if (cartController.heldCarts.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '⏸${cartController.heldCarts.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _mobileTab == 0 ? products : cart,
          ),
          if (_mobileTab == 0 && cartController.lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${cartController.lines.length} ta mahsulot',
                          style: const TextStyle(color: Color(0xFFA9BDB0), fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          money(cartController.total),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => setState(() => _mobileTab = 1),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.neonLime,
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 16),
                    label: const Text('Savat', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mahsulot kartasi
// ---------------------------------------------------------------------------

class _ProductCard extends StatefulWidget {
  const _ProductCard({super.key, required this.product, required this.index, required this.onTap});
  final Product product;
  final int index;
  final VoidCallback onTap;
  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final out = p.stock <= 0;
    final lifted = _hover && !out;
    final intro = Duration(milliseconds: 320 + widget.index.clamp(0, 10) * 45);

    final cart = context.watch<CartController>();
    final inCartLines = cart.lines.where((l) => l.product.id == p.id).toList();
    final inCart = inCartLines.isNotEmpty;
    final inCartCount = inCartLines.fold<double>(0, (sum, l) => sum + l.quantity);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: intro,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 22), child: child),
      ),
      child: MouseRegion(
        cursor: out ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: out ? null : widget.onTap,
          onTapDown: out ? null : (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: const Duration(milliseconds: 100),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, lifted ? -4 : 0, 0),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: lifted ? AppColors.green : context.borderColor, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: Color(lifted ? 0x24000000 : 0x0A000000),
                    blurRadius: lifted ? 20 : 10,
                    offset: Offset(0, lifted ? 8 : 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: Opacity(
                  opacity: out ? 0.55 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Katta rasm qismi (Image Banner)
                      SizedBox(
                        height: 104,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ProductThumbnail(
                              imageUrl: p.imageUrl,
                              name: p.name,
                              width: double.infinity,
                              height: 104,
                              borderRadiusGeometry: const BorderRadius.vertical(top: Radius.circular(19)),
                            ),
                            if (p.category != null && p.category!.isNotEmpty)
                              Positioned(
                                bottom: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    p.category!,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            // Qoldiq belgisi (Stock badge)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: out
                                      ? const Color(0xFFE53935)
                                      : Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2)),
                                  ],
                                ),
                                child: Text(
                                  out ? 'Tugagan' : 'Qoldiq: ${qty(p.stock)} ${_u(p.unit)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            // Katta ko'rish (Zoom preview) tugmasi agar rasm bo'lsa
                            if (p.imageUrl != null && p.imageUrl!.trim().isNotEmpty)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Material(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => showProductImagePreview(
                                      context,
                                      imageUrl: p.imageUrl,
                                      name: p.name,
                                      subtitle: '${money(p.price)} / ${_u(p.unit)} • Qoldiq: ${qty(p.stock)} ${_u(p.unit)}',
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.all(5),
                                      child: Icon(Icons.fullscreen_rounded, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Mahsulot matni va narxi
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.22,
                                  color: context.inkColor,
                                ),
                              ),
                              if (p.sortLabel.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: context.isDark ? const Color(0xFF332512) : const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      p.sortLabel,
                                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                                    ),
                                  ),
                                )
                              else if (p.color != null && p.color!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: StoneColorBadge(colorName: p.color!, fontSize: 9.5),
                                ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          money(p.price),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: context.isDark ? AppColors.neonLime : AppColors.ink,
                                          ),
                                        ),
                                        Text(
                                          '${moneyUsd(context.watch<CurrencyController>().toUsd(p.price))} / ${_u(p.unit)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.mutedColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: EdgeInsets.symmetric(horizontal: inCart ? 8 : 0),
                                    height: 34,
                                    constraints: const BoxConstraints(minWidth: 34),
                                    decoration: BoxDecoration(
                                      color: inCart
                                          ? const Color(0xFFF59E0B) // Savatda bo'lsa sariq / amber
                                          : (lifted
                                              ? AppColors.neonLime
                                              : (context.isDark ? const Color(0xFF21262D) : AppColors.darkCard)),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: inCart
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: inCart
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.shopping_cart_rounded,
                                                color: Color(0xFF161B22),
                                                size: 15,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                qty(inCartCount),
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFF161B22),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Icon(
                                            Icons.add_shopping_cart_rounded,
                                            color: lifted ? AppColors.ink : Colors.white,
                                            size: 16,
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.hint});
  final IconData icon;
  final String title, hint;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: AppColors.green),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(hint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Savat
// ---------------------------------------------------------------------------

class _CartPanel extends StatelessWidget {
  const _CartPanel({required this.onSold});
  final VoidCallback onSold;

  Future<void> _editQty(BuildContext context, CartLine l) async {
    final cart = context.read<CartController>();
    final ctrl = TextEditingController(text: qty(l.quantity));
    var inDona = l.inDona;
    var inPachka = l.inPachka;
    final canPachka = l.product.hasPachka || l.product.unit == 'm2' || l.product.unit == 'm²';
    final boxSize = l.product.effectiveBoxM2 ?? 1.44;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: context.cardColor,
          surfaceTintColor: Colors.transparent,
          shape: _dialogShape,
          title: Text(l.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Miqdor (${inPachka ? "pachka" : (inDona ? "dona" : _u(l.product.unit))})',
                ),
                onChanged: (_) => setS(() {}),
              ),
              if (canPachka || l.product.hasDona) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'base', label: Text(_u(l.product.unit))),
                    if (canPachka)
                      ButtonSegment(
                        value: 'pachka',
                        label: Text('pachka (${qty(boxSize)} m²)'),
                      ),
                    if (l.product.hasDona)
                      ButtonSegment(
                        value: 'dona',
                        label: Text('dona (${qty(l.product.donaM2!)} m²)'),
                      ),
                  ],
                  selected: {inPachka ? 'pachka' : (inDona ? 'dona' : 'base')},
                  onSelectionChanged: (s) {
                    setS(() {
                      final cur = parseInput(ctrl.text) ?? 0;
                      final box = boxSize;
                      final dona = l.product.donaM2 ?? (box / 2.0);

                      // Asosiy m2 ga aylantirish
                      double currentBase = cur;
                      if (inPachka) {
                        currentBase = cur * box;
                      } else if (inDona) {
                        currentBase = cur * dona;
                      }

                      final target = s.first;
                      if (target == 'pachka') {
                        inPachka = true;
                        inDona = false;
                        ctrl.text = qty(_roundClean(currentBase / box));
                      } else if (target == 'dona') {
                        inPachka = false;
                        inDona = true;
                        ctrl.text = qty(_roundClean(currentBase / dona));
                      } else {
                        inPachka = false;
                        inDona = false;
                        ctrl.text = qty(_roundClean(currentBase));
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final cur = parseInput(ctrl.text) ?? 0;
                  final box = boxSize;
                  final propText = inPachka
                      ? '${qty(cur)} pachka = ${qty(_roundClean(cur * box))} m²'
                      : (inDona
                          ? '${qty(cur)} dona = ${qty(_roundClean(cur * (l.product.donaM2 ?? (box / 2.0))))} m²'
                          : '${qty(cur)} m² = ${qty(_roundClean(cur / box))} pachka');
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (context.isDark ? AppColors.neonLime : const Color(0xFF0D9488)).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '🔄 Proporsional: $propText',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.isDark ? AppColors.neonLime : const Color(0xFF0F766E),
                      ),
                    ),
                  );
                }),
              ],
              if ((l.product.unit == 'm2' || l.product.unit == 'm²') && l.product.category != 'Xizmat') ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx, false);
                    _openStoneService(context, l.product);
                  },
                  icon: const Icon(Icons.design_services_rounded, size: 16),
                  label: const Text('✂️ Toshga ishlov berish xizmatlari'),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    final v = parseInput(ctrl.text);
    ctrl.dispose();
    if (ok == true && v != null && v > 0) {
      cart.update(l, quantity: v, inDona: inDona, inPachka: inPachka);
    }
  }

  Future<void> _openCutCalculator(BuildContext context, CartLine l) async {
    final cart = context.read<CartController>();
    // Bo'yi faqat santimetrda (sm), Eni esa metrda (m) kiritiladi va hisoblanadi
    final initialLenSm = l.cutLength != null ? (l.cutLength! * 100) : 120.0;
    final lengthCtrl = TextEditingController(
      text: initialLenSm % 1 == 0 ? initialLenSm.toInt().toString() : initialLenSm.toString(),
    );
    final initialWidM = l.cutWidth != null ? l.cutWidth! : 0.6;
    final widthCtrl = TextEditingController(
      text: initialWidM % 1 == 0 ? initialWidM.toInt().toString() : initialWidM.toString(),
    );
    final countCtrl = TextEditingController(text: l.cutPieces != null ? l.cutPieces.toString() : '1');
    final initialThickness = l.cutThickness ?? l.product.thickness ?? 2.0;
    final thicknessCtrl = TextEditingController(
      text: initialThickness > 0
          ? (initialThickness % 1 == 0 ? initialThickness.toInt().toString() : initialThickness.toString())
          : '2.0',
    );

    double calcArea() {
      final lenSm = parseInput(lengthCtrl.text) ?? 0;
      final widM = parseInput(widthCtrl.text) ?? 0;
      final cnt = parseInput(countCtrl.text) ?? 1;
      final lenM = lenSm / 100; // Bo'yi faqat sm dan metrga
      return (lenM * widM * cnt);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final area = calcArea();
          final lineSum = area * l.unitPrice;

          return AlertDialog(
            backgroundColor: context.cardColor,
            shape: _dialogShape,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.neonLime.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.straighten_rounded, color: AppColors.ink, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Razmer / Kesish Kalkulyatori', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(l.displayName, style: TextStyle(fontSize: 12, color: context.subtextColor)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.isDark ? const Color(0xFF21262D) : const Color(0xFFEFF2F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.straighten_rounded, size: 16, color: context.isDark ? AppColors.neonLime : AppColors.ink),
                          const SizedBox(width: 8),
                          Text(
                            'Bo‘yi faqat santimetrda (sm) · Eni metrda (m)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.inkColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: lengthCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Bo‘yi (sm)',
                              hintText: '120',
                              suffixText: 'sm',
                            ),
                            onChanged: (_) => setS(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: widthCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Eni (m)',
                              hintText: '0.6',
                              suffixText: 'm',
                            ),
                            onChanged: (_) => setS(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: countCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Soni (dona)',
                              hintText: '1',
                              prefixIcon: Icon(Icons.pin_rounded, size: 18),
                            ),
                            onChanged: (_) => setS(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: thicknessCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Qalinligi (sm)',
                              hintText: '2.0',
                              prefixIcon: Icon(Icons.layers_outlined, size: 18),
                            ),
                            onChanged: (_) => setS(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.neonLime.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.neonLime.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Hisoblangan maydon:', style: TextStyle(fontSize: 13, color: context.inkColor)),
                              Text(
                                '${area.toStringAsFixed(3)} m²',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: context.isDark ? AppColors.neonLime : AppColors.ink),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Jami summa:', style: TextStyle(fontSize: 12, color: context.subtextColor)),
                              Text(
                                money(lineSum),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.green),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Bekor'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                  foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('Qo‘llash', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true && context.mounted) {
      final lenSm = parseInput(lengthCtrl.text) ?? 0;
      final widM = parseInput(widthCtrl.text) ?? 0;
      final cnt = (parseInput(countCtrl.text) ?? 1).toInt();
      final thick = parseInput(thicknessCtrl.text) ?? initialThickness;
      final lenM = lenSm / 100;
      final area = lenM * widM * cnt;
      if (area > 0) {
        final thickStr = thick > 0 ? '${thick % 1 == 0 ? thick.toInt() : thick} sm' : '';
        final lenStr = '${lenSm % 1 == 0 ? lenSm.toInt() : lenSm} sm';
        final widStr = '${widM % 1 == 0 ? widM.toInt() : widM} m';
        final spec = thickStr.isNotEmpty
            ? '$lenStr × $widStr ($thickStr, $cnt dona)'
            : '$lenStr × $widStr ($cnt dona)';
        cart.update(
          l,
          quantity: double.parse(area.toStringAsFixed(3)),
          cutLength: lenM,
          cutWidth: widM,
          cutThickness: thick,
          cutPieces: cnt,
          cutSpec: spec,
        );
      }
    }
  }

  Future<void> _openStoneService(BuildContext context, Product p) async {
    final user = context.read<AuthController>().user;
    if (user != null) {
      await StoneServicesDialog.show(context, user: user, product: p);
    }
  }

  Future<void> _checkout(BuildContext context) async {
    final cart = context.read<CartController>();
    final result = await showDialog<_CheckoutInput>(context: context, builder: (_) => _CheckoutDialog(total: cart.total));
    if (result == null || !context.mounted) return;
    try {
      final res = await cart.checkout(
        paid: result.paid,
        currencyRate: result.currencyRate,
        paidUzs: result.paidUzs,
        paidUsd: result.paidUsd,
        status: result.status,
        note: result.note,
        customerId: result.customerId,
        customerName: result.name,
        customerPhone: result.phone,
        customerPassport: result.passport,
        customerPhotoUrl: result.photoUrl,
      );
      if (!context.mounted) return;
      if (res.isOrder) {
        showMessage(context, 'Buyurtma #${res.id} muvaffaqiyatli saqlandi. Avans: ${money(res.paid)}');
      } else {
        showMessage(context, 'Savdo #${res.id} saqlandi. To‘landi: ${money(res.paid)}'
            '${res.debt > 0 ? ', nasiya: ${money(res.debt)}' : ''}');
      }
      onSold();
      await ReceiptDialog.show(context, res);
    } catch (e) {
      if (context.mounted) showMessage(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final empty = cart.lines.isEmpty;
    final isCompact = MediaQuery.sizeOf(context).width < 500;
    return Container(
      padding: EdgeInsets.all(isCompact ? 14 : 20),
      decoration: _cardBox(radius: 24),
      child: Column(children: [
        Row(children: [
          const Text('Savat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: empty
                ? const SizedBox.shrink(key: ValueKey('none'))
                : Container(
                    key: ValueKey(cart.lines.length),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(20)),
                    child: Text('${cart.lines.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.darkCard, fontSize: 11.5)),
                  ),
          ),
          const Spacer(),
          if (!empty) ...[
            Tooltip(
              message: 'Kutishga qo‘yish',
              child: InkWell(
                onTap: () {
                  cart.holdCurrentCart();
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⏸ 1-mijoz savati kutishga saqlandi. Yangi mijoz uchun savat tayyor!'),
                      backgroundColor: Color(0xFFD97706),
                      duration: Duration(seconds: 3),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pause_circle_outline_rounded, size: 16, color: Color(0xFFD97706)),
                      const SizedBox(width: 4),
                      Text(
                        isCompact ? 'Kutish' : 'Kutishga qo‘yish',
                        style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w700, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Tooltip(
            message: 'Savatni tozalash',
            child: InkWell(
              onTap: empty ? null : cart.clear,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 16, color: empty ? context.mutedColor.withValues(alpha: 0.4) : AppColors.muted),
                    const SizedBox(width: 3),
                    Text(
                      'Tozalash',
                      style: TextStyle(
                        color: empty ? context.mutedColor.withValues(alpha: 0.4) : AppColors.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
        if (cart.heldCarts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF281E10) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFD97706).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pause_circle_filled_rounded, size: 15, color: Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Kutilayotgan mijozlar (${cart.heldCarts.length})',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD97706),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tiklash uchun bosing',
                      style: TextStyle(fontSize: 10, color: context.mutedColor),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final h in cart.heldCarts)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              cart.restoreHeldCart(h);
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ ${h.label} savati qayta tiklandi!'),
                                  backgroundColor: AppColors.green,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: context.isDark ? const Color(0xFF382A14) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFD97706).withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${h.label} · ${money(h.total)} (${h.count})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: context.inkColor,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () {
                                      cart.removeHeldCart(h);
                                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Kutilayotgan savat o‘chirildi.'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    child: Icon(Icons.close_rounded, size: 14, color: context.mutedColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: empty
              ? const _EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'Savat bo‘sh',
                  hint: 'Mahsulotni bosing yoki QR kodni kiriting')
              : ListView(children: [
                  for (final l in cart.lines)
                    _CartLineTile(
                      key: ObjectKey(l),
                      line: l,
                      onEdit: () => _editQty(context, l),
                      onCutCalculator: () => _openCutCalculator(context, l),
                      onStoneService: () => _openStoneService(context, l.product),
                    ),
                ]),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Jami', style: TextStyle(color: Color(0xFFA9BDB0), fontSize: 13)),
              const Spacer(),
              Text('${cart.lines.length} ta mahsulot', style: const TextStyle(color: Color(0xFFA9BDB0), fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: cart.total),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) {
                final rate = context.watch<CurrencyController>().usdRate;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(money(v), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                    ),
                    if (v > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '≈ ${moneyUsd(v / (rate > 0 ? rate : 1))}',
                          style: const TextStyle(color: AppColors.neonLime, fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (empty || cart.busy) ? null : () => _checkout(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.neonLime,
                  foregroundColor: AppColors.ink,
                  disabledBackgroundColor: const Color(0xFF22262B),
                  disabledForegroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                icon: cart.busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                    : const Icon(Icons.payments_rounded, color: AppColors.ink),
                label: const Text('To‘lovni qabul qilish', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    super.key,
    required this.line,
    required this.onEdit,
    this.onCutCalculator,
    this.onStoneService,
  });
  final CartLine line;
  final VoidCallback onEdit;
  final VoidCallback? onCutCalculator;
  final VoidCallback? onStoneService;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final l = line;
    final p = l.product;
    final short = l.baseQty > p.stock;
    final sub = l.inPachka
        ? '${money(l.unitPrice)} / ${_u(p.unit)}  ·  ${qty(l.baseQty)} ${_u(p.unit)} (${qty(l.quantity)} pachka)'
        : '${money(l.unitPrice)} / ${_u(p.unit)}${l.inDona ? '  ·  ${qty(l.baseQty)} ${_u(p.unit)}' : ''}';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset((1 - t) * 24, 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: short ? AppColors.danger : context.borderColor.withOpacity(0.6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(
              onTap: () => showProductImagePreview(
                context,
                imageUrl: p.imageUrl,
                name: p.name,
                subtitle: '${money(p.price)} / ${_u(p.unit)} • Savatda: ${qty(line.quantity)} ${_u(p.unit)}',
              ),
              child: ProductThumbnail(
                imageUrl: p.imageUrl,
                name: p.name,
                size: 38,
                borderRadius: 10,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.inkColor),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: context.subtextColor),
                      ),
                    ),
                    if (p.sortLabel.isNotEmpty || (l.sort != null && l.sort!.isNotEmpty)) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF332512) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          l.sort != null && l.sort!.isNotEmpty
                              ? (l.sort == 'oliy' ? 'Oliy sort' : '${l.sort}-sort')
                              : p.sortLabel,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                        ),
                      ),
                    ],
                  ],
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Olib tashlash',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: context.subtextColor),
              onPressed: () => cart.remove(l),
            ),
          ]),

          if (p.hasPachka) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('O‘lchov: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.subtextColor)),
                ChoiceChip(
                  label: const Text('m²', style: TextStyle(fontSize: 10.5)),
                  selected: !l.inPachka,
                  visualDensity: VisualDensity.compact,
                  onSelected: (sel) {
                    if (sel && l.inPachka) {
                      cart.update(l, inPachka: false, quantity: _roundClean(l.baseQty));
                    }
                  },
                ),
                ChoiceChip(
                  label: Text(
                    'Pachka (${p.effectiveBoxM2 != null ? '${qty(p.effectiveBoxM2!)} m²' : ''})',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                  selected: l.inPachka,
                  visualDensity: VisualDensity.compact,
                  onSelected: (sel) {
                    if (sel && !l.inPachka) {
                      final box = p.effectiveBoxM2 ?? 1.0;
                      final pQty = l.quantity / box;
                      cart.update(l, inPachka: true, quantity: _roundClean(pQty));
                    }
                  },
                ),
              ],
            ),
          ],

          // Variant / Rang va Toshga ishlov (bitta qatorda, "Rang:" so'zisiz)
          if ((p.availableColors.length > 1) ||
              (l.color != null && l.color!.isNotEmpty) ||
              (onStoneService != null && p.category != 'Xizmat')) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 1. Rang yoki Sort/Variant tanlovi
                if (p.availableColors.length > 1) ...[
                  for (final col in p.availableColors)
                    ChoiceChip(
                      avatar: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: getStoneColor(col),
                          shape: BoxShape.circle,
                        ),
                      ),
                      label: Text(col, style: const TextStyle(fontSize: 10.5)),
                      selected: (l.color ?? p.availableColors.first) == col,
                      onSelected: (sel) {
                        if (sel) cart.update(l, color: col);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                ] else if (l.color != null && l.color!.isNotEmpty) ...[
                  StoneColorBadge(colorName: l.color!, fontSize: 10),
                ],

                // 2. Toshga ishlov berish xizmatlari (kesish, faska, silliqlash)
                if (onStoneService != null && p.category != 'Xizmat') ...[
                  InkWell(
                    onTap: onStoneService,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.borderColor.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.design_services_rounded,
                            size: 13,
                            color: context.subtextColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '✂️ Toshga ishlov',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: context.subtextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 6),
          Row(children: [
            Material(
              color: context.isDark ? const Color(0xFF242C38) : const Color(0xFFEFF2F6),
              borderRadius: BorderRadius.circular(12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _StepBtn(icon: Icons.remove_rounded, onTap: () {
                  final q = l.quantity - 1;
                  if (q > 0) {
                    cart.update(l, quantity: q);
                  } else {
                    cart.remove(l);
                  }
                }),
                InkWell(
                  onTap: onEdit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(qty(l.quantity), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.inkColor)),
                  ),
                ),
                _StepBtn(icon: Icons.add_rounded, onTap: () => cart.update(l, quantity: l.quantity + 1)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    money(l.lineTotal),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: context.inkColor),
                  ),
                ),
              ),
            ),
          ]),
          if (short)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('⚠ Omborda yetarli emas', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 18, color: context.inkColor)),
      );
}

// ---------------------------------------------------------------------------
// To'lov oynasi
// ---------------------------------------------------------------------------

class _CheckoutInput {
  final double paid;
  final double? currencyRate;
  final double? paidUzs;
  final double? paidUsd;
  final String status;
  final String? note;
  final int? customerId;
  final String? name;
  final String? phone;
  final String? passport;
  final String? photoUrl;

  _CheckoutInput({
    required this.paid,
    this.currencyRate,
    this.paidUzs,
    this.paidUsd,
    this.status = 'completed',
    this.note,
    this.customerId,
    this.name,
    this.phone,
    this.passport,
    this.photoUrl,
  });
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({required this.total});
  final double total;
  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  late final _paidUzs = TextEditingController(text: widget.total.round().toString());
  final _paidUsd = TextEditingController(text: '0');
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _passport = TextEditingController();
  final _note = TextEditingController();
  bool _isOrder = false;
  String? _photoUrl;
  int? _selectedCustomerId;
  List<Customer> _existingCustomers = [];
  bool _uploadingImage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final list = await context.read<AppRepositories>().customers.listCustomers();
      if (mounted) {
        setState(() {
          _existingCustomers = list;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _paidUzs.dispose();
    _paidUsd.dispose();
    _name.dispose();
    _phone.dispose();
    _passport.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setPaidUzs(double v) {
    setState(() {
      _paidUzs.text = v.round().toString();
      _paidUsd.text = '0';
      _error = null;
    });
  }

  void _setPaidUsd(double v) {
    setState(() {
      _paidUsd.text = v.toStringAsFixed(2);
      _paidUzs.text = '0';
      _error = null;
    });
  }

  void _setSplit(double uzs, double usd) {
    setState(() {
      _paidUzs.text = uzs.round().toString();
      _paidUsd.text = usd.toStringAsFixed(2);
      _error = null;
    });
  }

  void _selectCustomer(Customer c) {
    setState(() {
      _selectedCustomerId = c.id;
      _name.text = c.name;
      _phone.text = c.phone ?? '';
      _passport.text = c.passport ?? '';
      _photoUrl = c.photoUrl;
      _error = null;
    });
  }

  void _clearCustomer() {
    setState(() {
      _selectedCustomerId = null;
      _name.clear();
      _phone.clear();
      _passport.clear();
      _photoUrl = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final custRepo = context.read<AppRepositories>().customers;
    setState(() {
      _uploadingImage = true;
      _error = null;
    });
    try {
      final bytes = await pickOrCaptureCustomerImage(context, source);
      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _uploadingImage = false);
        return;
      }

      String finalUrl;
      try {
        final decoded = img.decodeImage(Uint8List.fromList(bytes));
        if (decoded != null) {
          final resized = (decoded.width > 480 || decoded.height > 480)
              ? img.copyResize(decoded, width: decoded.width >= decoded.height ? 480 : null, height: decoded.height > decoded.width ? 480 : null)
              : decoded;
          final jpg = img.encodeJpg(resized, quality: 78);
          finalUrl = 'data:image/jpeg;base64,${base64Encode(jpg)}';
        } else {
          finalUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        }
      } catch (_) {
        finalUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      LocalImageStore.saveCustomerImage(_selectedCustomerId, finalUrl, _phone.text, _name.text);

      if (mounted) {
        setState(() {
          _photoUrl = finalUrl;
          _uploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Rasm olishda xatolik: $e';
          _uploadingImage = false;
        });
      }
    }
  }

  void _ok() {
    final rate = context.read<CurrencyController>().usdRate;
    final paidUzsVal = parseInput(_paidUzs.text) ?? 0.0;
    final paidUsdVal = parseInput(_paidUsd.text) ?? 0.0;
    if (paidUzsVal < 0 || paidUsdVal < 0) {
      setState(() {
        _error = 'To‘lov manfiy bo‘lishi mumkin emas';
      });
      return;
    }
    final totalEquivalent = paidUzsVal + (paidUsdVal * rate);
    final debt = (widget.total - totalEquivalent).clamp(0, double.infinity).toDouble();
    if (_isOrder) {
      if (_name.text.trim().isEmpty) {
        setState(() {
          _error = 'Buyurtma uchun mijoz ismini kiritish shart';
        });
        return;
      }
    } else {
      if (debt > 0.5 && _name.text.trim().isEmpty) {
        setState(() {
          _error = 'Nasiya uchun mijoz ismini kiriting';
        });
        return;
      }
    }
    final effectivePaid = totalEquivalent > widget.total ? widget.total : totalEquivalent;
    Navigator.pop(
      context,
      _CheckoutInput(
        paid: effectivePaid,
        currencyRate: rate,
        paidUzs: paidUzsVal,
        paidUsd: paidUsdVal,
        status: _isOrder ? 'order' : 'completed',
        note: _note.text.trim().isNotEmpty ? _note.text.trim() : null,
        customerId: _selectedCustomerId,
        name: _name.text.trim().isNotEmpty ? _name.text.trim() : null,
        phone: _phone.text.trim().isNotEmpty ? _phone.text.trim() : null,
        passport: _passport.text.trim().isNotEmpty ? _passport.text.trim() : null,
        photoUrl: _photoUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rate = context.watch<CurrencyController>().usdRate;
    final totalUsd = rate > 0 ? widget.total / rate : 0.0;
    final paidUzsVal = parseInput(_paidUzs.text) ?? 0.0;
    final paidUsdVal = parseInput(_paidUsd.text) ?? 0.0;
    final totalPaidEquivalent = paidUzsVal + (paidUsdVal * rate);
    final diff = totalPaidEquivalent - widget.total;
    final isOverpaid = diff > 0.5;
    final hasDebt = diff < -0.5;
    final debt = hasDebt ? -diff : 0.0;
    final change = isOverpaid ? diff : 0.0;

    return AlertDialog(
      backgroundColor: context.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: _dialogShape,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _isOrder ? 'Buyurtma rasmiylashtirish' : 'To‘lovni qabul qilish',
          style: const TextStyle(fontSize: 14, color: AppColors.muted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            Text(money(widget.total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.green)),
            Text('≈ ${moneyUsd(totalUsd)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('\$1 = ${money(rate)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
            ),
          ],
        ),
      ]),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Savdo yoki Buyurtma tanlash
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF21262D) : const Color(0xFFEFF2F6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        _isOrder = false;
                        _error = null;
                        if (_paidUzs.text.isEmpty && _paidUsd.text.isEmpty) {
                          _paidUzs.text = widget.total.round().toString();
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_isOrder
                              ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Darhol Sotuv',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: !_isOrder
                                ? (context.isDark ? AppColors.ink : Colors.white)
                                : context.inkColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        _isOrder = true;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _isOrder
                              ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.assignment_rounded,
                              size: 15,
                              color: _isOrder
                                  ? (context.isDark ? AppColors.ink : Colors.white)
                                  : context.inkColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Buyurtma (Pre-order)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _isOrder
                                    ? (context.isDark ? AppColors.ink : Colors.white)
                                    : context.inkColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // To'lov kiritish (So'm va Dollar ikkalasi ham mavjud)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _paidUzs,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _isOrder ? 'Avans (So‘m)' : 'To‘lov (So‘m)',
                      prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _paidUsd,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _isOrder ? 'Avans (\$ USD)' : 'To‘lov (\$ USD)',
                      prefixIcon: const Icon(Icons.attach_money_rounded, size: 20, color: Color(0xFF10B981)),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Tezkor to'lov tugmalari
            Wrap(spacing: 8, runSpacing: 6, children: [
              ActionChip(
                avatar: const Icon(Icons.payments_rounded, size: 14),
                label: Text(_isOrder ? 'To‘liq avans (So‘m)' : 'To‘liq so‘mda'),
                onPressed: () => _setPaidUzs(widget.total),
              ),
              ActionChip(
                avatar: const Icon(Icons.attach_money_rounded, size: 14, color: Color(0xFF10B981)),
                label: Text(_isOrder ? 'To‘liq (\$ USD)' : 'To‘liq dollarda (${moneyUsd(totalUsd)})'),
                onPressed: () => _setPaidUsd(totalUsd),
              ),
              ActionChip(
                label: const Text('50% / 50% aralash'),
                onPressed: () => _setSplit(widget.total / 2, (widget.total / 2) / rate),
              ),
              ActionChip(
                label: Text(_isOrder ? 'Avanssiz (0)' : 'Hammasi nasiya'),
                onPressed: () => _setSplit(0, 0),
              ),
            ]),
            const SizedBox(height: 12),

            // Holat va hisob-kitob ko'rsatkichi
            if (_isOrder)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 20, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Buyurtma holati',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mahsulotlar ombordan topshirilganda yechiladi. Qabul qilingan avans: ${money(totalPaidEquivalent)} (≈ ${moneyUsd(totalPaidEquivalent / rate)}). Qoldiq: ${money(debt)}.',
                            style: TextStyle(fontSize: 11.5, color: context.inkColor, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isOverpaid
                      ? const Color(0xFFE8F5E9)
                      : (hasDebt ? const Color(0xFFFFF1DC) : AppColors.greenSoft),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isOverpaid
                        ? const Color(0xFF4CAF50).withOpacity(0.3)
                        : (hasDebt ? const Color(0xFFFFA000).withOpacity(0.3) : Colors.transparent),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    isOverpaid
                        ? Icons.price_check_rounded
                        : (hasDebt ? Icons.schedule_rounded : Icons.check_circle_rounded),
                    size: 20,
                    color: isOverpaid
                        ? const Color(0xFF2E7D32)
                        : (hasDebt ? const Color(0xFFC77700) : AppColors.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOverpaid
                              ? 'Qaytim berilishi kerak: ${money(change)} (≈ ${moneyUsd(change / rate)})'
                              : (hasDebt
                                  ? 'Nasiya (qarz): ${money(debt)} (≈ ${moneyUsd(debt / rate)})'
                                  : 'To‘liq to‘landi (0 qoldiq)'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isOverpaid
                                ? const Color(0xFF1B5E20)
                                : (hasDebt ? const Color(0xFFB45309) : AppColors.ink),
                          ),
                        ),
                        if (paidUsdVal > 0)
                          Text(
                            'To‘landi: ${money(paidUzsVal)} + ${moneyUsd(paidUsdVal)} (Jami: ${money(totalPaidEquivalent)})',
                            style: TextStyle(fontSize: 11, color: context.mutedColor),
                          ),
                      ],
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 16),

            // Buyurtma izohi / topshirish muddati
            if (_isOrder) ...[
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Buyurtma izohi / topshirish muddati',
                  hintText: 'Masalan: 3 kundan keyin olib ketadi, o‘lchami...',
                  prefixIcon: Icon(Icons.event_note_rounded),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Mijoz ma'lumotlari sarlavhasi
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(
                  'Xaridor ma‘lumotlari',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.inkColor),
                ),
                const Spacer(),
                if (_selectedCustomerId != null)
                  TextButton.icon(
                    onPressed: _clearCustomer,
                    icon: const Icon(Icons.person_add_rounded, size: 15),
                    label: const Text('Yangi mijoz', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Doimiy mijozlarni tezkor tanlash
            if (_existingCustomers.isNotEmpty && _selectedCustomerId == null) ...[
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _existingCustomers.take(5).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final c = _existingCustomers[i];
                    return ActionChip(
                      avatar: const Icon(Icons.history_rounded, size: 14),
                      label: Text(c.name, style: const TextStyle(fontSize: 11)),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onPressed: () => _selectCustomer(c),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Ism
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: hasDebt ? 'Mijoz Ism-Familiyasi * (Nasiya uchun majburiy)' : 'Mijoz Ism-Familiyasi',
                hintText: 'Masalan: Rustam Karimov',
                prefixIcon: const Icon(Icons.person_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 10),

            // Telefon
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefon raqami',
                hintText: '+998 90 123 45 67',
                prefixIcon: Icon(Icons.phone_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 10),

            // Pasport
            TextField(
              controller: _passport,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Pasport seriya va raqami',
                hintText: 'AA 1234567',
                prefixIcon: Icon(Icons.badge_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 12),

            // Pasport / Mijoz fotosurati qismi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1E2822) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.camera_alt_outlined, size: 16, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text(
                        'Pasport / Mijoz surati',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.inkColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_photoUrl != null && _photoUrl!.isNotEmpty) ...[
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => showProductImagePreview(
                            context,
                            imageUrl: _photoUrl,
                            name: _name.text.isNotEmpty ? _name.text : 'Xaridor surati',
                            subtitle: 'Pasport: ${_passport.text.isNotEmpty ? _passport.text : 'Yo‘q'}',
                          ),
                          child: ProductThumbnail(
                            imageUrl: _photoUrl,
                            name: _name.text,
                            size: 64,
                            borderRadius: 14,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Rasm saqlandi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.green)),
                              const SizedBox(height: 2),
                              const Text('To‘liq ko‘rish uchun rasmni bosing', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _pickImage(ImageSource.camera),
                                    child: const Text('Qayta olish', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.green)),
                                  ),
                                  const SizedBox(width: 14),
                                  InkWell(
                                    onTap: () => setState(() => _photoUrl = null),
                                    child: const Text('O‘chirish', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.danger)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    if (_uploadingImage)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Text('Rasm yuklanmoqda...', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_rounded, size: 16),
                              label: const Text('Kamera', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_rounded, size: 16),
                              label: const Text('Galereya', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        FilledButton.icon(
          onPressed: _ok,
          style: FilledButton.styleFrom(
            backgroundColor: _isOrder
                ? (context.isDark ? AppColors.neonLime : const Color(0xFF2563EB))
                : (context.isDark ? AppColors.neonLime : AppColors.darkCard),
            foregroundColor: _isOrder
                ? (context.isDark ? AppColors.ink : Colors.white)
                : (context.isDark ? AppColors.ink : Colors.white),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
          icon: Icon(_isOrder ? Icons.assignment_turned_in_rounded : Icons.check_circle_rounded, size: 18),
          label: Text(
            _isOrder ? 'Buyurtmani saqlash' : 'Tasdiqlash',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Windows / Katta ekranlar uchun USB Skaner dialogi (F2)
// ---------------------------------------------------------------------------

class _DesktopQrScannerDialog extends StatefulWidget {
  const _DesktopQrScannerDialog({required this.onCartUpdated});
  final VoidCallback onCartUpdated;

  @override
  State<_DesktopQrScannerDialog> createState() => _DesktopQrScannerDialogState();
}

class _DesktopQrScannerDialogState extends State<_DesktopQrScannerDialog> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();

  String? _statusMessage;
  bool _isError = false;
  Product? _lastProduct;
  double _lastQty = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _processCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    if (isReceiptQr(code)) {
      final saleId = extractSaleId(code);
      if (saleId != null) {
        try {
          final sales = await context.read<AppRepositories>().sales.listSales(limit: 500);
          final matched = sales.where((s) => s.id == saleId).firstOrNull;
          if (matched != null && mounted) {
            HapticFeedback.mediumImpact();
            SystemSound.play(SystemSoundType.click);
            _inputCtrl.clear();
            await ReceiptDialog.show(context, matched);
            return;
          }
        } catch (_) {}
      }
    }

    try {
      final repo = context.read<AppRepositories>().products;
      final p = await repo.findByCode(code);
      if (!mounted) return;

      if (p != null) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);

        context.read<CartController>().add(p, quantity: 1);
        widget.onCartUpdated();

        setState(() {
          _isError = false;
          _statusMessage = '“${p.name}” savatga qo‘shildi (+1 ${_u(p.unit)})';
          _lastProduct = p;
          _lastQty = 1.0;
          _inputCtrl.clear();
        });
        _focusNode.requestFocus();
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _isError = true;
          _statusMessage = 'Mahsulot topilmadi: "$code"';
        });
        _focusNode.requestFocus();
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
      });
    } else if (delta < 0) {
      final existing = cart.lines.where((l) => l.product.id == p.id);
      if (existing.isNotEmpty) {
        final l = existing.first;
        if (l.quantity + delta > 0.001) {
          cart.update(l, quantity: l.quantity + delta);
          setState(() {
            _lastQty += delta;
          });
        } else {
          cart.remove(l);
          setState(() {
            _lastProduct = null;
            _lastQty = 1.0;
          });
        }
      }
    }
    widget.onCartUpdated();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();

    return Dialog(
      backgroundColor: context.dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.isDark ? const Color(0xFF132D21) : AppColors.greenSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.green, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'QR / Barkod skaneri',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'USB skaner yoki kod kiritish (F2)',
                          style: TextStyle(fontSize: 12, color: context.mutedColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF0F1A24) : const Color(0xFFF1F6FB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.usb_rounded, color: AppColors.info, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'USB 2D / Lazer skaner tayyor. Shtrix-kod yoki QR kodni skanerlang',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _inputCtrl,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(fontSize: 13, color: context.inkColor, fontWeight: FontWeight.w600),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: context.cardColor,
                          hintText: 'Skanerlang yoki kod yozing (masalan: STX-ANGOLA)...',
                          hintStyle: const TextStyle(fontSize: 12, color: AppColors.muted),
                          prefixIcon: const Icon(Icons.qr_code_rounded, size: 20, color: AppColors.muted),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: context.borderColor)),
                        ),
                        onSubmitted: _processCode,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: () => _processCode(_inputCtrl.text),
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 17),
                      label: const Text('Qo‘shish', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                        foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                ],
              ),
              if (_statusMessage != null && _isError) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF331616) : const Color(0xFFFCE4E3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_lastProduct != null) ...[
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: AppColors.green),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Oxirgi skanerlangan mahsulot',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.green),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.isDark ? const Color(0xFF132D21) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (context.isDark ? AppColors.greenBright : AppColors.green).withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.isDark ? const Color(0xFF0C2016) : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _lastProduct!.name.isNotEmpty ? _lastProduct!.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _lastProduct!.name,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${money(_lastProduct!.price)} / ${_u(_lastProduct!.unit)} • Qoldiq: ${qty(_lastProduct!.stock)} ${_u(_lastProduct!.unit)}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: context.isDark ? const Color(0xFF0E2218) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: context.borderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_rounded, size: 16),
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  splashRadius: 14,
                                  onPressed: () => _updateLastQty(-1),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    qty(_lastQty),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_rounded, size: 16),
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
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cart.lines.isNotEmpty ? 'Savatda: ${cart.lines.length} ta tovar • ${money(cart.total)}' : 'Savat bo‘sh',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cart.lines.isNotEmpty ? AppColors.green : context.mutedColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                      foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Tayyor (Yopish)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}