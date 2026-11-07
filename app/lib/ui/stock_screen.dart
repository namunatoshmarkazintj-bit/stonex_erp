import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  late Future<List<StockMovementRecord>> _movementsFuture;
  late Future<List<Product>> _productsFuture;
  late Future<List<dynamic>> _combinedFuture;
  String _selectedFilter = 'Barchasi';
  String _selectedProdCategory = 'Barchasi';
  String _activeTab = 'products'; // 'products' (birlamchi) yoki 'movements'
  final _searchCtrl = TextEditingController();

  StockRepository get _stockRepo => context.read<AppRepositories>().stock;
  ProductRepository get _productRepo => context.read<AppRepositories>().products;

  @override
  void initState() {
    super.initState();
    _movementsFuture = _stockRepo.movements().catchError((_) => <StockMovementRecord>[]);
    _productsFuture = _productRepo.list();
    _combinedFuture = Future.wait([_movementsFuture, _productsFuture]);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _movementsFuture = _stockRepo.movements().catchError((_) => <StockMovementRecord>[]);
        _productsFuture = _productRepo.list();
        _combinedFuture = Future.wait([_movementsFuture, _productsFuture]);
      });
    }
  }

  Future<void> _purchaseDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StockPurchaseDialog(
        stockRepo: _stockRepo,
        productRepo: _productRepo,
      ),
    );
    if (ok == true && mounted) {
      showMessage(context, 'Xarid muvaffaqiyatli kirim qilindi');
      _reload();
    }
  }

  Future<void> _adjustDialog([Product? preselected]) async {
    final products = await _productRepo.list();
    if (!mounted) return;
    if (products.isEmpty) {
      return showMessage(context, 'Mahsulotlar yo‘q', error: true);
    }
    Product selected = preselected ?? (products.where((p) => !p.isService).firstOrNull ?? products.first);
    final deltaCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: context.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Qoldiqni Tuzatish (Inventarizatsiya)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<Product>(
                    value: selected,
                    decoration: const InputDecoration(labelText: 'Mahsulot'),
                    items: products.where((p) => !p.isService).map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setS(() {
                          selected = v;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hozirgi hisobdagi qoldiq: ${qty(selected.stock)} ${selected.unit}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deltaCtrl,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: InputDecoration(
                      labelText: 'O‘zgarish miqdori (+ yoki -)',
                      hintText: '+10 yoki -5 (${selected.unit})',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tuzatish sababi (majburiy)',
                      hintText: 'Brak, qayta sanash, yo‘qotish va h.k.',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final d = parseInput(deltaCtrl.text);
                      final note = noteCtrl.text.trim();
                      if (d == null || d == 0) {
                        setS(() {
                          error = 'O‘zgarish miqdorini 0 dan farqli kiriting';
                        });
                        return;
                      }
                      if (note.isEmpty) {
                        setS(() {
                          error = 'Tuzatish sababini kiritish majburiy';
                        });
                        return;
                      }
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await _stockRepo.adjust(productId: selected.id, delta: d, note: note);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setS(() {
                          busy = false;
                          error = e.toString();
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                foregroundColor: context.isDark ? AppColors.ink : Colors.white,
              ),
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Tuzatish'),
            ),
          ],
        ),
      ),
    );

    deltaCtrl.dispose();
    noteCtrl.dispose();

    if (ok == true && mounted) {
      showMessage(context, 'Ombor qoldig‘i muvaffaqiyatli tuzatildi');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ['Barchasi', 'Xaridlar', 'Sotuvlar', 'Ishlab chiqarish', 'Tuzatishlar'];

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      floatingActionButton: Builder(
        builder: (context) {
          final isNarrow = MediaQuery.sizeOf(context).width < 450;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isNarrow)
                FloatingActionButton(
                  heroTag: 'adjust_btn',
                  backgroundColor: context.cardColor,
                  foregroundColor: context.inkColor,
                  tooltip: 'Inventarizatsiya',
                  onPressed: _adjustDialog,
                  child: const Icon(Icons.tune_rounded),
                )
              else
                FloatingActionButton.extended(
                  heroTag: 'adjust_btn',
                  backgroundColor: context.cardColor,
                  foregroundColor: context.inkColor,
                  onPressed: _adjustDialog,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Inventarizatsiya'),
                ),
              const SizedBox(width: 10),
              FloatingActionButton.extended(
                heroTag: 'purchase_btn',
                onPressed: _purchaseDialog,
                icon: const Icon(Icons.add_shopping_cart_rounded, color: AppColors.neonLime),
                label: const Text('Xarid kirimi'),
              ),
            ],
          );
        },
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _combinedFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorView(message: snap.error.toString(), onRetry: _reload);
          }

          final allMovements = snap.data![0] as List<StockMovementRecord>;
          final products = snap.data![1] as List<Product>;
          final productMap = {for (final p in products) p.id: p};

          // Ombordagi real materiallar va toshlar (xizmatlar chiqarib tashlanadi)
          final materialProducts = products.where((p) => !p.isService).toList();

          final q = _searchCtrl.text.trim().toLowerCase();

          // Qoldiqlar statistikasi
          final totalMatCount = materialProducts.length;
          final lowStockCount = materialProducts
              .where((p) => p.stock > 0 && p.stock <= (p.minStock ?? 15))
              .length;
          final outOfStockCount = materialProducts.where((p) => p.stock <= 0).length;
          final inStockCount = materialProducts
              .where((p) => p.stock > (p.minStock ?? 15))
              .length;

          // Mahsulotlarni filtrlash
          var displayProducts = List<Product>.from(materialProducts);
          if (_selectedProdCategory == 'Kam qolganlar') {
            displayProducts = displayProducts
                .where((p) => p.stock > 0 && p.stock <= (p.minStock ?? 15))
                .toList();
          } else if (_selectedProdCategory == 'Tugaganlar') {
            displayProducts = displayProducts.where((p) => p.stock <= 0).toList();
          } else if (_selectedProdCategory != 'Barchasi') {
            displayProducts = displayProducts
                .where((p) =>
                    (p.category ?? '').toLowerCase() ==
                    _selectedProdCategory.toLowerCase())
                .toList();
          }

          if (q.isNotEmpty) {
            displayProducts = displayProducts.where((p) {
              final name = p.name.toLowerCase();
              final cat = (p.category ?? '').toLowerCase();
              final sku = p.sku.toLowerCase();
              return name.contains(q) || cat.contains(q) || sku.contains(q);
            }).toList();
          }

          // Harakatlar ro'yxati
          var displayList = List<StockMovementRecord>.from(allMovements);
          if (_selectedFilter == 'Xaridlar') {
            displayList = displayList.where((m) => m.kind == 'purchase' || m.kind == 'opening').toList();
          } else if (_selectedFilter == 'Sotuvlar') {
            displayList = displayList.where((m) => m.kind == 'sale').toList();
          } else if (_selectedFilter == 'Ishlab chiqarish') {
            displayList = displayList.where((m) => m.kind == 'production').toList();
          } else if (_selectedFilter == 'Tuzatishlar') {
            displayList = displayList.where((m) => m.kind == 'adjustment').toList();
          }

          if (q.isNotEmpty) {
            displayList = displayList.where((m) {
              final pName = (productMap[m.productId]?.name ?? '').toLowerCase();
              final note = (m.note ?? '').toLowerCase();
              return pName.contains(q) || note.contains(q);
            }).toList();
          }

          final purchaseTotal = allMovements.where((m) => m.kind == 'purchase').length;
          final saleTotal = allMovements.where((m) => m.kind == 'sale').length;
          final prodTotal = allMovements.where((m) => m.kind == 'production').length;

          final prodFilters = [
            'Barchasi',
            'Marmar',
            'Keramogranit',
            'Qo‘shimcha',
            'Kam qolganlar',
            'Tugaganlar',
          ];
          final movementFilters = [
            'Barchasi',
            'Xaridlar',
            'Sotuvlar',
            'Ishlab chiqarish',
            'Tuzatishlar',
          ];

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900;

                return ListView(
                  padding: EdgeInsets.fromLTRB(isDesktop ? 28.0 : 12.0, 12, isDesktop ? 28.0 : 12.0, 80),
                  children: [
                    // Asosiy ko'rinish tanlagichi (Ombor qoldiqlari vs Harakatlar tarixi)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTabPill(
                              label: 'Ombor qoldiqlari ($totalMatCount)',
                              icon: Icons.inventory_2_rounded,
                              active: _activeTab == 'products',
                              onTap: () => setState(() => _activeTab = 'products'),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _buildTabPill(
                              label: 'Harakatlar tarixi (${allMovements.length})',
                              icon: Icons.swap_horiz_rounded,
                              active: _activeTab == 'movements',
                              onTap: () => setState(() => _activeTab = 'movements'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_activeTab == 'products') ...[
                      // Yuqori statistika paneli (Mahsulotlar qoldiqlari)
                      if (isDesktop)
                        Row(
                          children: [
                            Expanded(child: _buildStat(context, 'Jami tovarlar', '$totalMatCount ta', Icons.layers_rounded, AppColors.neonLime, true)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Yetarli zaxira', '$inStockCount ta', Icons.check_circle_rounded, AppColors.green, false)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Kam qolgan', '$lowStockCount ta', Icons.warning_amber_rounded, const Color(0xFFC77700), false)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Tugagan', '$outOfStockCount ta', Icons.cancel_rounded, AppColors.danger, false)),
                          ],
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(child: _buildStat(context, 'Jami tovarlar', '$totalMatCount ta', Icons.layers_rounded, AppColors.neonLime, true)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildStat(context, 'Yetarli', '$inStockCount ta', Icons.check_circle_rounded, AppColors.green, false)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildStat(context, 'Kam qolgan', '$lowStockCount ta', Icons.warning_amber_rounded, const Color(0xFFC77700), false)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildStat(context, 'Tugagan', '$outOfStockCount ta', Icons.cancel_rounded, AppColors.danger, false)),
                          ],
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Qidiruv va Xarid kirimi tugmasi
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: TextField(
                                controller: _searchCtrl,
                                style: TextStyle(fontSize: 13, color: context.inkColor, fontWeight: FontWeight.w500),
                                textAlignVertical: TextAlignVertical.center,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: context.cardColor,
                                  isDense: true,
                                  hintText: 'Tosh yoki mahsulot nomi bo‘yicha qidirish...',
                                  hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.normal),
                                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                                  suffixIcon: _searchCtrl.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() {});
                                          },
                                          splashRadius: 18,
                                          padding: EdgeInsets.zero,
                                        ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide(color: context.borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide(color: context.borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide(color: context.isDark ? AppColors.neonLime : AppColors.ink, width: 1.5),
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _purchaseDialog,
                            style: FilledButton.styleFrom(
                              backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                              foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                            icon: Icon(Icons.add, size: 18, color: context.isDark ? AppColors.ink : AppColors.neonLime),
                            label: const Text('Xarid kirimi', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Toifa filtrlari
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in prodFilters) ...[
                              GestureDetector(
                                onTap: () => setState(() => _selectedProdCategory = f),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _selectedProdCategory == f
                                        ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                                        : context.cardColor,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _selectedProdCategory == f
                                          ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                                          : context.borderColor,
                                    ),
                                  ),
                                  child: Text(
                                    f,
                                    style: TextStyle(
                                      color: _selectedProdCategory == f
                                          ? (context.isDark ? AppColors.ink : Colors.white)
                                          : context.inkColor,
                                      fontSize: 12,
                                      fontWeight: _selectedProdCategory == f ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Mahsulotlar ro'yxati
                      if (displayProducts.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(48),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.muted),
                                SizedBox(height: 12),
                                Text('Omborda mahsulotlar topilmadi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayProducts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _buildProductStockCard(context, displayProducts[i]),
                        ),
                    ] else ...[
                      // Harakatlar tarixi ko'rinishi
                      if (isDesktop)
                        Row(
                          children: [
                            Expanded(child: _buildStat(context, 'Jami Harakatlar', '${allMovements.length} ta', Icons.history_rounded, AppColors.neonLime, true)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Xarid Kirimlari', '$purchaseTotal ta', Icons.input_rounded, AppColors.green, false)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Sotuv Chiqimlari', '$saleTotal ta', Icons.output_rounded, const Color(0xFFC77700), false)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Ishlab Chiqarish', '$prodTotal ta', Icons.precision_manufacturing_rounded, const Color(0xFF245580), false)),
                          ],
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(child: _buildStat(context, 'Harakatlar', '${allMovements.length} ta', Icons.history_rounded, AppColors.neonLime, true)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildStat(context, 'Kirimlar', '$purchaseTotal ta', Icons.input_rounded, AppColors.green, false)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildStat(context, 'Chiqimlar', '$saleTotal ta', Icons.output_rounded, const Color(0xFFC77700), false)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildStat(context, 'Sex qabuli', '$prodTotal ta', Icons.precision_manufacturing_rounded, const Color(0xFF245580), false)),
                          ],
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Harakatlar qidiruvi
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: TextField(
                                controller: _searchCtrl,
                                style: TextStyle(fontSize: 13, color: context.inkColor, fontWeight: FontWeight.w500),
                                textAlignVertical: TextAlignVertical.center,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: context.cardColor,
                                  isDense: true,
                                  hintText: 'Harakat bo‘yicha qidirish...',
                                  hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.normal),
                                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide(color: context.borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide(color: context.borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    borderSide: BorderSide(color: context.isDark ? AppColors.neonLime : AppColors.ink, width: 1.5),
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _purchaseDialog,
                            style: FilledButton.styleFrom(
                              backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                              foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                            icon: Icon(Icons.add, size: 18, color: context.isDark ? AppColors.ink : AppColors.neonLime),
                            label: const Text('Xarid kirimi', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Harakatlar filtrlari
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in movementFilters) ...[
                              GestureDetector(
                                onTap: () => setState(() => _selectedFilter = f),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _selectedFilter == f
                                        ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                                        : context.cardColor,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _selectedFilter == f
                                          ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                                          : context.borderColor,
                                    ),
                                  ),
                                  child: Text(
                                    f,
                                    style: TextStyle(
                                      color: _selectedFilter == f
                                          ? (context.isDark ? AppColors.ink : Colors.white)
                                          : context.inkColor,
                                      fontSize: 12,
                                      fontWeight: _selectedFilter == f ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      if (displayList.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(48),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warehouse_outlined, size: 48, color: AppColors.muted),
                                SizedBox(height: 12),
                                Text('Ombor harakatlari topilmadi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayList.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final m = displayList[i];
                            final p = productMap[m.productId];
                            final isPositive = m.qtyDelta > 0;
                            final unit = p?.unit ?? '';

                            String kindLabel;
                            Color kindColor;
                            IconData kindIcon;

                            switch (m.kind) {
                              case 'purchase':
                                kindLabel = 'Xarid kirimi';
                                kindColor = AppColors.green;
                                kindIcon = Icons.input_rounded;
                                break;
                              case 'sale':
                                kindLabel = 'Sotuv chiqimi';
                                kindColor = const Color(0xFFC77700);
                                kindIcon = Icons.output_rounded;
                                break;
                              case 'production':
                                kindLabel = 'Ishlab chiqarish';
                                kindColor = const Color(0xFF245580);
                                kindIcon = Icons.precision_manufacturing_rounded;
                                break;
                              case 'adjustment':
                                kindLabel = 'Inventarizatsiya';
                                kindColor = const Color(0xFF6B48A8);
                                kindIcon = Icons.tune_rounded;
                                break;
                              default:
                                kindLabel = 'Boshlang‘ich qoldiq';
                                kindColor = AppColors.muted;
                                kindIcon = Icons.flag_rounded;
                            }

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: kindColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(kindIcon, color: kindColor, size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                p?.name ?? 'Mahsulot #${m.productId}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: kindColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                kindLabel,
                                                style: TextStyle(color: kindColor, fontWeight: FontWeight.w700, fontSize: 10),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${m.note ?? 'Izohsiz'}  ·  ${m.createdAt.day.toString().padLeft(2, '0')}.${m.createdAt.month.toString().padLeft(2, '0')}.${m.createdAt.year} ${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${isPositive ? '+' : ''}${qty(m.qtyDelta)} $unit',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: isPositive ? AppColors.green : AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabPill({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: active
              ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: active
                  ? (context.isDark ? AppColors.ink : Colors.white)
                  : context.mutedColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active
                      ? (context.isDark ? AppColors.ink : Colors.white)
                      : context.mutedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductStockCard(BuildContext context, Product p) {
    final minStock = p.minStock ?? 15;
    final isOut = p.stock <= 0;
    final isLow = p.stock > 0 && p.stock <= minStock;

    final Color statusColor = isOut
        ? AppColors.danger
        : (isLow ? const Color(0xFFC77700) : AppColors.green);

    final String statusLabel = isOut
        ? 'Tugagan'
        : (isLow ? 'Kam qolgan (Min: ${qty(minStock)})' : 'Yetarli zaxira');

    final sizeStr = (p.tileLength != null && p.tileWidth != null)
        ? '${qty(p.tileLength!)} × ${qty(p.tileWidth!)} sm'
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOut
              ? AppColors.danger.withValues(alpha: 0.3)
              : (isLow ? const Color(0xFFC77700).withValues(alpha: 0.3) : context.borderColor),
          width: isOut || isLow ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.layers_rounded, color: statusColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.isDark ? const Color(0xFF22262B) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        p.category ?? 'Material',
                        style: TextStyle(color: context.mutedColor, fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (sizeStr != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        sizeStr,
                        style: TextStyle(color: context.mutedColor, fontSize: 11),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      'Sotuv: ${money(p.price)} / ${p.unit}',
                      style: TextStyle(color: context.mutedColor, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${qty(p.stock)} ${p.unit}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => _adjustDialog(p),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: context.borderColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.tune_rounded, size: 14),
                label: const Text('Tuzatish', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(BuildContext context, String title, String value, IconData icon, Color color, bool isHeroCard) {
    final isDarkTheme = context.isDark;
    final isHero = isHeroCard && !isDarkTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHero ? AppColors.darkCard : context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isHero ? AppColors.darkCard : context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isHero ? const Color(0xFF22262B) : color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(color: isHero ? const Color(0xFF8E959E) : context.mutedColor, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: isHero ? Colors.white : context.inkColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Xarid kirimi dialogi (Vault uslubida)
// ---------------------------------------------------------------------------

class StockPurchaseDialog extends StatefulWidget {
  const StockPurchaseDialog({super.key, required this.stockRepo, required this.productRepo});
  final StockRepository stockRepo;
  final ProductRepository productRepo;

  @override
  State<StockPurchaseDialog> createState() => _StockPurchaseDialogState();
}

class _StockPurchaseDialogState extends State<StockPurchaseDialog> {
  late Future<List<Product>> _productsFuture;
  Product? _selected;
  final _qtyCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = widget.productRepo.list().then((products) {
      if (products.isNotEmpty) {
        _selected = products.first;
        if (_selected!.costPrice > 0) {
          _costCtrl.text = _selected!.costPrice.round().toString();
        }
      }
      return products;
    });
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    final q = parseInput(_qtyCtrl.text);
    final c = parseInput(_costCtrl.text);
    if (q == null || q <= 0 || c == null || c < 0) {
      setState(() {
        _error = 'Miqdor va narxni to‘g‘ri kiriting';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.stockRepo.purchase(
        productId: _selected!.id,
        quantity: q,
        unitCost: c,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _productsFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const AlertDialog(
            content: SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final products = snap.data!;
        if (products.isEmpty) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Mahsulotlar mavjud emas'),
            content: const Text('Xarid kirimi qilishdan oldin mahsulot yarating.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
            ],
          );
        }

        _selected ??= products.first;

        return AlertDialog(
          backgroundColor: context.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Yangi Xarid Kirimi (Partiya)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<Product>(
                    value: _selected,
                    decoration: const InputDecoration(labelText: 'Mahsulot'),
                    items: products.where((p) => !p.isService).map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selected = v;
                          if (_selected!.costPrice > 0) {
                            _costCtrl.text = _selected!.costPrice.round().toString();
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Kirim miqdori (${_selected!.unit})'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _costCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Xarid narxi (so‘m / ${_selected!.unit})'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(labelText: 'Izoh / Yetkazib beruvchi (ixtiyoriy)'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Kirim qilish', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }
}

