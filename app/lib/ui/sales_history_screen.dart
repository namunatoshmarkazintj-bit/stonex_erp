import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';
import 'receipt_dialog.dart';
import 'return_product_dialog.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late Future<List<SaleResult>> _salesFuture;
  final _searchCtrl = TextEditingController();
  String _dateFilter = 'Barchasi'; // 'Barchasi', 'Bugun', 'Shu hafta', 'Shu oy'
  String _statusFilter = 'Barchasi'; // 'Barchasi', 'To‘langan', 'Nasiyali'

  SalesRepository get _repo => context.read<AppRepositories>().sales;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadSales() {
    setState(() {
      _salesFuture = _repo.listSales(limit: 150);
    });
  }

  bool _matchesDate(DateTime? dt) {
    if (dt == null) return _dateFilter == 'Barchasi';
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'Bugun':
        return dt.year == now.year && dt.month == now.month && dt.day == now.day;
      case 'Shu hafta':
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final zeroStart = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        return dt.isAfter(zeroStart);
      case 'Shu oy':
        return dt.year == now.year && dt.month == now.month;
      default:
        return true;
    }
  }

  bool _matchesStatus(SaleResult s) {
    switch (_statusFilter) {
      case 'To‘langan':
        return s.debt <= 0.005;
      case 'Nasiyali':
        return s.debt > 0.005;
      default:
        return true;
    }
  }

  bool _matchesSearch(SaleResult s, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if ('chek #${s.id}'.contains(q) || s.id.toString().contains(q)) return true;
    if (s.customerName?.toLowerCase().contains(q) == true) return true;
    if (s.customerPhone?.toLowerCase().contains(q) == true) return true;
    if (s.customerPassport?.toLowerCase().contains(q) == true) return true;
    if (s.cashierName?.toLowerCase().contains(q) == true) return true;
    for (final it in s.items) {
      if (it.productName.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  Future<void> _payDebtDialog(SaleResult sale) async {
    final ctrl = TextEditingController(text: sale.debt.round().toString());
    String method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: context.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Qarz to‘lash — Chek #${sale.id}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mijoz: ${sale.customerName ?? 'Noma’lum'}\nJami qarz: ${money(sale.debt)}',
                  style: TextStyle(color: context.subtextColor, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'To‘lov summasi (so‘m)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'To‘lov usuli'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Naqd pul')),
                    DropdownMenuItem(value: 'card', child: Text('Plastik karta / Terminal')),
                  ],
                  onChanged: (v) {
                    if (v != null) setS(() => method = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.neonLime, foregroundColor: AppColors.ink),
              child: const Text('To‘lovni qabul qilish'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      final val = parseInput(ctrl.text);
      if (val == null || val <= 0) {
        showMessage(context, 'Noto‘g‘ri summa', error: true);
        return;
      }
      try {
        final updated = await _repo.payDebt(sale.id, val, method: method);
        if (mounted) {
          showMessage(context, 'Chek #${sale.id} bo‘yicha ${money(val)} qabul qilindi');
          _loadSales();
          // Oyna ko'rsatish
          ReceiptDialog.show(context, updated);
        }
      } catch (e) {
        if (mounted) showMessage(context, e.toString(), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<SaleResult>>(
        future: _salesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Xatolik: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _loadSales,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Qayta yuklash'),
                  ),
                ],
              ),
            );
          }

          final allSales = snapshot.data ?? [];
          final query = _searchCtrl.text.trim();
          final filtered = allSales.where((s) {
            return _matchesDate(s.createdAt) && _matchesStatus(s) && _matchesSearch(s, query);
          }).toList();

          final totalSum = filtered.fold<double>(0, (sum, s) => sum + s.total);
          final totalPaid = filtered.fold<double>(0, (sum, s) => sum + s.paid);
          final totalDebt = filtered.fold<double>(0, (sum, s) => sum + s.debt);

          return RefreshIndicator(
            onRefresh: () async => _loadSales(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Top header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Savdolar Jurnali',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kim nimani, qachon, kimga va qanchaga sotganini ko‘rish hamda chek berish',
                            style: TextStyle(color: context.subtextColor, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Yangilash',
                      onPressed: _loadSales,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // KPI Stat cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmall = constraints.maxWidth < 440;
                    final cardWidth = isSmall
                        ? (constraints.maxWidth < 360 ? constraints.maxWidth : (constraints.maxWidth - 12) / 2)
                        : (constraints.maxWidth < 800 ? (constraints.maxWidth - 24) / 3 : 210.0);
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _kpiCard(
                          context,
                          title: 'Jami Savdo Summasi',
                          value: money(totalSum),
                          icon: Icons.payments_rounded,
                          color: AppColors.neonLime,
                          width: cardWidth,
                        ),
                        _kpiCard(
                          context,
                          title: 'Undirilgan Pul (Kassa)',
                          value: money(totalPaid),
                          icon: Icons.account_balance_wallet_rounded,
                          color: const Color(0xFF10B981),
                          width: cardWidth,
                        ),
                        _kpiCard(
                          context,
                          title: 'Nasiyalar (Qarzlar)',
                          value: money(totalDebt),
                          icon: Icons.pending_actions_rounded,
                          color: totalDebt > 0 ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                          width: cardWidth,
                        ),
                        _kpiCard(
                          context,
                          title: 'Cheklar Soni',
                          value: '${filtered.length} ta',
                          icon: Icons.receipt_long_rounded,
                          color: const Color(0xFF38BDF8),
                          width: cardWidth,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),

                // Search & Filter controls
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Mijoz ismi, telefon, sotuvchi, tovar yoki chek raqami...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      // Sana filtrlari qatori
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: context.borderColor.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 12, color: context.subtextColor),
                                const SizedBox(width: 5),
                                Text(
                                  'Sana:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: context.inkColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final d in ['Barchasi', 'Bugun', 'Shu hafta', 'Shu oy'])
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: Text(d, style: const TextStyle(fontSize: 12)),
                                        selected: _dateFilter == d,
                                        onSelected: (sel) {
                                          if (sel) setState(() => _dateFilter = d);
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Holat filtrlari qatori
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: context.borderColor.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline_rounded, size: 12, color: context.subtextColor),
                                const SizedBox(width: 5),
                                Text(
                                  'Holat:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: context.inkColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final s in ['Barchasi', 'To‘langan', 'Nasiyali'])
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: Text(s, style: const TextStyle(fontSize: 12)),
                                        selected: _statusFilter == s,
                                        onSelected: (sel) {
                                          if (sel) setState(() => _statusFilter = s);
                                        },
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
                const SizedBox(height: 16),

                // Sales records
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 52, color: context.subtextColor.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'Birorta ham savdo topilmadi',
                          style: TextStyle(color: context.subtextColor, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                else
                  for (final sale in filtered)
                    _saleCard(context, sale),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kpiCard(BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    double? width,
  }) {
    return Container(
      width: width ?? 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(color: context.subtextColor, fontSize: 11, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _saleCard(BuildContext context, SaleResult sale) {
    final hasDebt = sale.debt > 0.005;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: context.cardBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: hasDebt ? const Color(0xFFEF4444).withOpacity(0.35) : context.borderColor,
            width: hasDebt ? 1.4 : 1,
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasDebt
                  ? const Color(0xFFEF4444).withOpacity(0.15)
                  : const Color(0xFF10B981).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasDebt ? Icons.pending_actions_rounded : Icons.check_circle_rounded,
              color: hasDebt ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              size: 24,
            ),
          ),
          title: Row(
            children: [
              Text(
                'Chek #${sale.id}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: hasDebt
                      ? const Color(0xFFEF4444).withOpacity(0.15)
                      : const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hasDebt ? 'Nasiya' : 'To‘langan',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: hasDebt ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          trailing: Text(
            money(sale.total),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_rounded, size: 14, color: context.subtextColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        sale.customerName?.isNotEmpty == true
                            ? '${sale.customerName} ${sale.customerPhone ?? ''}'
                            : 'Chakana xaridor',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: sale.customerName?.isNotEmpty == true
                              ? context.inkColor
                              : context.subtextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.badge_rounded, size: 14, color: context.subtextColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Sotuvchi: ${sale.cashierName ?? 'Kassir'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: context.subtextColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time_rounded, size: 13, color: context.subtextColor),
                        const SizedBox(width: 4),
                        Text(
                          formatDateTime(sale.createdAt ?? DateTime.now()),
                          style: TextStyle(fontSize: 11, color: context.subtextColor),
                        ),
                      ],
                    ),
                    Text(
                      'To‘landi: ${money(sale.paid)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w700),
                    ),
                    if (hasDebt)
                      Text(
                        'Qarz: ${money(sale.debt)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w800),
                      ),
                  ],
                ),
              ],
            ),
          ),
          children: [
            const Divider(),
            // Nima sotilgan: tovarlar jadvali
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sotilgan Mahsulotlar (${sale.items.length} xil):',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  for (final it in sale.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.neonLime,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  it.productName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                Text(
                                  '${it.quantity.toStringAsFixed(1)} dona/m² × ${money(it.unitPrice)}',
                                  style: TextStyle(color: context.subtextColor, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            money(it.lineTotal),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Action tugmalar
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasDebt)
                  FilledButton.icon(
                    onPressed: () => _payDebtDialog(sale),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    icon: const Icon(Icons.payment_rounded, size: 16),
                    label: const Text('Qarz to‘lash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                if (sale.status != 'cancelled' && sale.status != 'returned')
                  OutlinedButton.icon(
                    onPressed: () => ReturnProductDialog.show(context, sale, onSuccess: _loadSales),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD97706),
                      side: const BorderSide(color: Color(0xFFF59E0B)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.assignment_return_rounded, size: 16),
                    label: const Text('Qaytarish', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                FilledButton.icon(
                  onPressed: () => ReceiptDialog.show(context, sale),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.neonLime,
                    foregroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.receipt_rounded, size: 16),
                  label: const Text('Chek chiqarish', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    ),
  );
}
}
