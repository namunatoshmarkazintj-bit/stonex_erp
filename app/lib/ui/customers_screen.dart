import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/local_image_store.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'camera_capture_dialog.dart';
import 'common.dart';
import 'receipt_dialog.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchCtrl = TextEditingController();
  late Future<List<Customer>> _future;
  String _selectedFilter =
      'Barchasi'; // 'Barchasi', 'Qarzdorlar', 'Faol xaridorlar'

  CustomerRepository get _repo => context.read<AppRepositories>().customers;

  @override
  void initState() {
    super.initState();
    _future = _repo.listCustomers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _repo.listCustomers();
    });
  }

  Future<void> _openCustomerDialog([Customer? customer]) async {
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerDialog(customer: customer),
    );
    if (updated == true) {
      _reload();
    }
  }

  Future<void> _openCustomerDetails(Customer customer) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CustomerDetailsDialog(
        customer: customer,
        onEdit: () {
          Navigator.pop(context);
          _openCustomerDialog(customer);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 14, 4, wide ? 28 : 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Yuqori qidiruv va yangi mijoz qo'shish paneli
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(
                        fontSize: 13,
                        color: context.inkColor,
                        fontWeight: FontWeight.w500),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: context.cardColor,
                      isDense: true,
                      hintText:
                          'Mijoz ismi, telefoni yoki pasporti bo‘yicha qidirish...',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: AppColors.muted),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 20, color: AppColors.muted),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: context.borderColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: context.borderColor)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                              color: context.isDark
                                  ? AppColors.neonLime
                                  : AppColors.ink,
                              width: 1.5)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: () => _openCustomerDialog(),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(wide ? 'Yangi Mijoz' : '+',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.isDark
                        ? AppColors.neonLime
                        : AppColors.darkCard,
                    foregroundColor:
                        context.isDark ? AppColors.ink : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Filter chiplari
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  ['Barchasi', 'Qarzdorlar', 'Faol xaridorlar'].map((cat) {
                final sel = _selectedFilter == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? Colors.white : AppColors.ink,
                      ),
                    ),
                    selected: sel,
                    selectedColor: AppColors.darkCard,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                          color: sel ? AppColors.darkCard : AppColors.border),
                    ),
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _selectedFilter = cat),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Asosiy ro'yxat
          Expanded(
            child: FutureBuilder<List<Customer>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorView(
                      message: snap.error.toString(), onRetry: _reload);
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var list = snap.data!;

                // Qidiruv filtri
                final q = _searchCtrl.text.trim().toLowerCase();
                if (q.isNotEmpty) {
                  list = list.where((c) {
                    final n = c.name.toLowerCase();
                    final p = (c.phone ?? '').toLowerCase();
                    final pass = (c.passport ?? '').toLowerCase();
                    return n.contains(q) || p.contains(q) || pass.contains(q);
                  }).toList();
                }

                // Kategoriya filtri
                if (_selectedFilter == 'Qarzdorlar') {
                  list = list.where((c) => c.totalDebt > 0.5).toList();
                } else if (_selectedFilter == 'Faol xaridorlar') {
                  list = list.where((c) => c.salesCount > 0).toList();
                }

                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline_rounded,
                              size: 54, color: context.mutedColor),
                          const SizedBox(height: 12),
                          Text(
                            q.isNotEmpty
                                ? 'Mijoz topilmadi'
                                : 'Hozircha mijozlar ro‘yxati bo‘sh',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: context.inkColor),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            q.isNotEmpty
                                ? 'Boshqa ism, telefon yoki pasport bilan qidiring'
                                : 'Yangi savdo paytida yoki "+ Yangi Mijoz" tugmasi orqali qo‘shing',
                            style: TextStyle(
                                color: context.mutedColor, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Statistika hisoblash
                final totalDebtSum =
                    list.fold<double>(0, (sum, c) => sum + c.totalDebt);
                final totalSpentSum =
                    list.fold<double>(0, (sum, c) => sum + c.totalSpent);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Statistika paneli
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatMini(
                              label: 'Jami mijozlar',
                              value: '${list.length} nafar',
                              color: context.inkColor,
                            ),
                          ),
                          Container(
                              width: 1, height: 28, color: context.borderColor),
                          Expanded(
                            child: _StatMini(
                              label: 'Umumiy xarid',
                              value: money(totalSpentSum),
                              color: AppColors.green,
                            ),
                          ),
                          Container(
                              width: 1, height: 28, color: context.borderColor),
                          Expanded(
                            child: _StatMini(
                              label: 'Umumiy nasiya',
                              value: money(totalDebtSum),
                              color: totalDebtSum > 0
                                  ? AppColors.danger
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Mijozlar kartalari
                    Expanded(
                      child: ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final c = list[i];
                          final hasDebt = c.totalDebt > 0.5;

                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _openCustomerDetails(c),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: hasDebt
                                        ? AppColors.danger
                                            .withValues(alpha: 0.3)
                                        : context.borderColor),
                              ),
                              child: Row(
                                children: [
                                  // Mijoz / Pasport rasmi
                                  GestureDetector(
                                    onTap: (c.photoUrl != null &&
                                            c.photoUrl!.isNotEmpty)
                                        ? () => showProductImagePreview(
                                              context,
                                              imageUrl: c.photoUrl,
                                              name: c.name,
                                              subtitle:
                                                  'Pasport: ${c.passport ?? 'Kiritilmagan'} • Telefon: ${c.phone ?? 'Yo‘q'}',
                                            )
                                        : null,
                                    child: ProductThumbnail(
                                      imageUrl: c.photoUrl,
                                      name: c.name,
                                      size: 54,
                                      borderRadius: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Ismi, telefoni, pasporti
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                c.name,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 15,
                                                    color: context.inkColor),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (c.passport != null &&
                                                c.passport!.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: context.isDark
                                                      ? const Color(0xFF21262D)
                                                      : const Color(0xFFEFF6FF),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                      color: context.isDark
                                                          ? AppColors.border
                                                          : const Color(
                                                              0xFFBFDBFE)),
                                                ),
                                                child: Text(
                                                  c.passport!,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: context.isDark
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF1D4ED8),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.phone_outlined,
                                                size: 13,
                                                color: context.mutedColor),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                c.phone?.isNotEmpty == true
                                                    ? c.phone!
                                                    : 'Telefon kiritilmagan',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: context.mutedColor),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.isDark
                                                    ? const Color(0xFF1E2835)
                                                    : const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .receipt_long_outlined,
                                                      size: 11,
                                                      color:
                                                          context.mutedColor),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    '${c.salesCount} ta savdo',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            context.mutedColor),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              'Xarid: ${money(c.totalSpent)}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: context.inkColor),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: hasDebt
                                                    ? const Color(0xFFFCE4E3)
                                                    : AppColors.greenSoft,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                hasDebt
                                                    ? 'Nasiya: ${money(c.totalDebt)}'
                                                    : 'Qarzi yo‘q',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: hasDebt
                                                      ? AppColors.danger
                                                      : AppColors.darkCard,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 6),

                                  // Tahrirlash tugmasi
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 19),
                                    color: context.mutedColor,
                                    tooltip: 'Tahrirlash',
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(
                                        minWidth: 32, minHeight: 32),
                                    onPressed: () => _openCustomerDialog(c),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  const _StatMini(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
            maxLines: 1),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mijoz ma'lumotlarini to'liq ko'rish dialogi (Xarid qilingan tovarlar va Cheklar)
// ---------------------------------------------------------------------------

class _CustomerItemSummary {
  final String productName;
  final double totalQuantity;
  final double totalAmount;
  final int purchaseCount;
  final double lastUnitPrice;
  final DateTime? lastPurchasedAt;

  const _CustomerItemSummary({
    required this.productName,
    required this.totalQuantity,
    required this.totalAmount,
    required this.purchaseCount,
    required this.lastUnitPrice,
    this.lastPurchasedAt,
  });

  String get unit {
    final lower = productName.toLowerCase();
    if (lower.contains('kesish') ||
        lower.contains('silliqlash') ||
        lower.contains('faska') ||
        lower.contains('ariqcha')) {
      return 'metr';
    }
    if (lower.contains('dona') ||
        lower.contains('kley') ||
        lower.contains('disk') ||
        lower.contains('sim')) {
      return 'dona';
    }
    return 'm²';
  }
}

class _CustomerDetailsDialog extends StatefulWidget {
  const _CustomerDetailsDialog({required this.customer, required this.onEdit});
  final Customer customer;
  final VoidCallback onEdit;

  @override
  State<_CustomerDetailsDialog> createState() => _CustomerDetailsDialogState();
}

class _CustomerDetailsDialogState extends State<_CustomerDetailsDialog> {
  late Future<List<SaleResult>> _salesFuture;
  int _currentTab =
      0; // 0: Nimalar xarid qilgan (Tovarlar), 1: Savdolar va Cheklar

  @override
  void initState() {
    super.initState();
    _salesFuture = _fetchCustomerSales();
  }

  Future<List<SaleResult>> _fetchCustomerSales() async {
    final repos = context.read<AppRepositories>();
    try {
      var list = await repos.sales
          .listSales(limit: 500, customerId: widget.customer.id);
      if (list.isEmpty) {
        // Fallback: mijoz ismi yoki telefoni bo'yicha mos keluvchi savdolarni ham topish
        final all = await repos.sales.listSales(limit: 500);
        list = all.where((s) {
          if (s.customerId == widget.customer.id) return true;
          if (s.customerName != null &&
              s.customerName!.trim().toLowerCase() ==
                  widget.customer.name.trim().toLowerCase()) {
            return true;
          }
          if (widget.customer.phone != null &&
              widget.customer.phone!.isNotEmpty &&
              s.customerPhone != null &&
              s.customerPhone!.replaceAll(RegExp(r'\s+'), '') ==
                  widget.customer.phone!.replaceAll(RegExp(r'\s+'), '')) {
            return true;
          }
          return false;
        }).toList();
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  List<_CustomerItemSummary> _aggregateItems(List<SaleResult> sales) {
    final Map<
        String,
        ({
          double qty,
          double amount,
          int count,
          double lastPrice,
          DateTime? lastDate
        })> map = {};

    for (final sale in sales) {
      for (final item in sale.items) {
        final name = item.productName.trim().isEmpty
            ? 'Mahsulot #${item.productId}'
            : item.productName.trim();
        final cur = map[name];
        if (cur == null) {
          map[name] = (
            qty: item.quantity,
            amount: item.lineTotal,
            count: 1,
            lastPrice: item.unitPrice,
            lastDate: sale.createdAt,
          );
        } else {
          map[name] = (
            qty: cur.qty + item.quantity,
            amount: cur.amount + item.lineTotal,
            count: cur.count + 1,
            lastPrice: item.unitPrice,
            lastDate: (cur.lastDate == null ||
                    (sale.createdAt != null &&
                        sale.createdAt!.isAfter(cur.lastDate!)))
                ? sale.createdAt
                : cur.lastDate,
          );
        }
      }
    }

    final list = map.entries
        .map((e) => _CustomerItemSummary(
              productName: e.key,
              totalQuantity: e.value.qty,
              totalAmount: e.value.amount,
              purchaseCount: e.value.count,
              lastUnitPrice: e.value.lastPrice,
              lastPurchasedAt: e.value.lastDate,
            ))
        .toList();

    list.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return list;
  }

  void _openStatement(
      List<SaleResult> sales, List<_CustomerItemSummary> items) {
    showDialog<void>(
      context: context,
      builder: (_) => _CustomerStatementDialog(
        customer: widget.customer,
        sales: sales,
        items: items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final isDark = context.isDark;
    final screenW = MediaQuery.sizeOf(context).width;
    final screenH = MediaQuery.sizeOf(context).height;
    final isMobile = screenW < 650;

    return Dialog(
      backgroundColor: context.cardColor,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 36,
        vertical: isMobile ? 20 : 36,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? 520 : 680,
          maxHeight: screenH * 0.90,
        ),
        child: FutureBuilder<List<SaleResult>>(
          future: _salesFuture,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final sales = snapshot.data ?? [];
            final aggregatedItems = _aggregateItems(sales);

            // Aniq moliyaviy hisob-kitob
            double calcSpent = 0;
            double calcPaid = 0;
            for (final s in sales) {
              calcSpent += s.total;
              calcPaid += s.paid;
            }
            final totalSpent = sales.isNotEmpty ? calcSpent : c.totalSpent;
            final totalDebt = sales.isNotEmpty
                ? (calcSpent - calcPaid).clamp(0, double.infinity).toDouble()
                : c.totalDebt;
            final hasDebt = totalDebt > 0.5;
            final salesCount = sales.isNotEmpty ? sales.length : c.salesCount;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Yuqori sarlavha paneli
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.greenSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.person_pin_rounded,
                            color: AppColors.darkCard, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: context.inkColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (c.phone != null && c.phone!.isNotEmpty)
                              Text(
                                c.phone!,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.muted),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Yopish',
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // 2. Kontent qismi (Scrollable)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Mijoz rasmi va batafsil qismi
                        Row(
                          children: [
                            GestureDetector(
                              onTap:
                                  (c.photoUrl != null && c.photoUrl!.isNotEmpty)
                                      ? () => showProductImagePreview(
                                            context,
                                            imageUrl: c.photoUrl,
                                            name: c.name,
                                            subtitle:
                                                'Pasport: ${c.passport ?? 'Yo‘q'}',
                                          )
                                      : null,
                              child: ProductThumbnail(
                                imageUrl: c.photoUrl,
                                name: c.name,
                                size: 66,
                                borderRadius: 16,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      if (c.passport != null &&
                                          c.passport!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF1E2835)
                                                : const Color(0xFFF1F5F9),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.badge_outlined,
                                                  size: 13,
                                                  color: AppColors.muted),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Pasport: ${c.passport!}',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (c.createdAt != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF1E2835)
                                                : const Color(0xFFF1F5F9),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons.calendar_today_rounded,
                                                  size: 12,
                                                  color: AppColors.muted),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Ro‘yxat: ${formatDateTime(c.createdAt!)}',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.muted),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Tezkor harakat: Hisobot cheki (Akt-sverka)
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: () => _openStatement(
                                            sales, aggregatedItems),
                                        icon: const Icon(
                                            Icons.receipt_long_rounded,
                                            size: 16),
                                        label: const Text(
                                            'Hisobot Cheki (Akt-sverka)',
                                            style: TextStyle(fontSize: 12)),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Moliyaviy xulosa kartochkalari
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E2822)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  const Text('Jami xarid',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted)),
                                  const SizedBox(height: 3),
                                  Text(
                                    money(totalSpent),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: context.inkColor),
                                  ),
                                ],
                              ),
                              Container(
                                  width: 1,
                                  height: 28,
                                  color: context.borderColor),
                              Column(
                                children: [
                                  const Text('Nasiya / Qarz',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted)),
                                  const SizedBox(height: 3),
                                  Text(
                                    money(totalDebt),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      color: hasDebt
                                          ? AppColors.danger
                                          : AppColors.green,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                  width: 1,
                                  height: 28,
                                  color: context.borderColor),
                              Column(
                                children: [
                                  const Text('Savdolar soni',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted)),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$salesCount ta',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: context.inkColor),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Tab selektor: Tovarlar vs Savdolar/Cheklar
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E2835)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => setState(() => _currentTab = 0),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _currentTab == 0
                                          ? (isDark
                                              ? AppColors.darkCard
                                              : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _currentTab == 0
                                          ? [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.06),
                                                  blurRadius: 4)
                                            ]
                                          : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '📦 Nimalar olgan (${aggregatedItems.length})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _currentTab == 0
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: _currentTab == 0
                                              ? context.inkColor
                                              : AppColors.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => setState(() => _currentTab = 1),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _currentTab == 1
                                          ? (isDark
                                              ? AppColors.darkCard
                                              : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _currentTab == 1
                                          ? [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.06),
                                                  blurRadius: 4)
                                            ]
                                          : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '🧾 Cheklar tarixi (${sales.length})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _currentTab == 1
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: _currentTab == 1
                                              ? context.inkColor
                                              : AppColors.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Kontent: Tab 0 (Tovarlar xulosasi) yoki Tab 1 (Cheklar ro'yxati)
                        if (loading) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ] else if (_currentTab == 0) ...[
                          // 1-Tab: Nimalar xarid qilgan (Aggregated items)
                          if (aggregatedItems.isEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 24, horizontal: 16),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E2822)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.shopping_bag_outlined,
                                      size: 36, color: AppColors.muted),
                                  SizedBox(height: 8),
                                  Text(
                                    'Ushbu mijoz hali tovar xarid qilmagan',
                                    style: TextStyle(
                                        color: AppColors.muted, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: aggregatedItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final item = aggregatedItems[idx];
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E2822)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border:
                                        Border.all(color: context.borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: context.isDark
                                              ? const Color(0xFF2B3830)
                                              : const Color(0xFFE2E8F0),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${idx + 1}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: context.inkColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.productName,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: context.inkColor,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${qty(item.totalQuantity)} ${item.unit} • ${item.purchaseCount} ta savdoda olingan',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            money(item.totalAmount),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                              color: context.inkColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '~${money(item.lastUnitPrice)}/${item.unit}',
                                            style: const TextStyle(
                                                fontSize: 10.5,
                                                color: AppColors.muted),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ] else ...[
                          // 2-Tab: Cheklar tarixi
                          if (sales.isEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 24, horizontal: 16),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E2822)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.receipt_long_outlined,
                                      size: 36, color: AppColors.muted),
                                  SizedBox(height: 8),
                                  Text(
                                    'Ushbu mijozga biriktirilgan savdolar mavjud emas',
                                    style: TextStyle(
                                        color: AppColors.muted, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: sales.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, idx) {
                                final s = sales[idx];
                                final hasSaleDebt = s.debt > 0.5;

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E2822)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: hasSaleDebt
                                          ? AppColors.danger
                                              .withValues(alpha: 0.35)
                                          : context.borderColor,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Chek sarlavhasi va sana
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2563EB)
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Chek #${s.id}',
                                              style: const TextStyle(
                                                color: Color(0xFF2563EB),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              formatDateTime(s.createdAt ??
                                                  DateTime.now()),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.muted),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: s.isOrder
                                                  ? Colors.amber
                                                      .withValues(alpha: 0.15)
                                                  : AppColors.greenSoft,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              s.isOrder
                                                  ? 'Buyurtma'
                                                  : 'Bajarildi',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: s.isOrder
                                                    ? Colors.amber.shade800
                                                    : AppColors.darkCard,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 10),

                                      // Chekdagi tovarlar qisqartmasi
                                      if (s.items.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF141C16)
                                                : const Color(0xFFF8FAFC),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              for (final item
                                                  in s.items.take(3))
                                                Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 2),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          '• ${item.productName}',
                                                          style: TextStyle(
                                                              fontSize: 11.5,
                                                              color: context
                                                                  .inkColor),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${qty(item.quantity)} × ${money(item.unitPrice)}',
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color: AppColors
                                                                .muted),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (s.items.length > 3)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 2),
                                                  child: Text(
                                                    '+ yana ${s.items.length - 3} ta tovar...',
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.muted,
                                                        fontStyle:
                                                            FontStyle.italic),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                      ],

                                      // Chek summalari va Chekni chiqarish tugmasi
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Jami: ${money(s.total)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                    color: context.inkColor,
                                                  ),
                                                ),
                                                Text(
                                                  'To‘landi: ${money(s.paid)}'
                                                  '${hasSaleDebt ? ' • Nasiya: ${money(s.debt)}' : ''}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: hasSaleDebt
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                    color: hasSaleDebt
                                                        ? AppColors.danger
                                                        : AppColors.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          FilledButton.icon(
                                            onPressed: () =>
                                                ReceiptDialog.show(context, s),
                                            icon: const Icon(
                                                Icons.receipt_rounded,
                                                size: 15),
                                            label: const Text(
                                                'Chekni ko‘rish / chiqarish',
                                                style:
                                                    TextStyle(fontSize: 11.5)),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: AppColors.green,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),

                const Divider(height: 1),

                // 3. Pastki boshqaruv tugmalari (Mobil va Desktopda toza sig'uvchan)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: widget.onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Tahrirlash',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          onPressed: () =>
                              _openStatement(sales, aggregatedItems),
                          icon: const Icon(Icons.print_rounded, size: 16),
                          label: const Text(
                            'Hisobot Cheki',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.isDark
                                ? AppColors.neonLime
                                : const Color(0xFF10B981),
                            foregroundColor:
                                context.isDark ? AppColors.ink : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mijoz umumiy xaridlar va hisob-kitob kvitansiyasi (Akt-sverka) Cheki
// ---------------------------------------------------------------------------

class _CustomerStatementDialog extends StatefulWidget {
  const _CustomerStatementDialog({
    required this.customer,
    required this.sales,
    required this.items,
  });

  final Customer customer;
  final List<SaleResult> sales;
  final List<_CustomerItemSummary> items;

  @override
  State<_CustomerStatementDialog> createState() =>
      _CustomerStatementDialogState();
}

class _CustomerStatementDialogState extends State<_CustomerStatementDialog> {
  bool _isPrinting = false;

  double get _totalSpent {
    if (widget.sales.isNotEmpty) {
      return widget.sales.fold<double>(0, (sum, s) => sum + s.total);
    }
    return widget.customer.totalSpent;
  }

  double get _totalPaid {
    if (widget.sales.isNotEmpty) {
      return widget.sales.fold<double>(0, (sum, s) => sum + s.paid);
    }
    return (_totalSpent - widget.customer.totalDebt).clamp(0, double.infinity);
  }

  double get _totalDebt => (_totalSpent - _totalPaid).clamp(0, double.infinity);

  String _buildPlainText() {
    final c = widget.customer;
    final sb = StringBuffer();
    sb.writeln('========================================');
    sb.writeln('       ${CompanyInfo.name}              ');
    sb.writeln('      ${CompanyInfo.businessType}       ');
    sb.writeln('   Manzil: ${CompanyInfo.address}       ');
    sb.writeln(' Tel: ${CompanyInfo.phonesInline}       ');
    sb.writeln('========================================');
    sb.writeln('    MIJOZ HISOBOT CHEKI (AKT-SVERKA)    ');
    sb.writeln('Mijoz: ${c.name}');
    if (c.phone != null && c.phone!.isNotEmpty) sb.writeln('Tel: ${c.phone}');
    if (c.passport != null && c.passport!.isNotEmpty)
      sb.writeln('Pasport: ${c.passport}');
    sb.writeln('Hisobot sanasi: ${formatDateTime(DateTime.now())}');
    sb.writeln('Jami savdolar soni: ${widget.sales.length} ta');
    sb.writeln('----------------------------------------');
    sb.writeln('XARID QILINGAN BARCHA TOVARLAR:');
    sb.writeln('----------------------------------------');
    for (final it in widget.items) {
      sb.writeln('• ${it.productName}');
      sb.writeln(
          '  ${qty(it.totalQuantity)} ${it.unit} | Jami: ${money(it.totalAmount)}');
    }
    sb.writeln('----------------------------------------');
    sb.writeln('SAVDOLAR VA CHEKLAR RO‘YXATI:');
    sb.writeln('----------------------------------------');
    for (final s in widget.sales) {
      final dt = formatDateTime(s.createdAt ?? DateTime.now());
      sb.writeln('Chek #${s.id} ($dt):');
      sb.writeln(
          '  Jami: ${money(s.total)} | To‘landi: ${money(s.paid)} | Nasiya: ${money(s.debt)}');
    }
    sb.writeln('========================================');
    sb.writeln('MOLIYAVIY YAKUNIY BALANS:');
    sb.writeln('  JAMI XARIDLAR:     ${money(_totalSpent)}');
    sb.writeln('  JAMI TO‘LANGAN:    ${money(_totalPaid)}');
    sb.writeln('  HOZIRGI NASIYA:    ${money(_totalDebt)}');
    sb.writeln('========================================');
    sb.writeln('Xaridingiz va hamkorligingiz uchun rahmat!');
    return sb.toString();
  }

  Future<void> _printPdf(BuildContext context) async {
    setState(() => _isPrinting = true);
    try {
      final doc = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) => [
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(CompanyInfo.name,
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 3),
                  pw.Text(
                      '${CompanyInfo.businessType} • Manzil: ${CompanyInfo.address}',
                      style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                      'Tel: ${CompanyInfo.phonesInline}',
                      style: pw.TextStyle(font: font, fontSize: 9.5)),
                  pw.SizedBox(height: 6),
                  pw.Text('MIJOZ SAVDOLARI VA TO‘LOVLAR HISOBOTI (AKT-SVERKA)',
                      style: pw.TextStyle(font: fontBold, fontSize: 13)),
                  pw.Divider(thickness: 1),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Mijoz: ${widget.customer.name}',
                    style: pw.TextStyle(font: fontBold, fontSize: 11)),
                pw.Text('Sana: ${formatDateTime(DateTime.now())}',
                    style: pw.TextStyle(font: font, fontSize: 10)),
              ],
            ),
            if (widget.customer.phone != null &&
                widget.customer.phone!.isNotEmpty)
              pw.Text('Tel: ${widget.customer.phone}',
                  style: pw.TextStyle(font: font, fontSize: 10)),
            pw.SizedBox(height: 12),
            pw.Text('1. Xarid qilingan barcha mahsulotlar:',
                style: pw.TextStyle(font: fontBold, fontSize: 11)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: [
                '№',
                'Mahsulot / Xizmat',
                'Miqdori',
                'O‘rtacha narxi',
                'Jami summa'
              ],
              data: [
                for (var i = 0; i < widget.items.length; i++)
                  [
                    '${i + 1}',
                    widget.items[i].productName,
                    '${qty(widget.items[i].totalQuantity)} ${widget.items[i].unit}',
                    money(widget.items[i].lastUnitPrice),
                    money(widget.items[i].totalAmount),
                  ],
              ],
              headerStyle: pw.TextStyle(
                  font: fontBold, fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: pw.TextStyle(font: font, fontSize: 8.5),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
            ),
            pw.SizedBox(height: 14),
            pw.Text('2. Savdolar va cheklar tarixi:',
                style: pw.TextStyle(font: fontBold, fontSize: 11)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: [
                'Chek №',
                'Sana',
                'Jami summa',
                'To‘langan',
                'Nasiya / Qarz'
              ],
              data: [
                for (final s in widget.sales)
                  [
                    '#${s.id}',
                    formatDateTime(s.createdAt ?? DateTime.now()),
                    money(s.total),
                    money(s.paid),
                    money(s.debt),
                  ],
              ],
              headerStyle: pw.TextStyle(
                  font: fontBold, fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: pw.TextStyle(font: font, fontSize: 8.5),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
            ),
            pw.SizedBox(height: 16),
            pw.Divider(thickness: 1),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Jami xaridlar summasi: ${money(_totalSpent)}',
                        style: pw.TextStyle(font: fontBold, fontSize: 11)),
                    pw.Text('Jami to‘langan summa: ${money(_totalPaid)}',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text('Hozirgi nasiya / qarz: ${money(_totalDebt)}',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 12,
                            color: _totalDebt > 0
                                ? PdfColors.red
                                : PdfColors.green)),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: 'Mijoz_Hisoboti_${widget.customer.name.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Chop etishda xatolik: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _copyToClipboard() {
    final text = _buildPlainText();
    Clipboard.setData(ClipboardData(text: text));
    showMessage(context,
        'Hisobot nusxalandi! Telegram orqali mijozga yuborishingiz mumkin.');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final c = widget.customer;
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 600;

    return Dialog(
      backgroundColor: context.cardColor,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 20 : 36,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          children: [
            // Sarlavha
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded,
                      color: AppColors.green, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mijoz Akt-sverkasi • ${c.name}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: context.inkColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Termal chek uslubidagi qog'oz varag'i
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF141C16)
                        : const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: Text(
                          'NTJ — NAMUNA TOSH JILO',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5),
                        ),
                      ),
                      const Center(
                        child: Text(
                          'Tabiiy tosh va granit markazi',
                          style:
                              TextStyle(fontSize: 10.5, color: AppColors.muted),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Center(
                        child: Text(
                          'MIJOZ SAVDOLAR HISOBOTI (AKT-SVERKA)',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '--------------------------------------------------',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Mijoz: ${c.name}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12)),
                          Text(formatDateTime(DateTime.now()),
                              style: const TextStyle(
                                  fontSize: 10, color: AppColors.muted)),
                        ],
                      ),
                      if (c.phone != null && c.phone!.isNotEmpty)
                        Text('Tel: ${c.phone}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted)),
                      const Text(
                        '--------------------------------------------------',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),

                      // Tovarlar jadvali
                      const Text('OLINGAN TOVARLAR XULOSASI:',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 11.5)),
                      const SizedBox(height: 6),
                      for (final it in widget.items) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.productName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12),
                                  ),
                                  Text(
                                    '${qty(it.totalQuantity)} ${it.unit} (~${money(it.lastUnitPrice)})',
                                    style: const TextStyle(
                                        fontSize: 10.5, color: AppColors.muted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              money(it.totalAmount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],

                      const SizedBox(height: 6),
                      const Text(
                        '--------------------------------------------------',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const Text('SAVDOLAR (CHEKLAR) RO‘YXATI:',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 11.5)),
                      const SizedBox(height: 6),
                      for (final s in widget.sales) ...[
                        Row(
                          children: [
                            Text('Chek #${s.id}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formatDateTime(s.createdAt ?? DateTime.now()),
                                style: const TextStyle(
                                    fontSize: 10, color: AppColors.muted),
                              ),
                            ),
                            Text(money(s.total),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5)),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Text(
                            'To‘landi: ${money(s.paid)}${s.debt > 0 ? ' • Nasiya: ${money(s.debt)}' : ''}',
                            style: TextStyle(
                              fontSize: 10,
                              color: s.debt > 0
                                  ? AppColors.danger
                                  : AppColors.muted,
                              fontWeight: s.debt > 0
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],

                      const Text(
                        '==================================================',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),

                      // Yakuniy moliyaviy hisobot
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('JAMI XARIDLAR:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 12)),
                          Text(money(_totalSpent),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('JAMI TO‘LANGAN:',
                              style: TextStyle(
                                  fontSize: 11.5, color: AppColors.muted)),
                          Text(money(_totalPaid),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'HOZIRGI NASIYA / QARZ:',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: _totalDebt > 0
                                  ? AppColors.danger
                                  : AppColors.green,
                            ),
                          ),
                          Text(
                            money(_totalDebt),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: _totalDebt > 0
                                  ? AppColors.danger
                                  : AppColors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Center(
                        child: Text(
                          'Xaridingiz va hamkorligingiz uchun rahmat!',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                              color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            // Tugmalar: Chop etish, Nusxalash
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Nusxalash',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isPrinting ? null : () => _printPdf(context),
                      icon: _isPrinting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.print_rounded, size: 16),
                      label: Text(
                        _isPrinting ? 'Tayyorlanmoqda...' : 'Chop etish (PDF)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
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

// ---------------------------------------------------------------------------
// Mijoz yaratish / tahrirlash dialogi
// ---------------------------------------------------------------------------

class CustomerDialog extends StatefulWidget {
  const CustomerDialog({super.key, this.customer});
  final Customer? customer;

  @override
  State<CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<CustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl =
      TextEditingController(text: widget.customer?.name ?? '');
  late final _phoneCtrl =
      TextEditingController(text: widget.customer?.phone ?? '');
  late final _passportCtrl =
      TextEditingController(text: widget.customer?.passport ?? '');
  String? _photoUrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.customer?.photoUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passportCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final custRepo = context.read<AppRepositories>().customers;
      final bytes = await pickOrCaptureCustomerImage(context, source);
      if (bytes == null || bytes.isEmpty) return;

      String finalUrl;
      try {
        final decoded = img.decodeImage(Uint8List.fromList(bytes));
        if (decoded != null) {
          final resized = (decoded.width > 480 || decoded.height > 480)
              ? img.copyResize(decoded,
                  width: decoded.width >= decoded.height ? 480 : null,
                  height: decoded.height > decoded.width ? 480 : null)
              : decoded;
          final jpg = img.encodeJpg(resized, quality: 78);
          finalUrl = 'data:image/jpeg;base64,${base64Encode(jpg)}';
        } else {
          finalUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        }
      } catch (_) {
        finalUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      LocalImageStore.saveCustomerImage(
          widget.customer?.id, finalUrl, _phoneCtrl.text, _nameCtrl.text);

      if (mounted) {
        setState(() {
          _photoUrl = finalUrl;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Rasm olishda xatolik: $e');
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = context.read<AppRepositories>().customers;
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      final passport = _passportCtrl.text.trim();

      if (widget.customer == null) {
        // Yangi mijoz
        await repo.createCustomer(
          Customer(
            id: 0,
            name: name,
            phone: phone.isNotEmpty ? phone : null,
            passport: passport.isNotEmpty ? passport : null,
            photoUrl: _photoUrl,
          ),
        );
      } else {
        // Tahrirlash
        await repo.updateCustomer(
          widget.customer!.copyWith(
            name: name,
            phone: phone.isNotEmpty ? phone : null,
            passport: passport.isNotEmpty ? passport : null,
            photoUrl: _photoUrl,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customer != null;

    return Dialog(
      backgroundColor: context.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      isEdit ? 'Mijozni tahrirlash' : 'Yangi mijoz qo‘shish',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Fotosurat qismi
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => _pickImage(ImageSource.gallery),
                        child: Stack(
                          children: [
                            ProductThumbnail(
                              imageUrl: _photoUrl,
                              name: _nameCtrl.text.isNotEmpty
                                  ? _nameCtrl.text
                                  : 'Mijoz',
                              size: 88,
                              borderRadius: 22,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: AppColors.darkCard,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt_rounded,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_rounded,
                                size: 16),
                            label: const Text('Kamera',
                                style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_rounded,
                                size: 16),
                            label: const Text('Galereya',
                                style: TextStyle(fontSize: 12)),
                          ),
                          if (_photoUrl != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => setState(() => _photoUrl = null),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 18, color: AppColors.danger),
                              tooltip: 'Rasmni o‘chirish',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Ismi
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ism va Familiya *',
                    hintText: 'Masalan: Rustam Karimov',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Ism kiritilishi shart'
                      : null,
                ),
                const SizedBox(height: 12),

                // Telefon
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon raqami',
                    hintText: '+998 90 123 45 67',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),

                // Pasport
                TextFormField(
                  controller: _passportCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Pasport seriya va raqami',
                    hintText: 'AA 1234567',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12)),
                ],

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        child: const Text('Bekor'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(isEdit ? 'Saqlash' : 'Qo‘shish',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
