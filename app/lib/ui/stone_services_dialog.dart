import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import '../state/cart_controller.dart';
import 'common.dart';

/// Toshga ishlov berish xizmatlari modeli
class StoneServiceDef {
  final String key;
  final String name;
  final String unit;
  final String description;
  final IconData icon;
  final String? assetIcon;
  final double defaultPrice;
  final int defaultProductId;

  const StoneServiceDef({
    required this.key,
    required this.name,
    required this.unit,
    required this.description,
    required this.icon,
    this.assetIcon,
    required this.defaultPrice,
    required this.defaultProductId,
  });
}

const List<StoneServiceDef> kStoneServices = [
  StoneServiceDef(
    key: 'cut',
    name: 'Razmer kesish',
    unit: 'm²',
    description: 'Eni va bo‘yi bo‘yicha plita va toshlarni aniq o‘lchamda kesish',
    icon: Icons.content_cut_rounded,
    assetIcon: 'assets/icons/service_cut.png',
    defaultPrice: 25000,
    defaultProductId: 24,
  ),
  StoneServiceDef(
    key: 'chamfer',
    name: 'Faska ochish',
    unit: 'metr',
    description: 'Zinapoya, podokonnik yoki plita chetlariga faska (qirra) berish',
    icon: Icons.architecture_rounded,
    assetIcon: 'assets/icons/service_chamfer.png',
    defaultPrice: 20000,
    defaultProductId: 20,
  ),
  StoneServiceDef(
    key: 'polish',
    name: 'Silliqlash',
    unit: 'metr',
    description: 'Granit va Keramogranit toshlari yuzasi yoki qirrasini jilolash',
    icon: Icons.auto_awesome_rounded,
    defaultPrice: 25000,
    defaultProductId: 21,
  ),
  StoneServiceDef(
    key: 'groove',
    name: 'Chizish',
    unit: 'metr',
    description: 'Zinapoyalarga sirpanishga qarshi (antislip) yo‘llar chizish',
    icon: Icons.line_weight_rounded,
    defaultPrice: 10000,
    defaultProductId: 22,
  ),
];

/// Xizmat narxlarini doimiy saqlash (in-memory + database sync)
class StoneServicesStore {
  static final Map<String, double> _prices = {
    'cut': 25000,
    'cut_meter': 25000,
    'cut_m2': 25000,
    'chamfer': 20000,
    'polish_granite': 30000,
    'polish_ceramics': 20000,
    'groove': 10000,
  };

  static double getPrice(String key) {
    if (key == 'polish') {
      return _prices['polish_granite'] ?? 30000;
    }
    if (key == 'cut') {
      return _prices['cut_m2'] ?? _prices['cut'] ?? 25000;
    }
    return _prices[key] ?? 10000;
  }

  static void setPrice(String key, double price) {
    _prices[key] = price;
    if (key == 'cut_m2') {
      _prices['cut'] = price;
      _prices['cut_meter'] = price;
    }
  }

  static Map<String, double> getAllPrices() => Map.unmodifiable(_prices);

  /// Repozitoriyadan eng so'nggi xizmat narxlarini yuklash
  static Future<void> syncFromRepo(ProductRepository repo) async {
    try {
      final list = await repo.list();
      for (final p in list) {
        final name = p.name.trim().toLowerCase();
        if (p.id == 19 || (name.contains('kesish') && (name.contains('metr') || !name.contains('kvadrat')))) {
          _prices['cut_meter'] = p.price;
          _prices['cut'] = p.price;
        } else if (p.id == 24 || (name.contains('kesish') && (name.contains('kvadrat') || name.contains('m2')))) {
          _prices['cut_m2'] = p.price;
        } else if (p.id == 20 || name.contains('faska')) {
          _prices['chamfer'] = p.price;
        } else if (p.id == 21 || (name.contains('silliq') && name.contains('granit'))) {
          _prices['polish_granite'] = p.price;
        } else if (p.id == 23 || (name.contains('silliq') && name.contains('keramo'))) {
          _prices['polish_ceramics'] = p.price;
        } else if (p.id == 22 || name.contains('chizish')) {
          _prices['groove'] = p.price;
        }
      }
    } catch (_) {}
  }
}

/// Tabiiy tosh va kafel kesish ustaxonasi kalkulyatori
/// Material sarfi, chiqindi (otxod), brutto maydon va zarez (kerf loss) hisobi
class StoneCuttingResult {
  final double itemWidthCm;
  final double itemLengthM;
  final double slabWidthCm;
  final double slabLengthM;
  final double kerfCm;
  final double pricePerM2;

  final int nStrips;
  final int nTotal;
  final int nLines;
  final double netM2;
  final double grossM2;
  final double wasteM2;
  final double totalPrice;
  final bool isValid;
  final String? errorMessage;

  const StoneCuttingResult({
    required this.itemWidthCm,
    required this.itemLengthM,
    required this.slabWidthCm,
    required this.slabLengthM,
    required this.kerfCm,
    required this.pricePerM2,
    required this.nStrips,
    required this.nTotal,
    required this.nLines,
    required this.netM2,
    required this.grossM2,
    required this.wasteM2,
    required this.totalPrice,
    required this.isValid,
    this.errorMessage,
  });

  static StoneCuttingResult calculate({
    required double itemWidthCm,
    required double itemLengthM,
    required double slabWidthCm,
    required double slabLengthM,
    double kerfCm = 0.0,
    double pricePerM2 = 0.0,
  }) {
    if (itemWidthCm <= 0 || itemLengthM <= 0 || slabWidthCm <= 0 || slabLengthM <= 0) {
      return StoneCuttingResult(
        itemWidthCm: itemWidthCm,
        itemLengthM: itemLengthM,
        slabWidthCm: slabWidthCm,
        slabLengthM: slabLengthM,
        kerfCm: kerfCm,
        pricePerM2: pricePerM2,
        nStrips: 0,
        nTotal: 0,
        nLines: 0,
        netM2: 0,
        grossM2: 0,
        wasteM2: 0,
        totalPrice: 0,
        isValid: false,
        errorMessage: 'O‘lchamlar 0 dan katta bo‘lishi kerak',
      );
    }

    final effectiveWidth = itemWidthCm + (kerfCm > 0 ? kerfCm : 0.0);
    final nStrips = (slabWidthCm / effectiveWidth).floor();

    if (nStrips <= 0) {
      return StoneCuttingResult(
        itemWidthCm: itemWidthCm,
        itemLengthM: itemLengthM,
        slabWidthCm: slabWidthCm,
        slabLengthM: slabLengthM,
        kerfCm: kerfCm,
        pricePerM2: pricePerM2,
        nStrips: 0,
        nTotal: 0,
        nLines: 0,
        netM2: double.parse(((itemWidthCm / 100.0) * itemLengthM).toStringAsFixed(3)),
        grossM2: 0,
        wasteM2: 0,
        totalPrice: 0,
        isValid: false,
        errorMessage: 'Plita o‘lchami (${slabWidthCm.toStringAsFixed(1)} sm) kesiladigan kenglik va disk qalinligidan (${effectiveWidth.toStringAsFixed(1)} sm) kichik!',
      );
    }

    final nTotal = (itemLengthM / slabLengthM).ceil();
    final nLines = (nTotal / nStrips).ceil();

    final netM2 = double.parse(((itemWidthCm / 100.0) * itemLengthM).toStringAsFixed(3));
    final grossM2 = double.parse((nLines * (slabWidthCm / 100.0) * slabLengthM).toStringAsFixed(3));
    final rawWaste = grossM2 - netM2;
    final wasteM2 = double.parse((rawWaste > 0 ? rawWaste : 0.0).toStringAsFixed(3));
    final totalPrice = double.parse((grossM2 * pricePerM2).toStringAsFixed(2));

    return StoneCuttingResult(
      itemWidthCm: itemWidthCm,
      itemLengthM: itemLengthM,
      slabWidthCm: slabWidthCm,
      slabLengthM: slabLengthM,
      kerfCm: kerfCm,
      pricePerM2: pricePerM2,
      nStrips: nStrips,
      nTotal: nTotal,
      nLines: nLines,
      netM2: netM2,
      grossM2: grossM2,
      wasteM2: wasteM2,
      totalPrice: totalPrice,
      isValid: true,
    );
  }
}

/// Kassada xizmatlarni tanlash va savatga qo'shish oynasi
class StoneServicesDialog extends StatefulWidget {
  const StoneServicesDialog({super.key, required this.user, this.product});
  final AppUser user;
  final Product? product;

  static Future<void> show(
    BuildContext context, {
    required AppUser user,
    Product? product,
  }) async {
    final msg = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => StoneServicesDialog(user: user, product: product),
    );
    if (msg != null && context.mounted) {
      showMessage(context, msg);
    }
  }

  @override
  State<StoneServicesDialog> createState() => _StoneServicesDialogState();
}

class _StoneServicesDialogState extends State<StoneServicesDialog> {
  int _selectedServiceIdx = 0;

  // Qayta ishlanayotgan tosh yoki kafel mahsuloti
  Product? _selectedProduct;
  List<Product> _availableProducts = [];
  bool _includeStoneInCart = true;

  // Kesish va o'lchamlar uchun controllerlar
  // Bo'yi metr kvadratda (m2) metrda (m), metrda (meter) esa santimetrda (sm) kiritiladi.
  // Eni esa har doim metrda (m) kiritiladi va hisoblanadi.
  // Kesiladigan mahsulot o'lchamlari (Kenglik sm va jami Uzunlik metr)
  final _cutWidthCtrl = TextEditingController(text: '15'); // Kesiladigan kenglik (sm)
  final _cutLengthCtrl = TextEditingController(text: '4.8'); // Kesiladigan jami uzunlik (m)
  final _m2Ctrl = TextEditingController(text: '0.72'); // Metr kvadrat (m²) kiritish joyi
  bool _isSyncingCutDimensions = false;

  final _lengthCtrl = TextEditingController(text: '1.2'); // Bo'yi (m) - boshlang'ich m2 uchun
  final _widthCtrl = TextEditingController(text: '0.6');   // Eni (m)
  final _piecesCtrl = TextEditingController(text: '1');

  // Kesish o'lchov birligi: 'meter' (Metrda) yoki 'm2' (Metr kvadratda)
  String _cutUnit = 'm2';
  final _manualMetersCtrl = TextEditingController(text: '1.0');

  // Silliqlash uchun tosh turi: 'granite' (Granit) yoki 'ceramics' (Keramogranit)
  String _polishStoneType = 'granite';

  // Kesgandan so'ng qo'shimcha ishlov berish (Silliqlash, Faska, Chizish)
  bool _addPolishAfterCut = false;
  bool _addChamferAfterCut = false;
  bool _addGrooveAfterCut = false;

  final _polishMetersCtrl = TextEditingController(text: '1.2');
  final _chamferMetersCtrl = TextEditingController(text: '1.2');
  final _grooveMetersCtrl = TextEditingController(text: '1.2');

  final _noteCtrl = TextEditingController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _recalcFromCutWidth();
    if (widget.product != null) {
      _applyProduct(widget.product!, initial: true);
    }
    _loadPricesAndProducts();
  }

  bool get _isTileOrCeramic => _selectedProduct?.isTileOrCeramic ?? false;

  Future<void> _loadPricesAndProducts() async {
    setState(() => _syncing = true);
    try {
      final repo = context.read<AppRepositories>().products;
      await StoneServicesStore.syncFromRepo(repo);
      final prods = await repo.list();
      if (mounted) {
        // Faqat haqiqiy tosh/kafel mahsulotlarini filtrlaymiz (Akfix, kley, disk va h.k.lar MUTLAQO kiritilmaydi)
        final stones = prods.where((p) => p.isCuttableStone).toList();
        setState(() {
          _availableProducts = stones;
          if (_selectedProduct == null && stones.isNotEmpty) {
            final cart = context.read<CartController>();
            final cartStone = cart.lines
                .where((l) => l.product.isCuttableStone)
                .map((l) => l.product)
                .firstOrNull;
            final preferredStone = cartStone ??
                stones.where((p) => p.isTileOrCeramic && (p.tileLength ?? 0) >= 100).firstOrNull ??
                stones.where((p) => p.isTileOrCeramic).firstOrNull ??
                stones.firstOrNull;
            if (preferredStone != null) {
              _applyProduct(preferredStone, initial: true);
            }
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _syncing = false);
  }

  void _applyProduct(Product p, {bool initial = false}) {
    if (!p.isCuttableStone) return;
    _selectedProduct = p;

    double? len = p.tileLength;
    double? wid = p.tileWidth;

    // Nomidan razmer aniqlashga harakat (masalan: 60x120, 60*60, 30x60)
    if (len == null || wid == null) {
      final match = RegExp(r'(\d+)\s*[*xX×]\s*(\d+)').firstMatch(p.name);
      if (match != null) {
        final v1 = double.tryParse(match.group(1)!);
        final v2 = double.tryParse(match.group(2)!);
        if (v1 != null && v2 != null) {
          if (v1 > v2) {
            len ??= v1;
            wid ??= v2;
          } else {
            len ??= v2;
            wid ??= v1;
          }
        }
      }
    }

    if (len != null && len > 0) {
      final lenM = len / 100.0;
      final lenMStr = lenM % 1 == 0 ? lenM.toInt().toString() : lenM.toString();
      _lengthCtrl.text = lenMStr;
      _polishMetersCtrl.text = lenMStr;
      _chamferMetersCtrl.text = lenMStr;
      _grooveMetersCtrl.text = lenMStr;
    }
    if (wid != null && wid > 0) {
      final widM = wid / 100.0;
      _widthCtrl.text = widM % 1 == 0 ? widM.toInt().toString() : widM.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }

    if (p.isTileOrCeramic) {
      _polishStoneType = 'ceramics';
    } else {
      _polishStoneType = 'granite';
    }

    try {
      final cart = context.read<CartController>();
      final alreadyInCart = cart.lines.any((l) => l.product.id == p.id);
      _includeStoneInCart = !alreadyInCart;
    } catch (_) {
      _includeStoneInCart = true;
    }

    _syncM2FromDimensions();
    _recalcFromCutWidth();

    if (!initial && mounted) {
      setState(() {});
    }
  }

  String _effectiveProductDimText(Product p) {
    if (p.tileLength != null && p.tileWidth != null && p.tileLength! > 0 && p.tileWidth! > 0) {
      final l = p.tileLength! % 1 == 0 ? p.tileLength!.toInt() : p.tileLength!;
      final w = p.tileWidth! % 1 == 0 ? p.tileWidth!.toInt() : p.tileWidth!;
      return '$l × $w sm';
    }
    final match = RegExp(r'(\d+)\s*[*xX×]\s*(\d+)').firstMatch(p.name);
    if (match != null) {
      return '${match.group(1)} × ${match.group(2)} sm';
    }
    return p.unit;
  }

  Future<void> _openProductPicker(BuildContext context) async {
    final prods = _availableProducts.isNotEmpty
        ? _availableProducts
        : (await context.read<AppRepositories>().products.list())
            .where((p) => p.isCuttableStone)
            .toList();
    if (!mounted) return;

    final picked = await showDialog<Product?>(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        products: prods.where((p) => p.isCuttableStone).toList(),
        currentProduct: _selectedProduct,
      ),
    );

    if (mounted) {
      if (picked != null && picked.isCuttableStone) {
        _applyProduct(picked);
      }
    }
  }

  @override
  void dispose() {
    _cutWidthCtrl.dispose();
    _cutLengthCtrl.dispose();
    _m2Ctrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _piecesCtrl.dispose();
    _manualMetersCtrl.dispose();
    _polishMetersCtrl.dispose();
    _chamferMetersCtrl.dispose();
    _grooveMetersCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double _parseVal(TextEditingController ctrl) {
    final v = parseInput(ctrl.text);
    return (v != null && v > 0) ? v : 0.0;
  }

  int _parsePieces() {
    final v = int.tryParse(_piecesCtrl.text.trim());
    return (v != null && v > 0) ? v : 1;
  }

  double get _effectiveLengthCm {
    final raw = _parseVal(_lengthCtrl);
    if (raw <= 0) return 0.0;
    return raw < 20 ? (raw * 100.0) : raw;
  }

  void _syncM2FromCutDimensions() {
    // Korxonadagilar tosh kvadratini o'zlari kiritadi va pul shu kvadratga qarab hisoblanadi.
    // Eni va bo'yi faqat qancha razmer kesish kerakligini ko'rsatish uchun xizmat qiladi.
  }

  void _syncM2FromDimensions() {
    final m2Val = _parseVal(_m2Ctrl);
    if (m2Val <= 0) {
      _m2Ctrl.text = '1.0';
    }
  }

  /// Ustaxona tabiiy tosh va kafel kesish kalkulyatori
  StoneCuttingResult get _currentCuttingCalculation {
    final cutW = _parseVal(_cutWidthCtrl);
    final totalLenM = _parseVal(_cutLengthCtrl);
    final widVal = _parseVal(_widthCtrl);

    final slabLenM = widVal < 20 ? widVal : widVal / 100.0;
    final slabWidCm = _effectiveLengthCm;

    final price = StoneServicesStore.getAllPrices()['cut_m2'] ?? 25000.0;

    return StoneCuttingResult.calculate(
      itemWidthCm: cutW,
      itemLengthM: totalLenM,
      slabWidthCm: slabWidCm,
      slabLengthM: slabLenM,
      kerfCm: 0.0,
      pricePerM2: price,
    );
  }

  /// 1 ta plitadan chiqadigan bo'laklar soni
  double get _stripsCount {
    final calc = _currentCuttingCalculation;
    if (calc.isValid && calc.nStrips > 0) {
      return calc.nStrips.toDouble();
    }
    final hSm = _effectiveLengthCm;
    final cutWSm = _parseVal(_cutWidthCtrl);
    if (hSm <= 0 || cutWSm <= 0) return 0.0;
    final ratio = hSm / cutWSm;
    return (ratio * 10).round() / 10.0;
  }

  /// 1 ta list (plita)dan chiqadigan jami uzunlik (metrda)
  double get _oneSheetMeters {
    final rawW = _parseVal(_widthCtrl);
    if (_stripsCount <= 0 || rawW <= 0) return 0.0;
    final m = _stripsCount * rawW;
    return (m * 100).round() / 100.0;
  }

  /// Jami kesiladigan uzunlik uchun kerak bo'ladigan (sarflanadigan) listlar soni
  double get _neededSheetsCount {
    final calc = _currentCuttingCalculation;
    if (calc.isValid && calc.nLines > 0) {
      return calc.nLines.toDouble();
    }
    final totalLenM = _parseVal(_cutLengthCtrl);
    final oneM = _oneSheetMeters;
    if (totalLenM <= 0 || oneM <= 0) return _parsePieces().toDouble();
    final count = totalLenM / oneM;
    return (count * 10).round() / 10.0;
  }

  String get _neededSheetsDisplay {
    final calc = _currentCuttingCalculation;
    if (calc.isValid && calc.nLines > 0) {
      return '${calc.nLines} ta list';
    }
    final count = _neededSheetsCount;
    if (count <= 0) return '${_parsePieces()} ta list';
    final ceilVal = count.ceil();
    if (count % 1 == 0) {
      return '${count.toInt()} ta list';
    }
    return '$ceilVal ta list (${_formatNumber(count)} ta)';
  }

  String _formatNumber(double val) {
    if (val <= 0) return '0';
    return val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);
  }

  void _recalcFromCutWidth() {}

  void _recalcFromCutLength() {}

  double get _effectiveLengthM {
    final raw = _parseVal(_lengthCtrl);
    // Metr kvadratda bo'yi metrda kiritiladi (masalan: 1.2 m)
    // Agar foydalanuvchi sm kiritib yuborsa (masalan 120):
    return raw >= 20 ? (raw / 100.0) : raw;
  }

  double get _effectiveWidthM {
    final raw = _parseVal(_widthCtrl);
    return raw; // Eni har doim metrda (m) kiritiladi va hisoblanadi
  }

  /// Jami hisoblangan metr yoki miqdor (pul to'g'ridan-to'g'ri shu metr kvadratga qarab hisoblanadi!)
  double get _calculatedTotalMeters {
    final def = kStoneServices[_selectedServiceIdx];

    if (def.key == 'cut') {
      final m2Val = _parseVal(_m2Ctrl);
      return m2Val > 0 ? m2Val : 1.0;
    }

    final m = _parseVal(_manualMetersCtrl);
    return m > 0 ? m : 1.0;
  }

  /// Joriy tanlangan xizmat narxi (so'm / metr yoki m²)
  double get _activeUnitPrice {
    final def = kStoneServices[_selectedServiceIdx];
    if (def.key == 'cut') {
      return StoneServicesStore.getAllPrices()['cut_m2'] ?? 25000;
    }
    if (def.key == 'polish') {
      return _polishStoneType == 'granite'
          ? StoneServicesStore.getPrice('polish_granite')
          : StoneServicesStore.getPrice('polish_ceramics');
    }
    return StoneServicesStore.getPrice(def.key);
  }

  double get _calculatedTotalPrice {
    return _calculatedTotalMeters * _activeUnitPrice;
  }

  /// Qayta ishlanayotgan toshning o'zi uchun talab qilinadigan miqdor
  double get _stoneQtyNeeded {
    if (_selectedProduct == null) return 0.0;
    final pieces = _parsePieces();
    if (_selectedProduct!.unit == 'dona') {
      return pieces.toDouble();
    }
    // Agar m2 bo'lsa: korxona kiritgan tosh kvadrati (m²)
    final m2Val = _parseVal(_m2Ctrl);
    if (m2Val > 0) return m2Val;
    return 1.0;
  }

  /// Qayta ishlanayotgan toshning o'z qiymati
  double get _calculatedStonePrice {
    if (_selectedProduct == null || !_includeStoneInCart) return 0.0;
    return _stoneQtyNeeded * _selectedProduct!.price;
  }

  double get _addPolishMeters {
    final v = parseInput(_polishMetersCtrl.text);
    return (v != null && v > 0) ? v : _effectiveLengthM;
  }

  double get _addChamferMeters {
    final v = parseInput(_chamferMetersCtrl.text);
    return (v != null && v > 0) ? v : _effectiveLengthM;
  }

  double get _addGrooveMeters {
    final v = parseInput(_grooveMetersCtrl.text);
    return (v != null && v > 0) ? v : _effectiveLengthM;
  }

  double get _calculatedAddPolishPrice {
    final def = kStoneServices[_selectedServiceIdx];
    if (def.key != 'cut' || !_addPolishAfterCut) return 0.0;
    final unitPrice = _polishStoneType == 'granite'
        ? StoneServicesStore.getPrice('polish_granite')
        : StoneServicesStore.getPrice('polish_ceramics');
    return _addPolishMeters * unitPrice;
  }

  double get _calculatedAddChamferPrice {
    final def = kStoneServices[_selectedServiceIdx];
    if (def.key != 'cut' || !_addChamferAfterCut) return 0.0;
    return _addChamferMeters * StoneServicesStore.getPrice('chamfer');
  }

  double get _calculatedAddGroovePrice {
    final def = kStoneServices[_selectedServiceIdx];
    if (def.key != 'cut' || !_addGrooveAfterCut) return 0.0;
    return _addGrooveMeters * StoneServicesStore.getPrice('groove');
  }

  double get _allAdditionalServicesPrice {
    return _calculatedAddPolishPrice + _calculatedAddChamferPrice + _calculatedAddGroovePrice;
  }

  /// Umumiy jami to'lov: Tosh qiymati + Asosiy xizmat + Qo'shimcha ishlovlar
  double get _calculatedGrandTotal {
    return _calculatedTotalPrice + _calculatedStonePrice + _allAdditionalServicesPrice;
  }

  void _adjustPieces(int delta) {
    final cur = _parsePieces();
    final next = (cur + delta).clamp(1, 9999);
    _piecesCtrl.text = next.toString();
    _syncM2FromDimensions();
    _recalcFromCutWidth();
    setState(() {});
  }

  void _adjustManualMeters(double delta) {
    final cur = _parseVal(_manualMetersCtrl);
    final next = (cur + delta);
    if (next < 0.1) return;
    _manualMetersCtrl.text = next == next.roundToDouble() ? next.toInt().toString() : next.toStringAsFixed(1);
    setState(() {});
  }

  Future<void> _addToCart() async {
    final def = kStoneServices[_selectedServiceIdx];
    final qty = _calculatedTotalMeters;
    final price = _activeUnitPrice;
    final note = _noteCtrl.text.trim();
    final pieces = _parsePieces();
    final l = _effectiveLengthM;
    final w = _effectiveWidthM;

    final repos = context.read<AppRepositories>();
    final cart = context.read<CartController>();

    int targetProductId = def.defaultProductId;
    String serviceDisplayName = def.name;

    if (def.key == 'cut') {
      targetProductId = 24;
      serviceDisplayName = 'Razmer kesish (Kvadratda)';
    } else if (def.key == 'polish') {
      if (_polishStoneType == 'granite') {
        targetProductId = 21;
        serviceDisplayName = 'Silliqlash (Granit)';
      } else {
        targetProductId = 23;
        serviceDisplayName = 'Silliqlash (Keramogranit)';
      }
    }

    Product? targetProduct;
    try {
      final prods = await repos.products.list();
      targetProduct = prods.where((p) =>
          p.id == targetProductId ||
          p.name.trim().toLowerCase() == serviceDisplayName.toLowerCase()).firstOrNull;
    } catch (_) {}

    targetProduct ??= Product(
      id: targetProductId,
      name: serviceDisplayName,
      category: 'Xizmat',
      unit: def.unit,
      price: price,
      costPrice: 0,
      stock: 999999,
      minStock: 0,
    );

    // O'lcham va spetsifikatsiya matni
    String specText;
    final lenVal = _parseVal(_lengthCtrl);
    final widVal = _parseVal(_widthCtrl);
    final lenStr = '${lenVal % 1 == 0 ? lenVal.toInt() : lenVal} m';
    final widStr = '${widVal % 1 == 0 ? widVal.toInt() : widVal} m';

    if (def.key == 'cut') {
      final cutW = _cutWidthCtrl.text.trim();
      final cutL = _cutLengthCtrl.text.trim();
      final cutSizeStr = (cutW.isNotEmpty && cutL.isNotEmpty)
          ? '$cutW sm × $cutL m razmerda'
          : '';
      specText = '$qty m² tosh kesish${cutSizeStr.isNotEmpty ? ' ($cutSizeStr)' : ''}';
    } else {
      specText = '$qty ${def.unit}';
    }

    // Tosh yoki kafel nomi spetsifikatsiyaga qo'shiladi
    final stonePrefix = _selectedProduct != null
        ? '[${_selectedProduct!.name}] '
        : '';
    specText = '$stonePrefix$specText';

    if (note.isNotEmpty) {
      specText = '$specText — $note';
    }

    final cutWVal = _parseVal(_cutWidthCtrl);
    final cutLVal = _parseVal(_cutLengthCtrl);

    // 1. Toshga ishlov berish xizmatini savatga qo'shamiz
    cart.add(
      targetProduct,
      quantity: qty,
      cutLength: l > 0 ? l : (cutLVal > 0 ? cutLVal : null),
      cutWidth: w > 0 ? w : (cutWVal > 0 ? (cutWVal / 100.0) : null),
      cutPieces: pieces > 0 ? pieces : null,
      cutSpec: specText,
    );

    // Agar narx yangilangan bo'lsa override qo'llaymiz
    if (cart.lines.isNotEmpty) {
      final line = cart.lines.last;
      if (line.product.id == targetProduct.id && line.unitPrice != price) {
        cart.update(line, unitPriceOverride: price);
      }
    }

    // 2. Agar Kesish tanlangan bo'lsa va SILLIQLASH ham belgilangan bo'lsa:
    if (def.key == 'cut' && _addPolishAfterCut) {
      final pMeters = _addPolishMeters;
      final polishName = _polishStoneType == 'granite' ? 'Silliqlash (Granit)' : 'Silliqlash (Keramogranit)';
      final polishPrice = _polishStoneType == 'granite'
          ? StoneServicesStore.getPrice('polish_granite')
          : StoneServicesStore.getPrice('polish_ceramics');
      Product? polishProd;
      try {
        final prods = await repos.products.list();
        polishProd = prods.where((p) => p.name.trim().toLowerCase() == polishName.toLowerCase()).firstOrNull;
      } catch (_) {}
      polishProd ??= Product(
        id: _polishStoneType == 'granite' ? 21 : 23,
        name: polishName,
        category: 'Xizmat',
        unit: 'metr',
        price: polishPrice,
        costPrice: 0,
        stock: 999999,
        minStock: 0,
      );
      cart.add(
        polishProd,
        quantity: pMeters,
        cutLength: l > 0 ? l : null,
        cutWidth: w > 0 ? w : null,
        cutPieces: pieces > 0 ? pieces : null,
        cutSpec: ' metr silliqlash ()',
      );
      if (cart.lines.isNotEmpty) {
        final line = cart.lines.last;
        if (line.product.id == polishProd.id && line.unitPrice != polishPrice) {
          cart.update(line, unitPriceOverride: polishPrice);
        }
      }
    }

    // 3. Agar Kesish tanlangan bo'lsa va FASKA belgilangan bo'lsa:
    if (def.key == 'cut' && _addChamferAfterCut) {
      final cMeters = _addChamferMeters;
      final chamferPrice = StoneServicesStore.getPrice('chamfer');
      Product? chamferProd;
      try {
        final prods = await repos.products.list();
        chamferProd = prods.where((p) => p.name.trim().toLowerCase() == 'faska ochish').firstOrNull;
      } catch (_) {}
      chamferProd ??= Product(
        id: 20,
        name: 'Faska ochish',
        category: 'Xizmat',
        unit: 'metr',
        price: chamferPrice,
        costPrice: 0,
        stock: 999999,
        minStock: 0,
      );
      cart.add(
        chamferProd,
        quantity: cMeters,
        cutLength: l > 0 ? l : null,
        cutWidth: w > 0 ? w : null,
        cutPieces: pieces > 0 ? pieces : null,
        cutSpec: ' metr faska ochish',
      );
      if (cart.lines.isNotEmpty) {
        final line = cart.lines.last;
        if (line.product.id == chamferProd.id && line.unitPrice != chamferPrice) {
          cart.update(line, unitPriceOverride: chamferPrice);
        }
      }
    }

    // 4. Agar Kesish tanlangan bo'lsa va CHIZISH belgilangan bo'lsa:
    if (def.key == 'cut' && _addGrooveAfterCut) {
      final gMeters = _addGrooveMeters;
      final groovePrice = StoneServicesStore.getPrice('groove');
      Product? grooveProd;
      try {
        final prods = await repos.products.list();
        grooveProd = prods.where((p) => p.name.trim().toLowerCase() == 'chizish').firstOrNull;
      } catch (_) {}
      grooveProd ??= Product(
        id: 22,
        name: 'Chizish',
        category: 'Xizmat',
        unit: 'metr',
        price: groovePrice,
        costPrice: 0,
        stock: 999999,
        minStock: 0,
      );
      cart.add(
        grooveProd,
        quantity: gMeters,
        cutLength: l > 0 ? l : null,
        cutWidth: w > 0 ? w : null,
        cutPieces: pieces > 0 ? pieces : null,
        cutSpec: ' metr chizish (sirpanishga qarshi)',
      );
      if (cart.lines.isNotEmpty) {
        final line = cart.lines.last;
        if (line.product.id == grooveProd.id && line.unitPrice != groovePrice) {
          cart.update(line, unitPriceOverride: groovePrice);
        }
      }
    }

    // 5. Agar tosh ombordan yangi qo'shilishi kerak bo'lsa (ombordan chiqim)
    if (_selectedProduct != null && _includeStoneInCart) {
      final sQty = _stoneQtyNeeded;
      if (sQty > 0) {
        cart.add(
          _selectedProduct!,
          quantity: sQty,
          cutLength: l > 0 ? l : null,
          cutWidth: w > 0 ? w : null,
          cutPieces: pieces > 0 ? pieces : null,
          cutSpec: 'Kesishga berildi ($lenStr × $widStr)',
        );
      }
    }

    if (mounted) {
      final stoneMsg = (_selectedProduct != null && _includeStoneInCart)
          ? '${_selectedProduct!.name} va '
          : '';
      Navigator.pop(context, '$stoneMsg$serviceDisplayName ($qty ${def.unit}) savatga qo‘shildi');
    }
  }

  Future<void> _openAdminPriceConfig() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => const ServicesPriceConfigDialog(),
    );
    if (updated == true && mounted) {
      showMessage(context, 'Xizmatlar narxi muvaffaqiyatli saqlandi');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final isAdmin = widget.user.role == Role.admin;
    final curDef = kStoneServices[_selectedServiceIdx];
    final curPrice = _activeUnitPrice;
    final total = _calculatedTotalPrice;

    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 740),
        decoration: BoxDecoration(
          color: context.dialogBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 36,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sarlavha paneli
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.neonLime.withValues(alpha: 0.15)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppColors.neonLime.withValues(alpha: 0.4)
                            : AppColors.border,
                      ),
                    ),
                    child: Icon(
                      Icons.design_services_rounded,
                      color: isDark ? AppColors.neonLime : AppColors.ink,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Xizmatlar (Toshga ishlov berish)',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Eni va bo‘yiga qarab kesish, granit va keramagranit silliqlash',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.mutedColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Xizmatlar narxini sozlash (Admin)',
                      child: OutlinedButton.icon(
                        onPressed: _openAdminPriceConfig,
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: Text(
                          isCompact ? 'Narx' : 'Narxlarni sozlash',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? AppColors.neonLime : AppColors.ink,
                          side: BorderSide(
                            color: isDark ? AppColors.neonLime.withValues(alpha: 0.5) : AppColors.border,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Yopish',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),

            // Xizmatlarni tanlash va parametrlari
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ishlov beriladigan tosh / kafel tanlovi
                    _buildProductSelector(context, isDark),
                    const SizedBox(height: 16),

                    // 4 ta Xizmat tanlash kartalari
                    Text(
                      'Xizmat turini tanlang:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.mutedColor,
                      ),
                    ),
                    const SizedBox(height: 10),

                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 480;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isWide ? 4 : 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: isWide ? 1.15 : 1.4,
                          ),
                          itemCount: kStoneServices.length,
                          itemBuilder: (ctx, i) {
                            final def = kStoneServices[i];
                            final sel = i == _selectedServiceIdx;
                            final price = def.key == 'polish'
                                ? (_polishStoneType == 'granite'
                                    ? StoneServicesStore.getPrice('polish_granite')
                                    : StoneServicesStore.getPrice('polish_ceramics'))
                                : StoneServicesStore.getPrice(def.key);

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedServiceIdx = i;
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? (isDark
                                          ? AppColors.neonLime.withValues(alpha: 0.12)
                                          : const Color(0xFFF0FDF4))
                                      : context.cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: sel
                                        ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                        : context.borderColor,
                                    width: sel ? 1.6 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (def.assetIcon != null)
                                      Image.asset(
                                        def.assetIcon!,
                                        width: 24,
                                        height: 24,
                                        color: sel
                                            ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                            : context.mutedColor,
                                      )
                                    else
                                      Icon(
                                        def.icon,
                                        size: 24,
                                        color: sel
                                            ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                            : context.mutedColor,
                                      ),
                                    const SizedBox(height: 6),
                                    Text(
                                      def.name,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                                        color: sel ? context.inkColor : context.inkColor.withValues(alpha: 0.8),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${money(price)} / ${def.unit}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: sel
                                            ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                            : context.mutedColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // SILLIQLASH TANLANGAN BO'LSA: Granit va Keramogranit tanlovi
                    if (curDef.key == 'polish') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1B2028) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.tune_rounded, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Silliqlash uchun materialni tanlang:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: context.inkColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  avatar: const Icon(Icons.terrain_rounded, size: 18),
                                  label: Text(
                                    'Granit (${money(StoneServicesStore.getPrice('polish_granite'))} / m)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: _polishStoneType == 'granite' ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                  ),
                                  selected: _polishStoneType == 'granite',
                                  selectedColor: isDark ? AppColors.neonLime : AppColors.darkCard,
                                  labelStyle: TextStyle(
                                    color: _polishStoneType == 'granite'
                                        ? (isDark ? AppColors.ink : Colors.white)
                                        : context.inkColor,
                                  ),
                                  onSelected: (_) => setState(() => _polishStoneType = 'granite'),
                                ),
                                ChoiceChip(
                                  avatar: const Icon(Icons.grid_view_rounded, size: 18),
                                  label: Text(
                                    'Keramogranit (${money(StoneServicesStore.getPrice('polish_ceramics'))} / m)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: _polishStoneType == 'ceramics' ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                  ),
                                  selected: _polishStoneType == 'ceramics',
                                  selectedColor: isDark ? AppColors.neonLime : AppColors.darkCard,
                                  labelStyle: TextStyle(
                                    color: _polishStoneType == 'ceramics'
                                        ? (isDark ? AppColors.ink : Colors.white)
                                        : context.inkColor,
                                  ),
                                  onSelected: (_) => setState(() => _polishStoneType = 'ceramics'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // KESISH TANLANGAN BO'LSA: METRDA YOKI METR KVADRATDA
                    if (curDef.key == 'cut') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1B2028) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Birlik tanlovi: Metrda va Metr kvadratda (o'ng tomonga yopishtirilgan)
                            Row(
                              children: [
                                if (curDef.assetIcon != null)
                                  Image.asset(
                                    curDef.assetIcon!,
                                    width: 18,
                                    height: 18,
                                    color: isDark ? AppColors.neonLime : AppColors.ink,
                                  )
                                else
                                  Icon(Icons.straighten_rounded,
                                      size: 18,
                                      color: isDark ? AppColors.neonLime : AppColors.ink),
                                const SizedBox(width: 8),
                                Text(
                                  'Kesish o‘lchovi:',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: context.inkColor,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.neonLime.withValues(alpha: 0.15) : const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDark ? AppColors.neonLime.withValues(alpha: 0.4) : const Color(0xFF16A34A).withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    'm² (Kvadrat metr)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // 1-Qism: Kvadrat metr (m²) kiritish joyi (Pul shu kvadratga qarab hisoblanadi!)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Kvadrat metr (m²):',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: isDark ? AppColors.neonLime : const Color(0xFF047857),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Pul shu kvadratga qarab hisoblanadi',
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: context.mutedColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                TextField(
                                  controller: _m2Ctrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? AppColors.neonLime : const Color(0xFF047857),
                                  ),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF132018) : const Color(0xFFF0FDF4),
                                    isDense: true,
                                    hintText: '1.0',
                                    prefixIcon: const Icon(Icons.square_foot_rounded, size: 22, color: Color(0xFF10B981)),
                                    suffixText: 'm²',
                                    suffixStyle: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? AppColors.neonLime : const Color(0xFF047857),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: Color(0xFF059669), width: 2.0),
                                    ),
                                  ),
                                  onChanged: (_) {
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // 2-Qism: Kesish o'lchami (Eni va bo'yi — qancha razmer kesish kerakligini ko'rsatish uchun)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.content_cut_rounded, size: 15, color: context.mutedColor),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Kesish o‘lchami (Usta uchun razmer ko‘rsatmasi):',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: context.mutedColor,
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
                                      // Kenglik (sm)
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Kenglik (kesiladigan):',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: context.mutedColor,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            TextField(
                                              controller: _cutWidthCtrl,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.inkColor),
                                              decoration: InputDecoration(
                                                filled: true,
                                                fillColor: isDark ? const Color(0xFF181F28) : const Color(0xFFF8FAFC),
                                                isDense: true,
                                                hintText: '15',
                                                suffixText: 'sm',
                                                suffixStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.mutedColor),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderColor)),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderColor)),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5)),
                                              ),
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      // Uzunlik (m)
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Uzunlik (kesiladigan):',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: context.mutedColor,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            TextField(
                                              controller: _cutLengthCtrl,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.inkColor),
                                              decoration: InputDecoration(
                                                filled: true,
                                                fillColor: isDark ? const Color(0xFF181F28) : const Color(0xFFF8FAFC),
                                                isDense: true,
                                                hintText: '4.8',
                                                suffixText: 'm',
                                                suffixStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.mutedColor),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderColor)),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderColor)),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5)),
                                              ),
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // 3-Qism: Aniq hisob-kitob tafsiloti (Kiritilgan Metr Kvadrat, Narxi va Jami summa)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF132018) : const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Hisob maydoni:',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: context.mutedColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_calculatedTotalMeters.toStringAsFixed(2)} m²',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w900,
                                            color: isDark ? AppColors.neonLime : const Color(0xFF047857),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '1 m² narxi:',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: context.mutedColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          money(_activeUnitPrice),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: context.inkColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Jami xizmat puli:',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: context.mutedColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          money(_calculatedTotalPrice),
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildAdditionalServicesSection(context, isDark),
                      const SizedBox(height: 16),
                    ] else ...[
                      // SILLIQLASH, FASKA VA BOSHQA XIZMATLAR: Hajm (metrda) kiritish
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1B2028) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sarlavha (Kesish o‘lchovi kabi qilib)
                            Row(
                              children: [
                                if (curDef.assetIcon != null)
                                  Image.asset(
                                    curDef.assetIcon!,
                                    width: 18,
                                    height: 18,
                                    color: isDark ? AppColors.neonLime : AppColors.ink,
                                  )
                                else
                                  Icon(
                                    Icons.straighten_rounded,
                                    size: 18,
                                    color: isDark ? AppColors.neonLime : AppColors.ink,
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  'Xizmat hajmi:',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: context.inkColor,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF14181F) : const Color(0xFFEFF2F6),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    curDef.unit,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: context.mutedColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Kiritish maydoni va o‘ng tomonida -1 va +1 tugmalari
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Metrda kiritish:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: context.mutedColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: _manualMetersCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.inkColor),
                                        decoration: InputDecoration(
                                          filled: true,
                                          fillColor: context.cardColor,
                                          isDense: true,
                                          hintText: '1.0',
                                          suffixText: curDef.unit,
                                          suffixStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // O‘ng tomonidagi yonida -1 va +1 tugmalari
                                InkWell(
                                  onTap: () => _adjustManualMeters(-1.0),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 41,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: context.cardColor,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: context.borderColor),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.remove_rounded, size: 15, color: context.inkColor),
                                        const SizedBox(width: 2),
                                        Text(
                                          '1 m',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: context.inkColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => _adjustManualMeters(1.0),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 41,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: context.cardColor,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: context.borderColor),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add_rounded, size: 15, color: context.inkColor),
                                        const SizedBox(width: 2),
                                        Text(
                                          '1 m',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: context.inkColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Jonli hisob tafsiloti
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: context.cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calculate_rounded, size: 18, color: isDark ? AppColors.neonLime : AppColors.ink),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final m = _parseVal(_manualMetersCtrl);
                                        final price = _activeUnitPrice;
                                        final total = m * price;
                                        final mStr = m % 1 == 0 ? '${m.toInt()}' : '$m';
                                        return Text(
                                          'Hajmi: $mStr ${curDef.unit} → Jami: ${money(total)}',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: context.inkColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Izoh yoki buyurtma tafsiloti
                    Text(
                      'Izoh yoki buyurtma tafsiloti (ixtiyoriy):',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.mutedColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _noteCtrl,
                      style: TextStyle(fontSize: 13, color: context.inkColor),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: context.cardColor,
                        hintText: 'Masalan: 3-etaj pillapoyaga, Angola toshiga...',
                        hintStyle: TextStyle(fontSize: 13, color: context.mutedColor),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: context.borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: context.borderColor)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // Pastki xulosa va Savatga qo'shish paneli
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedProduct != null && _includeStoneInCart) ...[
                        Text(
                          _allAdditionalServicesPrice > 0
                              ? 'Tosh:  · Kesish:  · Ishlov: '
                              : 'Tosh:  · Xizmat: ',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.mutedColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          money(_calculatedGrandTotal),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ] else ...[
                        Text(
                          _allAdditionalServicesPrice > 0
                              ? 'Kesish:  · Ishlov: '
                              : 'Jami:  metr ·  / ',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.mutedColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          money(_calculatedGrandTotal),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Bekor qilish',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.mutedColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _calculatedTotalMeters > 0 ? _addToCart : null,
                        icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                        label: const Text(
                          'Savatga qo‘shish',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
                          foregroundColor: isDark ? AppColors.ink : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniCutUnitPill({
    required String label,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppColors.neonLime : AppColors.darkCard)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: (isDark ? AppColors.neonLime : AppColors.darkCard).withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 13,
              color: selected
                  ? (isDark ? AppColors.ink : Colors.white)
                  : context.mutedColor,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: selected
                    ? (isDark ? AppColors.ink : Colors.white)
                    : context.mutedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSelector(BuildContext context, bool isDark) {
    final cart = context.watch<CartController>();
    final cartStones = cart.lines
        .where((l) => l.product.isCuttableStone)
        .toList();

    if (_selectedProduct != null) {
      final p = _selectedProduct!;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B2228) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.neonLime.withValues(alpha: 0.35) : AppColors.greenSoft,
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.neonLime.withValues(alpha: 0.15)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? AppColors.neonLime.withValues(alpha: 0.4)
                          : AppColors.border,
                    ),
                  ),
                  child: Icon(
                    Icons.layers_rounded,
                    color: isDark ? AppColors.neonLime : AppColors.ink,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: context.inkColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2B3642) : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.category ?? 'Tosh',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: context.inkColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'O‘lcham: ${_effectiveProductDimText(p)}  •  Narxi: ${money(p.price)} / ${p.unit}  •  Omborda: ${qty(p.stock)} ${p.unit}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.mutedColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openProductPicker(context),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                  label: const Text(
                    'Almashtirish',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Tosh narxini ham savatga qo'shish tanlovi
            InkWell(
              onTap: () => setState(() => _includeStoneInCart = !_includeStoneInCart),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _includeStoneInCart
                      ? (isDark ? AppColors.neonLime.withValues(alpha: 0.12) : const Color(0xFFF0FDF4))
                      : (isDark ? const Color(0xFF222831) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _includeStoneInCart
                        ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                        : context.borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _includeStoneInCart ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: 18,
                      color: _includeStoneInCart
                          ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                          : context.mutedColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Toshning o‘zini ham savatga qo‘shish (ombordan chiqim qilinadi)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.inkColor,
                            ),
                          ),
                          Text(
                            _includeStoneInCart
                                ? 'Tosh miqdori: ${qty(_stoneQtyNeeded)} ${p.unit} · Qiymati: ${money(_calculatedStonePrice)}'
                                : 'Faqat xizmat narxi olinadi (tosh allaqachon savatga kiritilgan)',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Hech qaysi tosh tanlanmagan holat: Faqat ombor toshlari qabul qilinadi
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B20) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.layers_outlined, size: 18, color: context.mutedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ishlov berish uchun tosh / kafelni tanlang:',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.mutedColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF26303A) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Ombordan tanlang',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.neonLime : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Do‘konda begona tosh kesilmaydi, faqat o‘zimizning toshlar kesiladi',
            style: TextStyle(fontSize: 11, color: context.mutedColor),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final cl in cartStones.take(2))
                ActionChip(
                  avatar: const Icon(Icons.shopping_cart_outlined, size: 14),
                  label: Text(
                    cl.product.name,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _applyProduct(cl.product),
                  visualDensity: VisualDensity.compact,
                ),
              FilledButton.tonalIcon(
                onPressed: () => _openProductPicker(context),
                icon: const Icon(Icons.search_rounded, size: 14),
                label: const Text(
                  'Ombordan tosh / kafel tanlash',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalServicesSection(BuildContext context, bool isDark) {
    final polishUnitPrice = _polishStoneType == 'granite'
        ? StoneServicesStore.getPrice('polish_granite')
        : StoneServicesStore.getPrice('polish_ceramics');
    final chamferUnitPrice = StoneServicesStore.getPrice('chamfer');
    final grooveUnitPrice = StoneServicesStore.getPrice('groove');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2028) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (_addPolishAfterCut || _addChamferAfterCut || _addGrooveAfterCut)
              ? (isDark ? AppColors.neonLime.withValues(alpha: 0.35) : AppColors.greenSoft)
              : context.borderColor,
          width: (_addPolishAfterCut || _addChamferAfterCut || _addGrooveAfterCut) ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kesgandan so‘ng qo‘shimcha ishlov berish (ixtiyoriy):',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.inkColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 1. SILLIQLASH QO'SHISH
          _buildExtraServiceItem(
            isDark: isDark,
            title: 'Silliqlash (Jilolash)',
            icon: Icons.auto_awesome_rounded,
            unitPrice: polishUnitPrice,
            enabled: _addPolishAfterCut,
            onToggle: (v) => setState(() => _addPolishAfterCut = v),
            metersCtrl: _polishMetersCtrl,
            onAdjustMeters: (delta) {
              final cur = parseInput(_polishMetersCtrl.text) ?? _effectiveLengthM;
              final next = (cur + delta).clamp(0.1, 999.0);
              _polishMetersCtrl.text = next == next.roundToDouble() ? next.toInt().toString() : next.toStringAsFixed(1);
              setState(() {});
            },
            extraWidget: _addPolishAfterCut
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Text('Turi: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.mutedColor)),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text('Granit', style: TextStyle(fontSize: 11)),
                          selected: _polishStoneType == 'granite',
                          visualDensity: VisualDensity.compact,
                          onSelected: (s) => setState(() => _polishStoneType = 'granite'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Keramogranit', style: TextStyle(fontSize: 11)),
                          selected: _polishStoneType == 'ceramics',
                          visualDensity: VisualDensity.compact,
                          onSelected: (s) => setState(() => _polishStoneType = 'ceramics'),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),

          // 2. FASKA OCHISH QO'SHISH
          _buildExtraServiceItem(
            isDark: isDark,
            title: 'Faska ochish (Qirra berish)',
            icon: Icons.architecture_rounded,
            unitPrice: chamferUnitPrice,
            enabled: _addChamferAfterCut,
            onToggle: (v) => setState(() => _addChamferAfterCut = v),
            metersCtrl: _chamferMetersCtrl,
            onAdjustMeters: (delta) {
              final cur = parseInput(_chamferMetersCtrl.text) ?? _effectiveLengthM;
              final next = (cur + delta).clamp(0.1, 999.0);
              _chamferMetersCtrl.text = next == next.roundToDouble() ? next.toInt().toString() : next.toStringAsFixed(1);
              setState(() {});
            },
          ),
          const SizedBox(height: 8),

          // 3. CHIZISH QO'SHISH
          _buildExtraServiceItem(
            isDark: isDark,
            title: 'Chizish (Sirpanishga qarshi yo‘llar)',
            icon: Icons.line_weight_rounded,
            unitPrice: grooveUnitPrice,
            enabled: _addGrooveAfterCut,
            onToggle: (v) => setState(() => _addGrooveAfterCut = v),
            metersCtrl: _grooveMetersCtrl,
            onAdjustMeters: (delta) {
              final cur = parseInput(_grooveMetersCtrl.text) ?? _effectiveLengthM;
              final next = (cur + delta).clamp(0.1, 999.0);
              _grooveMetersCtrl.text = next == next.roundToDouble() ? next.toInt().toString() : next.toStringAsFixed(1);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExtraServiceItem({
    required bool isDark,
    required String title,
    required IconData icon,
    required double unitPrice,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required TextEditingController metersCtrl,
    required ValueChanged<double> onAdjustMeters,
    Widget? extraWidget,
  }) {
    final m = parseInput(metersCtrl.text) ?? _effectiveLengthM;
    final cost = m * unitPrice;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: enabled
            ? (isDark ? AppColors.neonLime.withValues(alpha: 0.1) : const Color(0xFFF0FDF4))
            : (isDark ? const Color(0xFF161A20) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
              ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
              : context.borderColor,
          width: enabled ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: enabled,
                visualDensity: VisualDensity.compact,
                activeColor: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                checkColor: isDark ? AppColors.ink : Colors.white,
                onChanged: (v) => onToggle(v ?? false),
              ),
              Icon(icon, size: 16, color: enabled ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A)) : context.mutedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.inkColor,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${money(unitPrice)} / metr',
                      style: TextStyle(fontSize: 11, color: context.mutedColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Row(
                children: [
                  Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF222831) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => onAdjustMeters(-0.1),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                          child: Container(
                            width: 28,
                            height: 32,
                            alignment: Alignment.center,
                            child: Icon(Icons.remove_rounded, size: 14, color: context.inkColor),
                          ),
                        ),
                        Container(
                          width: 44,
                          alignment: Alignment.center,
                          child: TextField(
                            controller: metersCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.inkColor),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                              border: InputBorder.none,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        InkWell(
                          onTap: () => onAdjustMeters(0.1),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                          child: Container(
                            width: 28,
                            height: 32,
                            alignment: Alignment.center,
                            child: Icon(Icons.add_rounded, size: 14, color: context.inkColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('metr', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.mutedColor)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF232D38) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      money(cost),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (extraWidget != null) extraWidget,
        ],
      ),
    );
  }
}

/// Admin uchun xizmatlar narxini sozlash va belgilash oynasi
class ServicesPriceConfigDialog extends StatefulWidget {
  const ServicesPriceConfigDialog({super.key});

  @override
  State<ServicesPriceConfigDialog> createState() => _ServicesPriceConfigDialogState();
}

class _ServicesPriceConfigDialogState extends State<ServicesPriceConfigDialog> {
  late final TextEditingController _cutMeterCtrl;
  late final TextEditingController _cutM2Ctrl;
  late final TextEditingController _chamferCtrl;
  late final TextEditingController _polishGraniteCtrl;
  late final TextEditingController _polishCeramicsCtrl;
  late final TextEditingController _grooveCtrl;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cutMeterCtrl = TextEditingController(text: StoneServicesStore.getPrice('cut_meter').round().toString());
    _cutM2Ctrl = TextEditingController(text: (StoneServicesStore.getAllPrices()['cut_m2'] ?? 25000).round().toString());
    _chamferCtrl = TextEditingController(text: StoneServicesStore.getPrice('chamfer').round().toString());
    _polishGraniteCtrl = TextEditingController(text: StoneServicesStore.getPrice('polish_granite').round().toString());
    _polishCeramicsCtrl = TextEditingController(text: StoneServicesStore.getPrice('polish_ceramics').round().toString());
    _grooveCtrl = TextEditingController(text: StoneServicesStore.getPrice('groove').round().toString());
  }

  @override
  void dispose() {
    _cutMeterCtrl.dispose();
    _cutM2Ctrl.dispose();
    _chamferCtrl.dispose();
    _polishGraniteCtrl.dispose();
    _polishCeramicsCtrl.dispose();
    _grooveCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repos = context.read<AppRepositories>();
      final prods = await repos.products.list();

      final cutMeterVal = parseInput(_cutMeterCtrl.text);
      final cutM2Val = parseInput(_cutM2Ctrl.text);
      final chamferVal = parseInput(_chamferCtrl.text);
      final polishGraniteVal = parseInput(_polishGraniteCtrl.text);
      final polishCeramicsVal = parseInput(_polishCeramicsCtrl.text);
      final grooveVal = parseInput(_grooveCtrl.text);

      if (cutMeterVal != null && cutMeterVal >= 0) {
        StoneServicesStore.setPrice('cut_meter', cutMeterVal);
        StoneServicesStore.setPrice('cut', cutMeterVal);
      }
      if (cutM2Val != null && cutM2Val >= 0) StoneServicesStore.setPrice('cut_m2', cutM2Val);
      if (chamferVal != null && chamferVal >= 0) StoneServicesStore.setPrice('chamfer', chamferVal);
      if (polishGraniteVal != null && polishGraniteVal >= 0) StoneServicesStore.setPrice('polish_granite', polishGraniteVal);
      if (polishCeramicsVal != null && polishCeramicsVal >= 0) StoneServicesStore.setPrice('polish_ceramics', polishCeramicsVal);
      if (grooveVal != null && grooveVal >= 0) StoneServicesStore.setPrice('groove', grooveVal);

      // Bazadagi mahsulotlarni yangilash
      for (final p in prods) {
        final name = p.name.trim().toLowerCase();
        double? newPrice;

        if (p.id == 19 || (name.contains('kesish') && !name.contains('kvadrat'))) {
          newPrice = cutMeterVal;
        } else if (p.id == 24 || (name.contains('kesish') && name.contains('kvadrat'))) {
          newPrice = cutM2Val;
        } else if (p.id == 20 || name == 'faska ochish') {
          newPrice = chamferVal;
        } else if (p.id == 21 || (name.contains('silliq') && name.contains('granit'))) {
          newPrice = polishGraniteVal;
        } else if (p.id == 23 || (name.contains('silliq') && name.contains('keramo'))) {
          newPrice = polishCeramicsVal;
        } else if (p.id == 22 || name == 'chizish') {
          newPrice = grooveVal;
        }

        if (newPrice != null && newPrice >= 0 && newPrice != p.price) {
          try {
            await repos.products.update(p.copyWith(price: newPrice));
          } catch (_) {}
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Xatolik: $e';
        });
      }
    }
  }

  void _resetToDefaults() {
    setState(() {
      _cutMeterCtrl.text = '15000';
      _cutM2Ctrl.text = '25000';
      _chamferCtrl.text = '20000';
      _polishGraniteCtrl.text = '30000';
      _polishCeramicsCtrl.text = '20000';
      _grooveCtrl.text = '10000';
    });
  }

  void _adjustPrice(TextEditingController ctrl, int delta) {
    final cur = (int.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) + delta;
    if (cur >= 0) {
      ctrl.text = cur.toString();
      setState(() {});
    }
  }

  Widget _buildGroupHeader({
    required String title,
    required IconData icon,
    required BuildContext context,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: context.mutedColor),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: context.mutedColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 0.8,
              color: context.borderColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard({
    required String title,
    required String subtitle,
    required String unit,
    required IconData icon,
    required Color accentColor,
    required TextEditingController controller,
    required bool isDark,
    required BuildContext context,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF2E3846) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1-qator: Belgisi + Nomi + Birligi
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: context.inkColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF28313E) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            unit,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: context.mutedColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.mutedColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2-qator: Narx boshqaruvi (+5k, [-] input [+], so'm)
          Row(
            children: [
              // Tezkor +5k qo'shish tugmachasi
              InkWell(
                onTap: () => _adjustPrice(controller, 5000),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF14181F) : const Color(0xFFEDF2F7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Text(
                    '+5 000',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: context.inkColor,
                    ),
                  ),
                ),
              ),
              const Spacer(),

              // Stepper konteyneri
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                      onTap: () => _adjustPrice(controller, -1000),
                      child: SizedBox(
                        width: 32,
                        height: 36,
                        child: Icon(Icons.remove, size: 14, color: context.mutedColor),
                      ),
                    ),
                    SizedBox(
                      width: 82,
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: context.inkColor,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                      onTap: () => _adjustPrice(controller, 1000),
                      child: SizedBox(
                        width: 32,
                        height: 36,
                        child: Icon(Icons.add, size: 14, color: context.mutedColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "so'm",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.mutedColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 560,
        decoration: BoxDecoration(
          color: context.dialogBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sarlavha
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [AppColors.neonLime.withValues(alpha: 0.3), AppColors.neonLime.withValues(alpha: 0.1)]
                            : [const Color(0xFF0F172A), const Color(0xFF334155)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: isDark ? AppColors.neonLime : Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Xizmatlar narxini belgilash',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kesish (m²), faska, silliqlash va chizish narxlari',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Yopish',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),

            // Form elementlari (Scrollable)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    color: AppColors.danger, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 1-Guruh: Kesish xizmati
                    _buildGroupHeader(
                      title: 'Kesish xizmati',
                      icon: Icons.content_cut_rounded,
                      context: context,
                    ),
                    _buildServiceCard(
                      title: 'Razmer kesish (m²)',
                      subtitle: 'Tosh yuzasi kvadrat metri bo‘yicha kesish narxi',
                      unit: '1 m²',
                      icon: Icons.crop_square_rounded,
                      accentColor: const Color(0xFF3B82F6),
                      controller: _cutM2Ctrl,
                      isDark: isDark,
                      context: context,
                    ),

                    // 2-Guruh: Ishlov berish & Jilolash
                    const SizedBox(height: 6),
                    _buildGroupHeader(
                      title: 'Ishlov berish & Silliqlash',
                      icon: Icons.auto_awesome_rounded,
                      context: context,
                    ),
                    _buildServiceCard(
                      title: 'Faska ochish',
                      subtitle: 'Plita va zinalar chetiga faska (qirra) berish',
                      unit: '1 metr',
                      icon: Icons.architecture_rounded,
                      accentColor: const Color(0xFF06B6D4),
                      controller: _chamferCtrl,
                      isDark: isDark,
                      context: context,
                    ),
                    _buildServiceCard(
                      title: 'Silliqlash — Granit',
                      subtitle: 'Tabiiy granit toshini jilolash va pardozlash',
                      unit: '1 metr',
                      icon: Icons.terrain_rounded,
                      accentColor: const Color(0xFF10B981),
                      controller: _polishGraniteCtrl,
                      isDark: isDark,
                      context: context,
                    ),
                    _buildServiceCard(
                      title: 'Silliqlash — Keramogranit',
                      subtitle: 'Keramogranit va kafel toshlarini silliqlash',
                      unit: '1 metr',
                      icon: Icons.grid_view_rounded,
                      accentColor: const Color(0xFF6366F1),
                      controller: _polishCeramicsCtrl,
                      isDark: isDark,
                      context: context,
                    ),
                    _buildServiceCard(
                      title: 'Chizish',
                      subtitle: 'Zinapoyalarga sirpanishga qarshi antislip yo‘l chizish',
                      unit: '1 metr',
                      icon: Icons.line_weight_rounded,
                      accentColor: const Color(0xFF8B5CF6),
                      controller: _grooveCtrl,
                      isDark: isDark,
                      context: context,
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // Amallar va pastki boshqaruv paneli
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  // Standart narxlarga qaytarish tugmasi
                  Tooltip(
                    message: 'Standart zavod narxlariga qaytarish',
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _resetToDefaults,
                      icon: const Icon(Icons.restart_alt_rounded, size: 15),
                      label: const Text(
                        'Standart',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.mutedColor,
                        side: BorderSide(color: context.borderColor),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(
                      'Bekor qilish',
                      style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.shrink()
                        : const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark ? AppColors.ink : Colors.white,
                            ),
                          )
                        : const Text(
                            'Saqlash',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
                      foregroundColor: isDark ? AppColors.ink : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bo'yi va Eni birliklarini (m / sm) mustaqil tanlash uchun miniatyura chip
class _UnitChoicePill extends StatelessWidget {
  const _UnitChoicePill({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppColors.neonLime : AppColors.darkCard)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? (isDark ? AppColors.neonLime : AppColors.darkCard)
                : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected
                ? (isDark ? AppColors.ink : Colors.white)
                : context.mutedColor,
          ),
        ),
      ),
    );
  }
}

/// Ombordan tosh yoki kafel tanlash oynasi
class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({
    required this.products,
    this.currentProduct,
  });

  final List<Product> products;
  final Product? currentProduct;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _categoryFilter = 'Barchasi';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final query = _searchCtrl.text.trim().toLowerCase();

    final categories = ['Barchasi', 'Marmar', 'Keramogranit', 'Kafel', 'Travertin'];

    final filtered = widget.products.where((p) {
      if (!p.isCuttableStone) return false;
      if (_categoryFilter != 'Barchasi') {
        final cat = (p.category ?? '').toLowerCase();
        final name = p.name.toLowerCase();
        final filterLow = _categoryFilter.toLowerCase();
        if (_categoryFilter == 'Marmar') {
          if (!cat.contains('marmar') && !name.contains('marmar') && !cat.contains('granit') && !name.contains('granit')) return false;
        } else if (_categoryFilter == 'Keramogranit') {
          if (!cat.contains('keram') && !name.contains('keram')) return false;
        } else if (_categoryFilter == 'Kafel') {
          if (!cat.contains('kafel') && !name.contains('kafel')) return false;
        } else if (_categoryFilter == 'Travertin') {
          if (!cat.contains('travertin') && !name.contains('travertin')) return false;
        } else {
          if (!cat.contains(filterLow) && !name.contains(filterLow)) return false;
        }
      }
      if (query.isNotEmpty) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final catMatch = (p.category ?? '').toLowerCase().contains(query);
        final skuMatch = p.sku.toLowerCase().contains(query);
        final qrMatch = p.qrCode.toLowerCase().contains(query);
        return nameMatch || catMatch || skuMatch || qrMatch;
      }
      return true;
    }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 620),
        decoration: BoxDecoration(
          color: context.dialogBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.layers_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tosh yoki kafel mahsulotini tanlang',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                        Text(
                          'Kesish yoki silliqlash uchun o‘lchamlari avtomatik to‘ldiriladi',
                          style: TextStyle(fontSize: 11.5, color: context.mutedColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Qidirish... (nomi, kodi, razmeri)',
                  hintStyle: TextStyle(fontSize: 13, color: context.mutedColor),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1B2228) : const Color(0xFFF1F5F9),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                ),
              ),
            ),

            // Category filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  for (final cat in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(cat, style: const TextStyle(fontSize: 11.5)),
                        selected: _categoryFilter == cat,
                        onSelected: (sel) {
                          if (sel) setState(() => _categoryFilter = cat);
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Products list
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 36, color: context.mutedColor),
                          const SizedBox(height: 8),
                          Text(
                            'Mahsulot topilmadi',
                            style: TextStyle(fontSize: 13, color: context.mutedColor),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (ctx, idx) {
                        final p = filtered[idx];
                        final isSel = widget.currentProduct?.id == p.id;
                        final dimStr = (p.tileLength != null && p.tileWidth != null && p.tileLength! > 0 && p.tileWidth! > 0)
                            ? '${p.tileLength!.toInt()} × ${p.tileWidth!.toInt()} sm'
                            : '';

                        return InkWell(
                          onTap: () => Navigator.pop(context, p),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? (isDark
                                      ? AppColors.neonLime.withValues(alpha: 0.12)
                                      : const Color(0xFFF0FDF4))
                                  : (isDark ? const Color(0xFF1B2228) : const Color(0xFFFAFAFA)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel
                                    ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                    : context.borderColor,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF26303A) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.layers_rounded,
                                    size: 18,
                                    color: isDark ? AppColors.neonLime : AppColors.ink,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: context.inkColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF2E3842) : const Color(0xFFE2E8F0),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              p.category ?? 'Tosh',
                                              style: TextStyle(fontSize: 10, color: context.inkColor),
                                            ),
                                          ),
                                          if (dimStr.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              '📐 $dimStr',
                                              style: TextStyle(fontSize: 11, color: context.mutedColor, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                          const Spacer(),
                                          Text(
                                            'Qoldiq: ${qty(p.stock)} ${p.unit}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: p.stock > 0
                                                  ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                                  : Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  isSel ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                                  size: 20,
                                  color: isSel
                                      ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                      : context.mutedColor,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const Divider(height: 1, thickness: 1),
            // Bottom bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'Jami: ${filtered.length} ta tosh / kafel',
                    style: TextStyle(fontSize: 12, color: context.mutedColor),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Bekor qilish'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
