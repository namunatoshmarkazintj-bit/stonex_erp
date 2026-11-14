import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/format.dart';
import '../core/qr_svg.dart';
import '../core/theme.dart';
import '../core/units.dart';
import '../data/api_client.dart';
import '../data/local_image_store.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import '../state/cart_controller.dart';
import 'common.dart';
import 'deleted_products_screen.dart';
import 'qr_scanner_screen.dart';
import 'receipt_html_printer.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  late Future<List<Product>> _future;
  String _selectedFilter = 'Barchasi';

  ProductRepository get _repo => context.read<AppRepositories>().products;

  @override
  void initState() {
    super.initState();
    _future = _repo.list();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = _repo.list();
      });
    }
  }

  Future<void> _edit([Product? p]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProductDialog(repo: _repo, product: p),
    );
    if (saved == true && mounted) {
      showMessage(context, p == null ? 'Yangi mahsulot saqlandi' : 'Mahsulot yangilandi');
      _reload();
    }
  }

  Future<void> _showQrLabel(Product p) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ProductQrLabelDialog(
        productName: p.name,
        qrCode: p.qrCode.isNotEmpty ? p.qrCode : (p.sku.isNotEmpty ? p.sku : 'STX-${p.id}'),
        sku: p.sku,
        price: p.price,
        unit: p.unit,
        product: p,
      ),
    );
  }

  Future<void> _delete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Mahsulotni faolsizlantirish', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          '"${p.name}" ro‘yxatdan olib tashlansinmi?\n(Oldingi savdo va ombor tarixi saqlanadi)',
          style: const TextStyle(height: 1.4, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('O‘chirish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deactivate(p.id);
      if (mounted) {
        showMessage(context, '${p.name} ro‘yxatdan olindi');
        _reload();
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  Future<void> _openDeletedProducts() async {
    final anyRestored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const DeletedProductsScreen()),
    );
    if (anyRestored == true && mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.neonLime),
        label: const Text('Mahsulot qo‘shish'),
      ),
      body: FutureBuilder<List<Product>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorView(message: snap.error.toString(), onRetry: _reload);
          }

          var allProducts = (snap.data ?? []).where((p) => !p.isService).toList();
          var displayList = List<Product>.from(allProducts);

          // Dinamik kategoriyalar
          final presentCategories = allProducts
              .map((p) => p.effectiveCategory.trim())
              .where((c) => c.isNotEmpty)
              .toSet();
          final orderedCategories = <String>[];
          for (final cat in standardProductCategories) {
            if (presentCategories.contains(cat)) {
              orderedCategories.add(cat);
            }
          }
          for (final cat in presentCategories) {
            if (!orderedCategories.contains(cat)) {
              orderedCategories.add(cat);
            }
          }

          final filters = [
            'Barchasi',
            ...orderedCategories,
            'Toshlar (m²)',
            'Sortli',
            'Dona',
            'Kam qolgan',
          ];

          // Qidiruv va Filtr qo'llash
          final q = _search.text.trim().toLowerCase();
          if (q.isNotEmpty) {
            displayList = displayList.where((p) {
              return p.name.toLowerCase().contains(q) ||
                  p.sku.toLowerCase().contains(q) ||
                  p.qrCode.toLowerCase().contains(q);
            }).toList();
          }

          if (orderedCategories.contains(_selectedFilter)) {
            displayList = displayList
                .where((p) => p.effectiveCategory.trim().toLowerCase() == _selectedFilter.toLowerCase())
                .toList();
          } else if (_selectedFilter == 'Toshlar (m²)') {
            displayList = displayList.where((p) => p.unit == 'm2').toList();
          } else if (_selectedFilter == 'Sortli') {
            displayList = displayList.where((p) => p.hasSorts || (p.sort != null && p.sort!.isNotEmpty)).toList();
          } else if (_selectedFilter == 'Dona') {
            displayList = displayList.where((p) => p.hasDona || p.unit == 'dona').toList();
          } else if (_selectedFilter == 'Kam qolgan') {
            displayList = displayList.where((p) => p.stock <= p.minStock).toList();
          }

          // Umumiy statistika
          final totalCount = allProducts.length;
          final totalStockValue = allProducts.fold<double>(0, (sum, p) => sum + (p.stock * p.price));
          final lowStockCount = allProducts.where((p) => p.stock <= p.minStock).length;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900;
                final isNarrow = constraints.maxWidth < 720;
                final isExtraSmall = constraints.maxWidth < 420;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(isNarrow ? 14 : 28, 8, isNarrow ? 14 : 28, 80),
                  children: [
                    // Yuqori 3 ta mini-statistika kartasi
                    if (isDesktop)
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniStat(
                              context: context,
                              title: 'Jami Mahsulotlar',
                              value: '$totalCount ta',
                              icon: Icons.inventory_2_outlined,
                              accentColor: AppColors.neonLime,
                              isHeroCard: true,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildMiniStat(
                              context: context,
                              title: 'Ombordagi Tovarlar Qiymati',
                              value: money(totalStockValue),
                              icon: Icons.account_balance_wallet_outlined,
                              accentColor: AppColors.green,
                              isHeroCard: false,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildMiniStat(
                              context: context,
                              title: 'Zaxirasi Kam Qolgan',
                              value: '$lowStockCount ta tovar',
                              icon: Icons.warning_amber_rounded,
                              accentColor: const Color(0xFFEAB308),
                              isHeroCard: false,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildMiniStat(
                        context: context,
                        title: 'Jami Mahsulotlar',
                        value: '$totalCount ta',
                        icon: Icons.inventory_2_outlined,
                        accentColor: AppColors.neonLime,
                        isHeroCard: true,
                        isCompact: isNarrow,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniStat(
                              context: context,
                              title: 'Umumiy Qiymat',
                              value: money(totalStockValue),
                              icon: Icons.account_balance_wallet_outlined,
                              accentColor: AppColors.green,
                              isHeroCard: false,
                              isCompact: isNarrow,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMiniStat(
                              context: context,
                              title: 'Kam Qolgan',
                              value: '$lowStockCount ta',
                              icon: Icons.warning_amber_rounded,
                              accentColor: const Color(0xFFEAB308),
                              isHeroCard: false,
                              isCompact: isNarrow,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Qidiruv va Filtr teglari
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _search,
                              style: TextStyle(fontSize: 13, color: context.inkColor, fontWeight: FontWeight.w500),
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: context.cardColor,
                                isDense: true,
                                hintText: isNarrow ? 'Qidirish...' : 'Qidirish (Nomi, SKU yoki QR kod)...',
                                hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.normal),
                                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                                        onPressed: () {
                                          _search.clear();
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
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'O‘chirilgan mahsulotlar',
                          child: OutlinedButton(
                            onPressed: _openDeletedProducts,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.45)),
                              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                if (!isNarrow) ...[
                                  const SizedBox(width: 6),
                                  const Text('O‘chirilganlar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isExtraSmall)
                          Tooltip(
                            message: 'Mahsulot qo‘shish',
                            child: FilledButton(
                              onPressed: () => _edit(),
                              style: FilledButton.styleFrom(
                                backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                                foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                                padding: const EdgeInsets.all(12),
                                shape: const CircleBorder(),
                                minimumSize: const Size(44, 44),
                              ),
                              child: Icon(Icons.add, size: 20, color: context.isDark ? AppColors.ink : AppColors.neonLime),
                            ),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => _edit(),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                              foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            icon: Icon(Icons.add, size: 18, color: context.isDark ? AppColors.ink : AppColors.neonLime),
                            label: const Text('Qo‘shish', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Filtr chiplari
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in filters) ...[
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

                    // Mahsulotlar ro'yxati (Vault kartalari)
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
                              Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.muted),
                              SizedBox(height: 12),
                              Text('Mahsulotlar topilmadi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              SizedBox(height: 4),
                              Text('Qidiruv mezonlarini o‘zgartiring yoki yangi mahsulot qo‘shing',
                                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
                          final p = displayList[i];
                          final isOutOfStock = p.stock <= 0;
                          final isLowStock = p.stock > 0 && p.stock <= p.minStock;

                          Color stockColor = AppColors.green;
                          String stockLabel = '${qty(p.stock)} ${p.unit}';
                          if (isOutOfStock) {
                            stockColor = AppColors.danger;
                            stockLabel = 'Tugagan (0 ${p.unit})';
                          } else if (isLowStock) {
                            stockColor = const Color(0xFFD97706);
                            stockLabel = 'Kam qolgan (${qty(p.stock)} ${p.unit})';
                          }

                          if (isNarrow) {
                            // Mobil / tor ekranlar uchun 2 qavatli toza moslashuvchan karta
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 1-qator: Logo, Nomi, SKU va Amallar
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                          size: 58,
                                          borderRadius: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5,
                                                color: context.inkColor,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  'SKU: ${p.sku.isNotEmpty ? p.sku : 'Yo‘q'}',
                                                  style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                                                ),
                                                if (p.hasDona && p.donaM2Formatted.isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: context.pillColor,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text('1 dona = ${p.donaM2Formatted}',
                                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                                                  ),
                                                if (p.sortLabel.isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: context.isDark ? const Color(0xFF332512) : const Color(0xFFFEF3C7),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      p.sortLabel,
                                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                                                    ),
                                                  )
                                                else if (p.hasSorts)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: context.isDark ? const Color(0xFF1B2E1D) : const Color(0xFFECFDF5),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text('1 • 1.5 • 2 sort',
                                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.green)),
                                                  ),
                                                if (p.color != null && p.color!.isNotEmpty && p.color != p.sort)
                                                  StoneColorBadge(colorName: p.color!),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.qr_code_2_rounded, size: 19),
                                            tooltip: 'QR Yorliq',
                                            onPressed: () => _showQrLabel(p),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.edit_outlined, size: 18),
                                            tooltip: 'Tahrirlash',
                                            onPressed: () => _edit(p),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                            tooltip: 'O‘chirish',
                                            onPressed: () => _delete(p),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),
                                  Divider(height: 1, color: context.borderColor),
                                  const SizedBox(height: 10),

                                  // 2-qator: Narx va Qoldiq
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '${money(p.price)} / ${p.unit}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13.5,
                                                  color: context.inkColor,
                                                ),
                                              ),
                                            ),
                                            if (p.costPrice > 0)
                                              Text(
                                                'Tannarx: ${money(p.costPrice)}',
                                                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: stockColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          stockLabel,
                                          style: TextStyle(color: stockColor, fontWeight: FontWeight.w700, fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }

                          // Katta ekranlar (Desktop/Planshet) uchun gorizontal to'liq qator
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: context.borderColor),
                            ),
                            child: Row(
                              children: [
                                // Mahsulot logosi
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
                                    size: 58,
                                    borderRadius: 14,
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Nomi va SKU
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              p.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                            ),
                                          ),
                                          if (p.effectiveCategory.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: (context.isDark ? AppColors.neonLime : const Color(0xFF0D9488)).withOpacity(0.14),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                p.effectiveCategory,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: context.isDark ? AppColors.neonLime : const Color(0xFF0F766E),
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (p.hasDona && p.donaM2Formatted.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.pillColor,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text('1 dona = ${p.donaM2Formatted}',
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                                            ),
                                          ],
                                          if (p.sortLabel.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.isDark ? const Color(0xFF332512) : const Color(0xFFFEF3C7),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                p.sortLabel,
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                                              ),
                                            ),
                                          ] else if (p.hasSorts) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.isDark ? const Color(0xFF1B2E1D) : const Color(0xFFECFDF5),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Text('1 • 1.5 • 2 sort',
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.green)),
                                            ),
                                          ],
                                          if (p.thickness != null) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: context.borderColor),
                                              ),
                                              child: Text(
                                                '${p.thickness} sm',
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.subtextColor),
                                              ),
                                            ),
                                          ],
                                          if (p.color != null && p.color!.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            StoneColorBadge(colorName: p.color!),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 8,
                                        children: [
                                          Text(
                                            'SKU: ${p.sku.isNotEmpty ? p.sku : 'Yo‘q'}',
                                            style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                          ),
                                          InkWell(
                                            onTap: () => _showQrLabel(p),
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.isDark ? const Color(0xFF1E2822) : const Color(0xFFE8F5E9),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: (context.isDark ? AppColors.greenBright : AppColors.green).withValues(alpha: 0.3),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.qr_code_rounded, size: 12, color: context.isDark ? AppColors.greenBright : AppColors.green),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    p.qrCode.isNotEmpty ? p.qrCode : 'QR Yorliq',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: context.isDark ? AppColors.greenBright : const Color(0xFF2E7D32),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Narx va Tannarx
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '${money(p.price)} / ${p.unit}',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                        ),
                                      ),
                                      if (p.costPrice > 0)
                                        Text(
                                          'Tannarx: ${money(p.costPrice)}',
                                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),

                                // Qoldiq holati nishoni
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: stockColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    stockLabel,
                                    style: TextStyle(color: stockColor, fontWeight: FontWeight.w700, fontSize: 11),
                                  ),
                                ),

                                const SizedBox(width: 14),

                                // Amallar: QR Yorliq, Tahrirlash va O'chirish
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                                      tooltip: 'QR Yorliq (Chop etish)',
                                      onPressed: () => _showQrLabel(p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 19),
                                      tooltip: 'Tahrirlash',
                                      onPressed: () => _edit(p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AppColors.danger),
                                      tooltip: 'O‘chirish',
                                      onPressed: () => _delete(p),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMiniStat({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required bool isHeroCard,
    bool isCompact = false,
  }) {
    final isDarkTheme = context.isDark;
    final isHero = isHeroCard && !isDarkTheme;

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 18),
      decoration: BoxDecoration(
        color: isHero ? AppColors.darkCard : context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isHero ? AppColors.darkCard : context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 34 : 40,
            height: isCompact ? 34 : 40,
            decoration: BoxDecoration(
              color: isHero ? const Color(0xFF22262B) : accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: isCompact ? 18 : 20),
          ),
          SizedBox(width: isCompact ? 8 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isHero ? const Color(0xFF8E959E) : context.mutedColor,
                    fontSize: isCompact ? 10.5 : 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: isHero ? Colors.white : context.inkColor,
                      fontSize: isCompact ? 15 : 18,
                      fontWeight: FontWeight.w900,
                    ),
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
// Mahsulot qo'shish va tahrirlash dialogi
// ---------------------------------------------------------------------------

class ProductDialog extends StatefulWidget {
  const ProductDialog({super.key, required this.repo, this.product});
  final ProductRepository repo;
  final Product? product;

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  late final _name = TextEditingController(text: widget.product?.name);
  late final _sku = TextEditingController(
    text: widget.product?.sku.isNotEmpty == true
        ? widget.product!.sku
        : (widget.product?.qrCode ?? ''),
  );
  late final _price = TextEditingController(text: widget.product == null ? '' : qty(widget.product!.price));
  late final _cost = TextEditingController(text: widget.product == null ? '' : qty(widget.product!.costPrice));
  late final _thickness = TextEditingController(text: widget.product?.thickness != null ? qty(widget.product!.thickness!) : '');
  late final _tileLength = TextEditingController(text: widget.product?.tileLength != null ? qty(widget.product!.tileLength!) : '');
  late final _tileWidth = TextEditingController(text: widget.product?.tileWidth != null ? qty(widget.product!.tileWidth!) : '');
  late final _boxPieces = TextEditingController(text: widget.product?.boxPieces != null ? widget.product!.boxPieces.toString() : '');
  late final _imageUrl = TextEditingController(text: widget.product?.imageUrl);
  final _stock = TextEditingController();
  final _stockPachka = TextEditingController();
  late final _minStock = TextEditingController(
    text: widget.product?.minStock != null
        ? (widget.product!.minStock == widget.product!.minStock.roundToDouble()
            ? widget.product!.minStock.toInt().toString()
            : widget.product!.minStock.toString())
        : '15',
  );
  final _minStockPachka = TextEditingController();
  late final _sort = TextEditingController(text: widget.product?.sort ?? widget.product?.color ?? "");
  late String? _category = widget.product?.category;
  late String _unit = widget.product?.unit ?? 'm2';
  String? _error;
  bool _busy = false;
  bool _uploadingImage = false;

  static const _units = ['m2', 'dona', 'kg', 'm', 'litr'];

  double? _calcTileDonaM2() {
    final l = parseInput(_tileLength.text);
    final w = parseInput(_tileWidth.text);
    if (l != null && l > 0 && w != null && w > 0) {
      return (l * w) / 10000.0;
    }
    return null;
  }

  double? _calcTileBoxM2() {
    final dona = _calcTileDonaM2();
    final pcs = int.tryParse(_boxPieces.text.trim());
    if (dona != null && pcs != null && pcs > 0) {
      return dona * pcs;
    }
    return null;
  }

  static String _formatNum(double v) {
    if (v == v.roundToDouble()) {
      return v.toInt().toString();
    }
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  @override
  void initState() {
    super.initState();
    final boxM2 = widget.product?.effectiveBoxM2;
    if (boxM2 != null && boxM2 > 0) {
      final minM2 = parseInput(_minStock.text);
      if (minM2 != null) {
        _minStockPachka.text = _formatNum(minM2 / boxM2);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _cost.dispose();
    _thickness.dispose();
    _tileLength.dispose();
    _tileWidth.dispose();
    _boxPieces.dispose();
    _imageUrl.dispose();
    _stock.dispose();
    _stockPachka.dispose();
    _minStock.dispose();
    _minStockPachka.dispose();
    _sort.dispose();
    super.dispose();
  }

  double? _effectiveBoxM2() {
    return _calcTileBoxM2() ?? widget.product?.effectiveBoxM2;
  }

  void _onStockPachkaChanged(String val) {
    final boxM2 = _effectiveBoxM2();
    if (boxM2 == null || boxM2 <= 0) return;
    final p = parseInput(val);
    if (p != null) {
      final m2 = p * boxM2;
      final formatted = _formatNum(m2);
      if (_stock.text != formatted) {
        _stock.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    } else if (val.trim().isEmpty) {
      if (_stock.text.isNotEmpty) {
        _stock.value = const TextEditingValue(text: "");
      }
    }
    setState(() {});
  }

  void _onStockM2Changed(String val) {
    final boxM2 = _effectiveBoxM2();
    if (boxM2 == null || boxM2 <= 0) {
      setState(() {});
      return;
    }
    final m = parseInput(val);
    if (m != null) {
      final p = m / boxM2;
      final formatted = _formatNum(p);
      if (_stockPachka.text != formatted) {
        _stockPachka.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    } else if (val.trim().isEmpty) {
      if (_stockPachka.text.isNotEmpty) {
        _stockPachka.value = const TextEditingValue(text: "");
      }
    }
    setState(() {});
  }

  void _onMinStockPachkaChanged(String val) {
    final boxM2 = _effectiveBoxM2();
    if (boxM2 == null || boxM2 <= 0) return;
    final p = parseInput(val);
    if (p != null) {
      final m2 = p * boxM2;
      final formatted = _formatNum(m2);
      if (_minStock.text != formatted) {
        _minStock.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    } else if (val.trim().isEmpty) {
      if (_minStock.text.isNotEmpty) {
        _minStock.value = const TextEditingValue(text: "");
      }
    }
    setState(() {});
  }

  void _onMinStockM2Changed(String val) {
    final boxM2 = _effectiveBoxM2();
    if (boxM2 == null || boxM2 <= 0) {
      setState(() {});
      return;
    }
    final m = parseInput(val);
    if (m != null) {
      final p = m / boxM2;
      final formatted = _formatNum(p);
      if (_minStockPachka.text != formatted) {
        _minStockPachka.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    } else if (val.trim().isEmpty) {
      if (_minStockPachka.text.isNotEmpty) {
        _minStockPachka.value = const TextEditingValue(text: "");
      }
    }
    setState(() {});
  }

  void _recalculatePachkasWhenDimensionsChange() {
    final boxM2 = _effectiveBoxM2();
    if (boxM2 != null && boxM2 > 0) {
      final sVal = parseInput(_stock.text);
      if (sVal != null) {
        final p = _formatNum(sVal / boxM2);
        if (_stockPachka.text != p) _stockPachka.text = p;
      }
      final mVal = parseInput(_minStock.text);
      if (mVal != null) {
        final p = _formatNum(mVal / boxM2);
        if (_minStockPachka.text != p) _minStockPachka.text = p;
      }
    }
  }

  Widget _buildDualStockCard({
    required String title,
    required String subtitle,
    required TextEditingController m2Controller,
    required TextEditingController pachkaController,
    required ValueChanged<String> onM2Changed,
    required ValueChanged<String> onPachkaChanged,
    required IconData icon,
    required Color iconColor,
  }) {
    final boxM2 = _effectiveBoxM2();
    final hasPachka = boxM2 != null && boxM2 > 0;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF192028) : const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (hasPachka) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Pachkada (dona)",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: pachkaController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: "Masalan: 10",
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                          filled: true,
                          fillColor: context.cardColor,
                        ),
                        onChanged: onPachkaChanged,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: context.isDark ? const Color(0xFF222B36) : const Color(0xFFE2E8F0),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sync_alt_rounded,
                      size: 16,
                      color: AppColors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Kvadratda ($_unit)",
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: m2Controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: "Masalan: 14.4",
                          suffixText: _unit,
                          suffixStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                          filled: true,
                          fillColor: context.cardColor,
                        ),
                        onChanged: onM2Changed,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: context.isDark ? AppColors.neonLime : const Color(0xFF0F766E)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    "1 pachka = ${_formatNum(boxM2)} $_unit  •  Ikkisidan biriga yozsangiz, ikkinchisi avtomatik hisoblanadi",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: context.isDark ? AppColors.neonLime : const Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: m2Controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: "0",
                suffixText: _unit,
                suffixStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: context.cardColor,
              ),
              onChanged: onM2Changed,
            ),
            if (_category != null &&
                (_category!.trim().toLowerCase() == "kafel" ||
                    _category!.trim().toLowerCase() == "kerama granit")) ...[
              const SizedBox(height: 6),
              const Text(
                "💡 Pachka va kvadratni bir vaqtda ko‘rish uchun yuqoridagi o‘lchamlarni kiriting",
                style: TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ],
          ],
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'granit':
        return Icons.terrain_rounded;
      case 'kerama granit':
        return Icons.grid_view_rounded;
      case 'kafel':
        return Icons.dashboard_customize_rounded;
      case 'marmar':
        return Icons.diamond_outlined;
      case 'tayyor mahsulot':
        return Icons.inventory_2_outlined;
      case 'xomashyo':
        return Icons.architecture_rounded;
      case 'qo‘shimcha':
      case 'qoshimcha':
        return Icons.extension_outlined;
      default:
        return Icons.category_rounded;
    }
  }

  Color _getCategoryColor(String cat) {
    switch (cat.toLowerCase()) {
      case 'granit':
        return const Color(0xFFD97706);
      case 'kerama granit':
        return const Color(0xFF059669);
      case 'kafel':
        return const Color(0xFF0D9488);
      case 'marmar':
        return const Color(0xFF8B5CF6);
      case 'tayyor mahsulot':
        return const Color(0xFF2563EB);
      case 'xomashyo':
        return const Color(0xFFEA580C);
      case 'qo‘shimcha':
      case 'qoshimcha':
        return const Color(0xFFE11D48);
      default:
        return AppColors.green;
    }
  }

  Future<void> _pickAndUploadImage() async {
    setState(() {
      _uploadingImage = true;
      _error = null;
    });

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (picked == null) {
        if (mounted) setState(() => _uploadingImage = false);
        return;
      }

      final fileBytes = await picked.readAsBytes();
      if (fileBytes.isEmpty) {
        if (mounted) setState(() => _uploadingImage = false);
        return;
      }

      final pickedFilename = picked.name.isNotEmpty
          ? picked.name
          : 'product_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Rasmni avval ixcham qilib siqish (Base64)
      String finalImageValue;
      try {
        final decoded = img.decodeImage(Uint8List.fromList(fileBytes));
        if (decoded != null) {
          final resized = (decoded.width > 360 || decoded.height > 360)
              ? img.copyResize(
                  decoded,
                  width: decoded.width >= decoded.height ? 360 : null,
                  height: decoded.height > decoded.width ? 360 : null,
                )
              : decoded;
          final jpgBytes = img.encodeJpg(resized, quality: 78);
          finalImageValue = 'data:image/jpeg;base64,${base64Encode(jpgBytes)}';
        } else {
          finalImageValue = 'data:image/jpeg;base64,${base64Encode(fileBytes)}';
        }
      } catch (_) {
        finalImageValue = 'data:image/jpeg;base64,${base64Encode(fileBytes)}';
      }

      // Agar serverda upload yo'li mavjud bo'lsa, yuklashga urinib ko'ramiz
      try {
        final uploadedUrl = await widget.repo.uploadImage(
          fileBytes,
          pickedFilename,
        );
        if (uploadedUrl.isNotEmpty) {
          finalImageValue = uploadedUrl;
        }
      } catch (_) {
        // Serverda upload yo'li bo'lmasa yoki xato bersa, siqilgan Base64 rasm bevosita ishlatiladi
      }

      if (mounted) {
        setState(() {
          _imageUrl.text = finalImageValue;
          _uploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingImage = false;
          _error = 'Rasm tanlashda xatolik: $e';
        });
      }
    }
  }

  void _autoGenerateBarcode() {
    final cleanName = _name.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final suffix = (DateTime.now().millisecondsSinceEpoch % 900) + 100;
    final code = cleanName.isNotEmpty ? 'STX-$cleanName' : 'STX-PROD-$suffix';
    setState(() {
      _sku.text = code;
    });
  }

  Future<void> _scanBarcodeWithCamera() async {
    final scanned = await QrScannerScreen.scanCode(
      context,
      title: 'Shtrix-kodni skanerlash',
    );
    if (scanned != null && scanned.trim().isNotEmpty) {
      setState(() {
        _sku.text = scanned.trim();
      });
      if (mounted) {
        showMessage(context, 'Shtrix-kod kiritildi: ${scanned.trim()}');
      }
    }
  }

  void _autoGenerateQr() => _autoGenerateBarcode();

  void _previewQrLabel(BuildContext context) {
    final qrData = _sku.text.trim();
    if (qrData.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => ProductQrLabelDialog(
        productName: _name.text.trim().isNotEmpty ? _name.text.trim() : 'Nomsiz Mahsulot',
        qrCode: qrData,
        sku: qrData,
        price: parseInput(_price.text) ?? (widget.product?.price ?? 0),
        unit: _unit,
        product: widget.product,
      ),
    );
  }

  Future<void> _save() async {
    final thick = parseInput(_thickness.text);
    final price = parseInput(_price.text);
    final cost = _cost.text.trim().isEmpty ? 0.0 : parseInput(_cost.text);
    final rawStock = _stock.text.trim().isEmpty ? 0.0 : parseInput(_stock.text);
    final rawMinStock = _minStock.text.trim().isEmpty ? 15.0 : parseInput(_minStock.text);

    if (_name.text.trim().isEmpty) {
      setState(() {
        _error = 'Nomini kiriting';
      });
      return;
    }
    if (price == null || price < 0) {
      setState(() {
        _error = 'Sotuv narxini to‘g‘ri kiriting';
      });
      return;
    }
    if (cost == null || cost < 0 || rawStock == null || rawStock < 0 || rawMinStock == null || rawMinStock < 0) {
      setState(() {
        _error = 'Raqamlarni to‘g‘ri kiriting';
      });
      return;
    }

    final barcode = _sku.text.trim();
    final isTile = _category != null &&
        (_category!.trim().toLowerCase() == 'kafel' ||
            _category!.trim().toLowerCase() == 'kerama granit');
    final tLen = isTile ? parseInput(_tileLength.text) : null;
    final tWid = isTile ? parseInput(_tileWidth.text) : null;
    final bPieces = isTile ? int.tryParse(_boxPieces.text.trim()) : null;
    double? calculatedDonaM2;
    double? calculatedBoxM2;
    if (isTile && tLen != null && tLen > 0 && tWid != null && tWid > 0) {
      calculatedDonaM2 = (tLen * tWid) / 10000.0;
      if (bPieces != null && bPieces > 0) {
        calculatedBoxM2 = calculatedDonaM2 * bPieces;
      }
    }

    final boxM2 = calculatedBoxM2 ?? widget.product?.effectiveBoxM2;
    double effectiveStock = rawStock;
    if (effectiveStock == 0 && _stockPachka.text.trim().isNotEmpty && boxM2 != null && boxM2 > 0) {
      effectiveStock = (parseInput(_stockPachka.text) ?? 0.0) * boxM2;
    }

    double effectiveMinStock = rawMinStock;
    if (effectiveMinStock == 0 && _minStockPachka.text.trim().isNotEmpty && boxM2 != null && boxM2 > 0) {
      effectiveMinStock = (parseInput(_minStockPachka.text) ?? 0.0) * boxM2;
    }

    final p = Product(
      id: widget.product?.id ?? 0,
      name: _name.text.trim(),
      category: _category,
      sku: barcode,
      qrCode: barcode,
      unit: _unit,
      donaM2: isTile
          ? calculatedDonaM2
          : (_unit == 'm2' ? (widget.product?.donaM2 ?? Units.stoneDonaM2) : null),
      thickness: ((_category?.trim().toLowerCase() == 'marmar' || _category?.trim().toLowerCase() == 'granit') && thick != null && thick > 0)
          ? thick
          : null,
      tileLength: tLen,
      tileWidth: tWid,
      boxPieces: bPieces,
      boxM2: calculatedBoxM2,
      sort: _sort.text.trim().isNotEmpty ? _sort.text.trim() : null,
      hasSorts: false,
      color: _sort.text.trim().isNotEmpty ? _sort.text.trim() : null,
      price: price,
      costPrice: cost,
      minStock: effectiveMinStock,
      imageUrl: _imageUrl.text.trim().isNotEmpty ? _imageUrl.text.trim() : null,
    );

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (widget.product == null) {
        final created = await widget.repo.create(p, initialStock: effectiveStock);
        LocalImageStore.saveImage(created.id, p.imageUrl, created.name);
      } else {
        LocalImageStore.saveImage(p.id, p.imageUrl, p.name);
        await widget.repo.update(p);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Widget _buildImagePicker(BuildContext context) {
    final currentUrl = _imageUrl.text.trim();
    final hasImage = currentUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF192028) : const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, size: 18, color: context.isDark ? AppColors.neonLime : AppColors.ink),
              const SizedBox(width: 8),
              const Text(
                'Mahsulot rasmi',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const Spacer(),
              if (_uploadingImage)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    height: 120,
                    width: double.infinity,
                    color: context.isDark ? const Color(0xFF10151B) : const Color(0xFFE2E8F0),
                    child: Builder(
                      builder: (_) {
                        try {
                          if (currentUrl.startsWith('data:image/') || currentUrl.contains(';base64,')) {
                            final comma = currentUrl.indexOf(',');
                            final b64 = comma != -1 ? currentUrl.substring(comma + 1).trim() : currentUrl;
                            return Image.memory(
                              Uint8List.fromList(base64Decode(b64)),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_outlined, size: 36, color: AppColors.muted),
                              ),
                            );
                          }
                          if (!currentUrl.startsWith('http') &&
                              !currentUrl.startsWith('/') &&
                              File(currentUrl).existsSync()) {
                            return Image.file(
                              File(currentUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_outlined, size: 36, color: AppColors.muted),
                              ),
                            );
                          }
                          return Image.network(
                            ApiClient.resolveUrl(currentUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_outlined, size: 36, color: AppColors.muted),
                            ),
                          );
                        } catch (_) {
                          return const Center(
                            child: Icon(Icons.broken_image_outlined, size: 36, color: AppColors.muted),
                          );
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        tooltip: 'Rasmni olib tashlash',
                        onPressed: () => setState(() => _imageUrl.clear()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadingImage ? null : _pickAndUploadImage,
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Rasmni almashtirish', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            InkWell(
              onTap: _uploadingImage ? null : _pickAndUploadImage,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (context.isDark ? AppColors.neonLime : AppColors.green).withValues(alpha: 0.35),
                    style: BorderStyle.solid,
                    width: 1.2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: context.isDark ? AppColors.neonLime : AppColors.green,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _uploadingImage ? 'Rasm serverga yuklanmoqda...' : 'Galereyadan rasm yuklash',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: context.isDark ? AppColors.neonLime : AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'JPG, PNG yoki WebP formatida',
                      style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _imageUrl,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              labelText: 'Rasm havolasi (URL yoki yo‘l)',
              hintText: 'https://... yoki galereyadan yuklang',
              prefixIcon: const Icon(Icons.link_rounded, size: 18),
              isDense: true,
              suffixIcon: _imageUrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () => setState(() => _imageUrl.clear()),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveQrPreview(BuildContext context) {
    final qrData = _sku.text.trim();

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF192028) : const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: qrData.isNotEmpty
              ? (context.isDark ? AppColors.neonLime.withValues(alpha: 0.4) : AppColors.green.withValues(alpha: 0.4))
              : context.borderColor,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                size: 18,
                color: context.isDark ? AppColors.neonLime : AppColors.green,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Haqiqiy QR Yorliq',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              if (qrData.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF132D21) : AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Skanerlanadi',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.isDark ? AppColors.greenBright : AppColors.green,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (qrData.isNotEmpty) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(color: Color(0xFF0F9D58), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'NTM ERP',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 120.0,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      qrData,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                    if (_name.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _name.text.trim(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _previewQrLabel(context),
                  icon: const Icon(Icons.print_rounded, size: 15),
                  label: const Text('Chop etish / Ko‘rish', style: TextStyle(fontSize: 11.5)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: 'Kodni nusxalash',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(7),
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: qrData));
                    showMessage(context, 'QR kod nusxalandi: $qrData');
                  },
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 36, color: AppColors.muted),
                  const SizedBox(height: 6),
                  const Text(
                    'QR kod hali kiritilmagan',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _autoGenerateQr,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                    label: const Text('Avtomatik QR yaratish', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;

    return AlertDialog(
      backgroundColor: context.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(isNew ? 'Yangi Mahsulot Qo‘shish' : 'Mahsulotni Tahrirlash',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImagePicker(context),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Mahsulot nomi'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: standardProductCategories.contains(_category) ? _category : null,
                dropdownColor: context.isDark ? const Color(0xFF1E2631) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                elevation: 8,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                style: TextStyle(
                  color: context.inkColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: 'Kategoriya',
                  prefixIcon: const Icon(Icons.category_rounded, size: 18),
                  suffixIcon: _category != null
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          tooltip: 'Tozalash',
                          onPressed: () => setState(() => _category = null),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                hint: const Text('Tanlang', style: TextStyle(fontSize: 12.5)),
                selectedItemBuilder: (BuildContext context) {
                  return standardProductCategories.map<Widget>((String cat) {
                    final color = _getCategoryColor(cat);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(_getCategoryIcon(cat), size: 13, color: color),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            cat,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: context.inkColor,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
                items: [
                  for (final cat in standardProductCategories)
                    DropdownMenuItem(
                      value: cat,
                      child: Builder(
                        builder: (context) {
                          final isSel = _category == cat;
                          final color = _getCategoryColor(cat);
                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(_getCategoryIcon(cat), size: 16, color: color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                    color: isSel
                                        ? (context.isDark ? AppColors.neonLime : color)
                                        : context.inkColor,
                                  ),
                                ),
                              ),
                              if (isSel)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: context.isDark ? AppColors.neonLime : color,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sort,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Turi (Sort, Rang...)',
                  hintText: '1-sort, Qora...',
                  prefixIcon: Icon(Icons.style_outlined, size: 18),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 12),
              TextField(
                controller: _sku,
                decoration: InputDecoration(
                  labelText: 'Shtrix kod (Barcode)',
                  hintText: 'Kamerada skanerlang yoki yozing',
                  prefixIcon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.photo_camera_rounded, size: 20, color: AppColors.green),
                        tooltip: 'Kamera orqali skanerlash',
                        onPressed: _scanBarcodeWithCamera,
                      ),
                      IconButton(
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        tooltip: 'Avto-kod generatsiya qilish',
                        onPressed: _autoGenerateBarcode,
                      ),
                    ],
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _scanBarcodeWithCamera,
                  icon: const Icon(Icons.photo_camera_rounded, size: 16, color: AppColors.green),
                  label: const Text(
                    'Kamerada shtrix kodni o‘qish',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.green),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Bazaviy o‘lchov birligi'),
                items: [for (final u in _units) DropdownMenuItem(value: u, child: Text(u))],
                onChanged: (v) {
                  setState(() {
                    _unit = v ?? _unit;
                  });
                },
              ),


              if (_category != null &&
                  (_category!.trim().toLowerCase() == 'kafel' ||
                      _category!.trim().toLowerCase() == 'kerama granit')) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF1B2028) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (context.isDark ? AppColors.neonLime : const Color(0xFF0D9488)).withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getCategoryIcon(_category!),
                            size: 18,
                            color: _getCategoryColor(_category!),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$_category o‘lchamlari va Pachka hisobi',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.inkColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tileLength,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Bo‘yi (sm)',
                                hintText: '60 yoki 120',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                prefixIcon: Icon(Icons.height_rounded, size: 16),
                                prefixIconConstraints: BoxConstraints(minWidth: 26, minHeight: 26),
                              ),
                              onChanged: (_) {
                                _recalculatePachkasWhenDimensionsChange();
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _tileWidth,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Eni (sm)',
                                hintText: '60',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                prefixIcon: Icon(Icons.straighten_rounded, size: 16),
                                prefixIconConstraints: BoxConstraints(minWidth: 26, minHeight: 26),
                              ),
                              onChanged: (_) {
                                _recalculatePachkasWhenDimensionsChange();
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _boxPieces,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Pachkada',
                                hintText: '4',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                prefixIcon: Icon(Icons.all_inbox_rounded, size: 16),
                                prefixIconConstraints: BoxConstraints(minWidth: 26, minHeight: 26),
                              ),
                              onChanged: (_) {
                                _recalculatePachkasWhenDimensionsChange();
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      Builder(
                        builder: (context) {
                          final donaM2 = _calcTileDonaM2();
                          final boxM2 = _calcTileBoxM2();
                          if (donaM2 == null) return const SizedBox.shrink();
                          final donaFormatted = donaM2.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
                          final boxFormatted = boxM2 != null ? boxM2.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : null;
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: (context.isDark ? AppColors.neonLime : const Color(0xFF0D9488)).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: (context.isDark ? AppColors.neonLime : const Color(0xFF0D9488)).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calculate_rounded,
                                    size: 18,
                                    color: context.isDark ? AppColors.neonLime : const Color(0xFF0F766E),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '1 dona = $donaFormatted m²'
                                      '${boxFormatted != null ? '  •  1 pachka (${_boxPieces.text.trim()} dona) = $boxFormatted m²' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: context.isDark ? AppColors.neonLime : const Color(0xFF0F766E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
              if (_category != null && (_category!.trim().toLowerCase() == 'marmar' || _category!.trim().toLowerCase() == 'granit')) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _thickness,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Marmar qalinligi (sm)',
                    hintText: 'Masalan: 2.0 yoki 1.8',
                    prefixIcon: Icon(Icons.layers_outlined, size: 20),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Sotuv narxi (so‘m / $_unit)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tannarx (so‘m)'),
              ),
              if (isNew) ...[
                const SizedBox(height: 12),
                _buildDualStockCard(
                  title: 'Boshlang‘ich ombor qoldig‘i',
                  subtitle: 'Yangi mahsulot uchun ombordagi dastlabki miqdor',
                  m2Controller: _stock,
                  pachkaController: _stockPachka,
                  onM2Changed: _onStockM2Changed,
                  onPachkaChanged: _onStockPachkaChanged,
                  icon: Icons.inventory_2_outlined,
                  iconColor: context.isDark ? AppColors.neonLime : AppColors.green,
                ),
              ],
              const SizedBox(height: 12),
              _buildDualStockCard(
                title: 'Minimal ombor qoldig‘i',
                subtitle: 'Omborda kamida qancha bo‘lishi kerak (ogohlantirish chegarasi)',
                m2Controller: _minStock,
                pachkaController: _minStockPachka,
                onM2Changed: _onMinStockM2Changed,
                onPachkaChanged: _onMinStockPachkaChanged,
                icon: Icons.warning_amber_rounded,
                iconColor: const Color(0xFFD97706),
              ),

              // Haqiqiy jonli QR-kod stiker ko'rinishi
              _buildLiveQrPreview(context),

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
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Bekor'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
            foregroundColor: context.isDark ? AppColors.ink : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Saqlash'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mahsulot QR Yorlig'i (Chop etish va Katta ko'rish dialogi)
// ---------------------------------------------------------------------------

class ProductQrLabelDialog extends StatefulWidget {
  const ProductQrLabelDialog({
    super.key,
    required this.productName,
    required this.qrCode,
    this.sku = '',
    required this.price,
    this.unit = 'm2',
    this.product,
  });

  final String productName;
  final String qrCode;
  final String sku;
  final double price;
  final String unit;
  final Product? product;

  @override
  State<ProductQrLabelDialog> createState() => _ProductQrLabelDialogState();
}

class _ProductQrLabelDialogState extends State<ProductQrLabelDialog> {
  // 'sticker_58x41' (aniq 58x41mm stiker), 'roll_80mm' (lenta)
  String _selectedFormat = 'sticker_58x41';

  @override
  Widget build(BuildContext context) {
    final cleanCode = widget.qrCode.trim().isNotEmpty ? widget.qrCode.trim() : 'NO-CODE';

    return Dialog(
      backgroundColor: context.dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sarlavha
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.isDark ? const Color(0xFF132D21) : AppColors.greenSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_2_rounded, color: AppColors.green, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mahsulot QR Yorlig‘i',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text('58 x 41 mm etiketka stikeri',
                            style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Format tanlash (SegmentedButton)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Qog‘oz formati:',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 11.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 'sticker_58x41',
                          label: Text('58x41 mm (Stiker)'),
                          icon: Icon(Icons.label_rounded, size: 14),
                        ),
                        ButtonSegment(
                          value: 'roll_80mm',
                          label: Text('80 mm lenta'),
                          icon: Icon(Icons.receipt_long_rounded, size: 14),
                        ),
                      ],
                      selected: {_selectedFormat},
                      onSelectionChanged: (set) => setState(() => _selectedFormat = set.first),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Oq stiker kartasi (Aynan so'ralgan 58x41mm ko'rinishi)
              Center(
                child: Container(
                  width: 250,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD0D7DE), width: 1.2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // QR Kod
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEAECEF), width: 1),
                        ),
                        child: QrImageView(
                          data: cleanCode,
                          version: QrVersions.auto,
                          size: 130,
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.all(2),
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Kodi (masalan: 1209)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD0D7DE), width: 0.8),
                        ),
                        child: Text(
                          cleanCode,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1.0,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Mahsulot nomi
                      Text(
                        widget.productName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Narx va o'lchov birligi
                      Text(
                        '${money(widget.price)} / ${widget.unit}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Harakat tugmalari
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: cleanCode));
                        showMessage(context, 'QR kod nusxalandi: $cleanCode');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Nusxalash', style: TextStyle(fontSize: 12.5)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _printLabel(context),
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: const Text('Chop etish', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                        foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),

              if (widget.product != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      context.read<CartController>().add(widget.product!);
                      showMessage(context, '✅ “${widget.productName}” kassa savatiga qo‘shildi!');
                    },
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                    label: const Text('Kassa savatiga qo‘shish (Sinash)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _cleanAsciiLabel(String input) {
    var s = input
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('`', "'")
        .replaceAll('ʻ', "'")
        .replaceAll('ʼ', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('№', 'No.')
        .replaceAll('²', '2')
        .replaceAll('³', '3')
        .replaceAll('€', 'EUR')
        .replaceAll('£', 'GBP')
        .replaceAll('Ў', "O'")
        .replaceAll('ў', "o'")
        .replaceAll('Ғ', "G'")
        .replaceAll('ғ', "g'")
        .replaceAll('Ш', "Sh")
        .replaceAll('ш', "sh")
        .replaceAll('Ч', "Ch")
        .replaceAll('ch', "ch")
        .replaceAll('Ю', "Yu")
        .replaceAll('ю', "yu")
        .replaceAll('Я', "Ya")
        .replaceAll('я', "ya")
        .replaceAll('Ё', "Yo")
        .replaceAll('ё', "yo")
        .replaceAll('Ц', "Ts")
        .replaceAll('ц', "ts");
    return s.replaceAll(RegExp(r'[^\x20-\x7E\r\n\t]'), ' ');
  }

  String _buildLabelHtml(String cleanCode, String format) {
    final cleanName = _cleanAsciiLabel(widget.productName);
    final cleanPrice = _cleanAsciiLabel(money(widget.price));

    // 80mm kassa chek lentasi
    if (format == 'roll_80mm') {
      final qrSvgTag = generateQrSvg(cleanCode, size: 110);
      return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>QR-$cleanCode</title>
  <style>
    @page { size: 80mm auto; margin: 0; }
    @media print {
      body { width: 72mm; margin: 0 auto; padding: 2mm 0; }
    }
    body {
      font-family: Arial, Helvetica, sans-serif;
      font-size: 13px;
      line-height: 1.32;
      text-align: center;
      color: #000;
      background: #fff;
      width: 72mm;
      margin: 0 auto;
      padding: 6px;
      box-sizing: border-box;
      -webkit-print-color-adjust: exact;
    }
    .bold { font-weight: bold; }
  </style>
</head>
<body>
  $qrSvgTag
  <div style="display: inline-block; margin-top: 4px; padding: 2px 10px; background: #f1f3f5; border: 1px solid #d0d7de; border-radius: 6px; font-family: monospace; font-size: 12px; font-weight: bold;">$cleanCode</div>
  <div class="bold" style="font-size: 14px; margin: 6px 0;">$cleanName</div>
  <div class="bold" style="font-size: 13px; color: #1b5e20;">$cleanPrice / ${widget.unit}</div>
  <div style="height: 18mm;"></div>
</body>
</html>
''';
    }

    // Aynan 58mm eni x 41mm bo'yi stiker (boshqa ortiqcha yozuvlarsiz!)
    final qrSvgTag = generateQrSvg(cleanCode, size: 80);

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>QR-$cleanCode</title>
  <style>
    @page {
      size: 58mm 41mm;
      margin: 0;
    }
    @media print {
      html, body {
        width: 58mm;
        height: 41mm;
        margin: 0;
        padding: 0;
        overflow: hidden;
      }
    }
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      -webkit-print-color-adjust: exact;
    }
    body {
      font-family: Arial, Helvetica, sans-serif;
      width: 58mm;
      height: 41mm;
      background: #fff;
      color: #000;
      padding: 1.5mm 2mm;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      overflow: hidden;
    }
    svg, .qr-svg {
      width: 22mm !important;
      height: 22mm !important;
      margin: 0 auto !important;
      display: block;
    }
    .code-badge {
      display: inline-block;
      margin-top: 1mm;
      padding: 0.6mm 3.5mm;
      background: #f1f3f5;
      border: 0.5px solid #d0d7de;
      border-radius: 2.5mm;
      font-family: monospace;
      font-size: 8.5pt;
      font-weight: 900;
      color: #000;
      line-height: 1;
    }
    .product-name {
      margin-top: 1.2mm;
      font-size: 9pt;
      font-weight: 900;
      color: #000;
      line-height: 1.15;
      max-width: 54mm;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .product-price {
      margin-top: 0.8mm;
      font-size: 9.5pt;
      font-weight: 900;
      color: #1b5e20;
      line-height: 1;
      white-space: nowrap;
    }
  </style>
</head>
<body>
  $qrSvgTag
  <div class="code-badge">$cleanCode</div>
  <div class="product-name">$cleanName</div>
  <div class="product-price">$cleanPrice / ${widget.unit}</div>
</body>
</html>
''';
  }

  Future<void> _printLabel(BuildContext context) async {
    final cleanCode = widget.qrCode.trim().isNotEmpty ? widget.qrCode.trim() : 'NO-CODE';
    final cleanName = _cleanAsciiLabel(widget.productName);
    final cleanPrice = _cleanAsciiLabel(money(widget.price));

    // Web muhitida brauzer HTML orqali chiqarish (aniq 58x41mm stiker o'lchami bilan)
    if (kIsWeb) {
      final ok = await printReceiptViaWebHtml(_buildLabelHtml(cleanCode, _selectedFormat));
      if (ok) {
        if (context.mounted) {
          showMessage(context, '✓ QR Yorliq chop etish oynasi ochildi (58x41 mm)');
        }
        return;
      }
    }

    try {
      final doc = pw.Document();
      final fontBold = pw.Font.courierBold();

      final PdfPageFormat pageFormat;
      if (_selectedFormat == 'roll_80mm') {
        pageFormat = const PdfPageFormat(80.0 * PdfPageFormat.mm, double.infinity, marginAll: 3 * PdfPageFormat.mm);
      } else {
        pageFormat = const PdfPageFormat(58.0 * PdfPageFormat.mm, 41.0 * PdfPageFormat.mm, marginAll: 1.2 * PdfPageFormat.mm);
      }

      if (_selectedFormat == 'roll_80mm') {
        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (pw.Context ctx) {
              return pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.BarcodeWidget(
                      data: cleanCode,
                      barcode: pw.Barcode.qrCode(),
                      width: 60,
                      height: 60,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(cleanCode, style: pw.TextStyle(font: fontBold, fontSize: 11)),
                    pw.SizedBox(height: 4),
                    pw.Text(cleanName, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: fontBold, fontSize: 12)),
                    pw.SizedBox(height: 2),
                    pw.Text('$cleanPrice / ${widget.unit}', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                    pw.SizedBox(height: 18 * PdfPageFormat.mm),
                  ],
                ),
              );
            },
          ),
        );
      } else {
        // 58x41 mm stiker (faqat QR, kodi, nomi va narxi!)
        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (pw.Context ctx) {
              return pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.BarcodeWidget(
                      data: cleanCode,
                      barcode: pw.Barcode.qrCode(),
                      width: 21 * PdfPageFormat.mm,
                      height: 21 * PdfPageFormat.mm,
                    ),
                    pw.SizedBox(height: 1.0 * PdfPageFormat.mm),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey200,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                      ),
                      child: pw.Text(
                        cleanCode,
                        style: pw.TextStyle(font: fontBold, fontSize: 8),
                      ),
                    ),
                    pw.SizedBox(height: 1.0 * PdfPageFormat.mm),
                    pw.Text(
                      cleanName,
                      maxLines: 1,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: fontBold, fontSize: 8.5),
                    ),
                    pw.SizedBox(height: 0.8 * PdfPageFormat.mm),
                    pw.Text(
                      '$cleanPrice / ${widget.unit}',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 8.5,
                        color: PdfColor.fromHex('#1B5E20'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }

      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: 'QR_$cleanCode.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        showMessage(context, 'Chop etishda xatolik: $e', error: true);
      }
    }
  }
}
