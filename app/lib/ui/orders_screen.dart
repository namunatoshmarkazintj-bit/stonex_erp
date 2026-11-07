import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/local_image_store.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'deliveries_screen.dart';
import 'receipt_dialog.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.onNewOrder});
  final VoidCallback? onNewOrder;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'Faol (Kutilmoqda)'; // 'Barchasi', 'Faol (Kutilmoqda)', 'Topshirilgan', 'Bekor qilingan'
  bool _loading = true;
  String? _error;
  List<SaleResult> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repos = context.read<AppRepositories>();
      final allSales = await repos.sales.listSales(limit: 200);
      // Buyurtmalar: status == 'order' yoki 'cancelled' yoki (status == 'completed' va izohi mavjud/avval buyurtma bo'lgan)
      final orders = allSales.where((s) => s.isOrder || s.status == 'cancelled' || s.note != null).toList();
      if (mounted) {
        setState(() {
          _orders = orders;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<SaleResult> get _filteredOrders {
    var list = _orders;

    // Status filter
    if (_statusFilter == 'Faol (Kutilmoqda)') {
      list = list.where((o) => o.status == 'order').toList();
    } else if (_statusFilter == 'Topshirilgan') {
      list = list.where((o) => o.status == 'completed').toList();
    } else if (_statusFilter == 'Bekor qilingan') {
      list = list.where((o) => o.status == 'cancelled').toList();
    }

    // Search filter
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((o) {
        final idStr = '#${o.id}';
        final name = o.customerName?.toLowerCase() ?? '';
        final phone = o.customerPhone?.toLowerCase() ?? '';
        final note = o.note?.toLowerCase() ?? '';
        final items = o.items.map((i) => i.productName.toLowerCase()).join(' ');
        return idStr.contains(q) ||
            o.id.toString().contains(q) ||
            name.contains(q) ||
            phone.contains(q) ||
            note.contains(q) ||
            items.contains(q);
      }).toList();
    }

    return list;
  }

  Future<void> _fulfillOrder(SaleResult order) async {
    final updated = await showDialog<SaleResult?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OrderFulfillDialog(order: order),
    );

    if (updated != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF10B981),
          content: Text('✓ Buyurtma #${order.id} muvaffaqiyatli topshirildi va ombordan chiqarildi!'),
        ),
      );
      _loadOrders();
      await ReceiptDialog.show(context, updated);
    }
  }

  Future<void> _cancelOrder(SaleResult order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 10),
            Text('Buyurtmani bekor qilish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text('Haqiqatan ham #${order.id} sonli buyurtmani bekor qilmoqchimisiz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Yo‘q')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Bekor qilish'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final repos = context.read<AppRepositories>();
      await repos.sales.cancelOrder(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Buyurtma #${order.id} bekor qilindi'),
        ),
      );
      _loadOrders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _payDebtDialog(SaleResult order) async {
    final ctrl = TextEditingController(text: order.debt.round().toString());
    var method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: context.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'To‘lov qabul qilish — Buyurtma #${order.id}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions_rounded, color: Color(0xFFEF4444), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Qolgan summa: ${money(order.debt)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFEF4444)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'To‘lov summasi'),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: Text('Naqd')),
                    ButtonSegment(value: 'card', label: Text('Karta')),
                    ButtonSegment(value: 'bank', label: Text('Hisob')),
                  ],
                  selected: {method},
                  onSelectionChanged: (s) => setS(() => method = s.first),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.neonLime, foregroundColor: AppColors.ink),
              child: const Text('To‘lovni tasdiqlash', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );

    final val = parseInput(ctrl.text);
    ctrl.dispose();
    if (ok == true && val != null && val > 0 && mounted) {
      try {
        final repos = context.read<AppRepositories>();
        final updated = await repos.sales.payDebt(order.id, val, method: method);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
            content: Text('Buyurtma #${order.id} uchun ${money(val)} qabul qilindi'),
          ),
        );
        _loadOrders();
        await ReceiptDialog.show(context, updated);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(behavior: SnackBarBehavior.floating, content: Text(e.toString()), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _createDeliveryForOrder(SaleResult order) async {
    final repos = context.read<AppRepositories>();
    final items = order.items
        .map((i) => DeliveryItem(
              productId: i.productId,
              productName: i.productName,
              quantity: i.quantity,
              unit: 'dona',
            ))
        .toList();

    final created = await showDialog<Delivery>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DeliveryEditDialog(
        saleId: order.id,
        initialRecipientName: order.customerName,
        initialRecipientPhone: order.customerPhone,
        initialAddress: order.note,
        initialItems: items,
      ),
    );

    if (created != null && mounted) {
      try {
        await repos.deliveries.create(created);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Buyurtma #${order.id} uchun yetkazib berish (mashina: ${created.vehicleNumber}) reysga qo‘shildi'),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text('Xatolik: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildFilterSegment({
    required String label,
    required int count,
    required Color? dotColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6.5),
        decoration: BoxDecoration(
          color: isSelected
              ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(context.isDark ? 0.25 : 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isSelected && dotColor != null && count > 0) ...[
              Container(
                width: 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (context.isDark ? AppColors.ink : Colors.white)
                    : (context.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? (context.isDark
                        ? AppColors.ink.withOpacity(0.15)
                        : Colors.white.withOpacity(0.2))
                    : (context.isDark ? const Color(0xFF262C36) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? (context.isDark ? AppColors.ink : Colors.white)
                      : context.inkColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;
    final totalOrders = _orders.length;
    final activeOrders = _orders.where((o) => o.status == 'order').length;
    final completedOrders = _orders.where((o) => o.status == 'completed').length;
    final cancelledOrders = _orders.where((o) => o.status == 'cancelled').length;
    final totalAdvances = _orders.fold<double>(0, (a, o) => a + o.paid);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        color: AppColors.neonLime,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // KPI kartochkalari
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 640;
                final cardWidth = isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _KpiCard(
                      title: 'Jami Buyurtmalar',
                      value: '$totalOrders ta',
                      icon: Icons.assignment_rounded,
                      color: const Color(0xFF3B82F6),
                      width: cardWidth,
                    ),
                    _KpiCard(
                      title: 'Kutilmoqda (Faol)',
                      value: '$activeOrders ta',
                      icon: Icons.hourglass_top_rounded,
                      color: const Color(0xFFF59E0B),
                      width: cardWidth,
                    ),
                    _KpiCard(
                      title: 'Topshirilgan',
                      value: '$completedOrders ta',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF10B981),
                      width: cardWidth,
                    ),
                    _KpiCard(
                      title: 'Avanslar Summasi',
                      value: money(totalAdvances),
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppColors.neonLimeDark,
                      width: cardWidth,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Qidiruv va Filterlar (Zamonaviy burchaksiz kapsulalar)
            LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth > 820;

                final searchField = SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Mijoz ismi, telefon, buyurtma # yoki mahsulot nomi...',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: context.subtextColor.withOpacity(0.8),
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: context.cardBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide(
                          color: context.isDark ? AppColors.neonLime : const Color(0xFF3B82F6),
                          width: 1.4,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                );

                final filterCapsule = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      color: context.isDark ? AppColors.darkCard : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: context.borderColor.withOpacity(0.6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in [
                          ('Faol (Kutilmoqda)', activeOrders, const Color(0xFFF59E0B)),
                          ('Barchasi', totalOrders, null),
                          ('Topshirilgan', completedOrders, const Color(0xFF10B981)),
                          ('Bekor qilingan', cancelledOrders, const Color(0xFFEF4444)),
                        ])
                          _buildFilterSegment(
                            label: item.$1,
                            count: item.$2,
                            dotColor: item.$3,
                            isSelected: _statusFilter == item.$1,
                            onTap: () => setState(() => _statusFilter = item.$1),
                          ),
                      ],
                    ),
                  ),
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 12),
                      filterCapsule,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    filterCapsule,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Buyurtmalar ro'yxati
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppColors.neonLime),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 40),
                      const SizedBox(height: 12),
                      Text('Xatolik yuz berdi: $_error', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadOrders, child: const Text('Qayta urinish')),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.assignment_late_outlined, size: 54, color: context.subtextColor.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    Text(
                      'Buyurtmalar topilmadi',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.inkColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kassada tovarlarni savatga qo‘shib, to‘lov oynasida "Buyurtma (Pre-order)" sifatida saqlashingiz mumkin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: context.subtextColor),
                    ),
                  ],
                ),
              )
            else
              for (final order in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _OrderCard(
                    order: order,
                    onFulfill: () => _fulfillOrder(order),
                    onCancel: () => _cancelOrder(order),
                    onPay: () => _payDebtDialog(order),
                    onReceipt: () => ReceiptDialog.show(context, order),
                    onDelivery: () => _createDeliveryForOrder(order),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.width,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
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
                  style: TextStyle(fontSize: 11, color: context.subtextColor, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: context.inkColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onFulfill,
    required this.onCancel,
    required this.onPay,
    required this.onReceipt,
    required this.onDelivery,
  });

  final SaleResult order;
  final VoidCallback onFulfill;
  final VoidCallback onCancel;
  final VoidCallback onPay;
  final VoidCallback onReceipt;
  final VoidCallback onDelivery;

  @override
  Widget build(BuildContext context) {
    final isOrder = order.status == 'order';
    final isCancelled = order.status == 'cancelled';
    final isCompleted = order.status == 'completed';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isOrder) {
      statusColor = const Color(0xFFF59E0B);
      statusText = 'Kutilmoqda';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (isCancelled) {
      statusColor = const Color(0xFFEF4444);
      statusText = 'Bekor qilingan';
      statusIcon = Icons.cancel_outlined;
    } else {
      statusColor = const Color(0xFF10B981);
      statusText = 'Topshirilgan';
      statusIcon = Icons.check_circle_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.borderColor.withOpacity(0.75),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Yuqori qism (Header)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                // Holat belgisi (Doiraviy zamonaviy avatar)
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor.withOpacity(0.25), width: 1.2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(statusIcon, color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),

                // Buyurtma raqami, holat kapsulasi va sana
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 3,
                        children: [
                          Text(
                            'Buyurtma #${order.id}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: context.inkColor,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: statusColor.withOpacity(0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 10.5, color: statusColor),
                                const SizedBox(width: 3.5),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: context.subtextColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              formatDateTime(order.createdAt ?? DateTime.now()),
                              style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Jami summa
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Jami summa',
                        style: TextStyle(fontSize: 11, color: context.subtextColor, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          money(order.total),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                            color: context.inkColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Mijoz va Izoh (Nozik toza karta)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: context.isDark ? AppColors.darkCard : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded, size: 16, color: context.subtextColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.customerName?.isNotEmpty == true
                              ? '${order.customerName} ${order.customerPhone ?? ''}'
                              : 'Noma‘lum mijoz',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: context.inkColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (order.note != null && order.note!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes_rounded, size: 15, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Izoh: ${order.note}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.inkColor,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (order.receivedByName != null && order.receivedByName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.how_to_reg_rounded, size: 16, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Qabul qildi: ',
                                style: TextStyle(fontSize: 11.5, color: context.subtextColor, fontWeight: FontWeight.w500),
                              ),
                              Flexible(
                                child: Text(
                                  order.receivedByName!,
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.inkColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (order.receivedByPhone != null && order.receivedByPhone!.isNotEmpty)
                                Text(' (${order.receivedByPhone})', style: TextStyle(fontSize: 11.5, color: context.subtextColor)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                order.deliveryType == 'delivery' ? Icons.local_shipping_outlined : Icons.store_mall_directory_outlined,
                                size: 12,
                                color: context.subtextColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                order.deliveryType == 'delivery' ? 'Yetkazib berildi (Mashinada)' : 'Ombordan olib ketildi',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.subtextColor),
                              ),
                              if (order.receiverDocOrCar != null && order.receiverDocOrCar!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text('• ${order.receiverDocOrCar}', style: TextStyle(fontSize: 11, color: context.subtextColor)),
                              ],
                            ],
                          ),
                          if (order.fulfilledByName != null || order.fulfilledAt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Topshirdi: ${order.fulfilledByName ?? 'Kassir'} ${order.fulfilledAt != null ? '• ${formatDateTime(order.fulfilledAt!)}' : ''}',
                              style: TextStyle(fontSize: 10.5, color: context.subtextColor, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),

          // 3. Mahsulotlar ro'yxati (Toza va tartibli)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF181D24) : const Color(0xFFF1F5F9).withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (int i = 0; i < order.items.length; i++) ...[
                  if (i > 0)
                    Divider(height: 12, thickness: 0.5, color: context.borderColor.withOpacity(0.4)),
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 14, color: context.subtextColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.items[i].productName,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.inkColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${order.items[i].quantity.toStringAsFixed(1)} × ${money(order.items[i].unitPrice)}',
                        style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        money(order.items[i].lineTotal),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.inkColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 4. To'lov holati kapsulalari (Avans va Qoldiq qarz)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                // Avans kapsulasi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF10B981)),
                      const SizedBox(width: 5),
                      Text(
                        'Avans: ${money(order.paid)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),

                // Qoldiq qarz kapsulasi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (order.debt > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: (order.debt > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withOpacity(0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.debt > 0 ? Icons.error_outline_rounded : Icons.task_alt_rounded,
                        size: 13,
                        color: order.debt > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        order.debt > 0 ? 'Qoldiq: ${money(order.debt)}' : 'To‘liq to‘langan',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: order.debt > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: context.borderColor.withOpacity(0.6)),

          // 5. Harakat tugmalari (Zamonaviy burchaksiz kapsulalar)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Chek tugmasi
                OutlinedButton.icon(
                  onPressed: onReceipt,
                  icon: const Icon(Icons.receipt_long_rounded, size: 15),
                  label: const Text('Chek', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.inkColor,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // To'lov qo'shish
                if (order.debt > 0.005 && !isCancelled)
                  OutlinedButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.payment_rounded, size: 15, color: Color(0xFF10B981)),
                    label: const Text(
                      'To‘lov qo‘shish',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.5)),
                      backgroundColor: const Color(0xFF10B981).withOpacity(0.06),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                // Bekor qilish
                if (isOrder) ...[
                  // Yetkazish (Logistika / Avtomobil)
                  OutlinedButton.icon(
                    onPressed: onDelivery,
                    icon: const Icon(Icons.local_shipping_rounded, size: 15, color: Color(0xFF0284C7)),
                    label: const Text(
                      'Yetkazish',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0284C7)),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0284C7),
                      side: BorderSide(color: const Color(0xFF0284C7).withOpacity(0.5)),
                      backgroundColor: const Color(0xFF0284C7).withOpacity(0.06),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFEF4444)),
                    label: const Text(
                      'Bekor qilish',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFEF4444)),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.4)),
                      backgroundColor: const Color(0xFFEF4444).withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  // Topshirish (Primary)
                  FilledButton.icon(
                    onPressed: onFulfill,
                    icon: const Icon(Icons.task_alt_rounded, size: 16),
                    label: const Text('Topshirish', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OrderFulfillDialog extends StatefulWidget {
  const OrderFulfillDialog({super.key, required this.order});

  final SaleResult order;

  @override
  State<OrderFulfillDialog> createState() => _OrderFulfillDialogState();
}

class _OrderFulfillDialogState extends State<OrderFulfillDialog> {
  final _formKey = GlobalKey<FormState>();

  String _receiverType = 'customer'; // 'customer', 'driver', 'agent'
  String _deliveryType = 'pickup'; // 'pickup', 'delivery'

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _docOrCarCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _payAmountCtrl;

  bool _payDebtNow = true;
  String _payMethod = 'cash'; // 'cash', 'card', 'transfer'
  bool _busy = false;
  String? _error;

  List<AppUser> _drivers = [];

  @override
  void initState() {
    super.initState();
    final ord = widget.order;
    _nameCtrl = TextEditingController(text: ord.customerName ?? '');
    _phoneCtrl = TextEditingController(text: ord.customerPhone ?? '');
    _docOrCarCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _payAmountCtrl = TextEditingController(
      text: ord.debt > 0 ? ord.debt.round().toString() : '0',
    );
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      final repos = context.read<AppRepositories>();
      final users = await repos.users.list();
      if (mounted) {
        setState(() {
          _drivers = users.where((u) => u.role == Role.haydovchi && u.isActive).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _docOrCarCtrl.dispose();
    _noteCtrl.dispose();
    _payAmountCtrl.dispose();
    super.dispose();
  }

  void _onReceiverTypeChanged(String type) {
    setState(() {
      _receiverType = type;
      if (type == 'customer') {
        _nameCtrl.text = widget.order.customerName ?? '';
        _phoneCtrl.text = widget.order.customerPhone ?? '';
        _deliveryType = 'pickup';
      } else if (type == 'driver') {
        _deliveryType = 'delivery';
        if (_drivers.isNotEmpty) {
          _nameCtrl.text = _drivers.first.fullName;
          _phoneCtrl.text = '';
        } else {
          _nameCtrl.text = 'Haydovchi';
        }
      } else if (type == 'agent') {
        _deliveryType = 'pickup';
        _nameCtrl.text = '';
        _phoneCtrl.text = '';
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repos = context.read<AppRepositories>();
      double? payAmount;
      if (widget.order.debt > 0.005 && _payDebtNow) {
        payAmount = double.tryParse(_payAmountCtrl.text.replaceAll(' ', '')) ?? 0.0;
      }

      final updated = await repos.sales.fulfillOrder(
        widget.order.id,
        receivedByName: _nameCtrl.text.trim(),
        receivedByPhone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        deliveryType: _deliveryType,
        receiverDocOrCar: _docOrCarCtrl.text.trim().isEmpty ? null : _docOrCarCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        payAmount: payAmount,
        payMethod: _payMethod,
      );

      if (mounted) {
        Navigator.pop(context, updated);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ord = widget.order;
    final hasDebt = ord.debt > 0.005;

    return AlertDialog(
      backgroundColor: context.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.task_alt_rounded, color: Color(0xFF10B981), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Buyurtmani topshirish',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                Text(
                  'Buyurtma #${ord.id} • Jami: ${money(ord.total)}',
                  style: TextStyle(fontSize: 12, color: context.subtextColor, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)))),
                      ],
                    ),
                  ),
                ],

                // 1. Mijoz va tovarlar qisqa ma'lumoti
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.isDark ? AppColors.darkCard : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.borderColor.withOpacity(0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person_outline_rounded, size: 15, color: context.subtextColor),
                              const SizedBox(width: 6),
                              Text(
                                ord.customerName ?? 'Noma‘lum mijoz',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.inkColor),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${ord.items.length} xil tovar',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF3B82F6)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ord.items.map((i) => '${i.productName} (${i.quantity.toStringAsFixed(1)})').join(', '),
                        style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Kim qabul qilib oldi? (Tezkor tanlov chiplari)
                Text(
                  'Kim qabul qilib olmoqda?',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.inkColor),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildPresetChip('👤 Mijozning o‘zi', 'customer'),
                    _buildPresetChip('🚚 Haydovchi', 'driver'),
                    _buildPresetChip('🤝 Ishonchli vakili', 'agent'),
                  ],
                ),
                const SizedBox(height: 12),

                // Agar haydovchi tanlansa va tizimda haydovchilar bo'lsa - tezkor tanlash
                if (_receiverType == 'driver' && _drivers.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.drive_eta_rounded, size: 16, color: Color(0xFF0284C7)),
                        const SizedBox(width: 8),
                        const Text('Tizimdagi haydovchilar: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _drivers.map((drv) {
                                final isSel = _nameCtrl.text == drv.fullName;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ActionChip(
                                    avatar: Icon(
                                      drv.isOnShift ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                                      size: 13,
                                      color: drv.isOnShift ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    ),
                                    label: Text(
                                      drv.isOnShift ? drv.fullName : '${drv.fullName} (Dam olmoqda)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                                        color: drv.isOnShift ? null : Colors.grey,
                                      ),
                                    ),
                                    backgroundColor: isSel ? const Color(0xFF0284C7).withOpacity(0.2) : Colors.transparent,
                                    side: BorderSide(color: isSel ? const Color(0xFF0284C7) : context.borderColor),
                                    onPressed: () {
                                      setState(() {
                                        _nameCtrl.text = drv.fullName;
                                      });
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Qabul qiluvchi F.I.SH.
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Qabul qiluvchi F.I.SH. *',
                    hintText: 'Masalan: Alisher Valiyev',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                    filled: true,
                    fillColor: context.cardColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: context.borderColor)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Qabul qiluvchi ismini kiriting' : null,
                ),
                const SizedBox(height: 10),

                // Qabul qiluvchi telefoni va mashina/hujjat
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        decoration: InputDecoration(
                          labelText: 'Telefon raqami',
                          hintText: '+998 90 123 45 67',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                          filled: true,
                          fillColor: context.cardColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: context.borderColor)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _docOrCarCtrl,
                        decoration: InputDecoration(
                          labelText: _receiverType == 'driver' ? 'Mashina raqami' : 'Hujjat / Pasport',
                          hintText: _receiverType == 'driver' ? '01 A 777 AA' : 'AA 1234567',
                          prefixIcon: Icon(
                            _receiverType == 'driver' ? Icons.local_shipping_outlined : Icons.assignment_ind_outlined,
                            size: 18,
                          ),
                          filled: true,
                          fillColor: context.cardColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: context.borderColor)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3. Topshirish usuli
                Text(
                  'Topshirish usuli:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.inkColor),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildDeliveryTypeOption(
                        title: 'Ombordan olib ketish',
                        subtitle: 'Mijoz yoki vakil o‘zi keldi',
                        icon: Icons.storefront_rounded,
                        value: 'pickup',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDeliveryTypeOption(
                        title: 'Mashinada yetkazish',
                        subtitle: 'Haydovchi orqali yuborildi',
                        icon: Icons.local_shipping_rounded,
                        value: 'delivery',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 4. Qoldiq to'lov bo'lsa (Nasiya / To'lov)
                if (hasDebt) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_balance_wallet_outlined, size: 16, color: Color(0xFFEF4444)),
                                const SizedBox(width: 6),
                                Text(
                                  'Qoldiq to‘lov: ${money(ord.debt)}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFEF4444)),
                                ),
                              ],
                            ),
                            Switch.adaptive(
                              value: _payDebtNow,
                              activeColor: const Color(0xFF10B981),
                              onChanged: (v) => setState(() => _payDebtNow = v),
                            ),
                          ],
                        ),
                        Text(
                          _payDebtNow
                              ? 'Mijoz qoldiq to‘lovni topshirish vaqtida to‘lamoqda:'
                              : 'To‘lanmagan qoldiq mijoz hisobida qarz (nasiya) sifatida saqlanadi.',
                          style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                        ),
                        if (_payDebtNow) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _payAmountCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'To‘lanayotgan summa',
                                    filled: true,
                                    fillColor: context.cardColor,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: _payMethod,
                                  decoration: InputDecoration(
                                    labelText: 'Usul',
                                    filled: true,
                                    fillColor: context.cardColor,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'cash', child: Text('Naqd', style: TextStyle(fontSize: 12.5))),
                                    DropdownMenuItem(value: 'card', child: Text('Karta', style: TextStyle(fontSize: 12.5))),
                                    DropdownMenuItem(value: 'transfer', child: Text('O‘tkazma', style: TextStyle(fontSize: 12.5))),
                                  ],
                                  onChanged: (v) => setState(() => _payMethod = v ?? 'cash'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // 5. Topshirish izohi
                Text(
                  'Topshirish izohi / Dalolatnoma eslatmasi:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.inkColor),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildNotePresetChip('Tovarlar to‘liq topshirildi'),
                    _buildNotePresetChip('Ko‘rib tekshirib olindi'),
                    _buildNotePresetChip('Sifatiga e\'tiroz yo‘q'),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'Qo‘shimcha izoh yoki haydovchi/mijoz fikri (ixtiyoriy)',
                    prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                    filled: true,
                    fillColor: context.cardColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: context.borderColor)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Bekor qilish'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(
            _busy ? 'Topshirilmoqda...' : 'Topshirish va Tasdiqlash',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, String type) {
    final isSel = _receiverType == type;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSel ? FontWeight.w800 : FontWeight.w600)),
      selected: isSel,
      selectedColor: const Color(0xFF10B981).withOpacity(0.18),
      side: BorderSide(color: isSel ? const Color(0xFF10B981) : context.borderColor),
      onSelected: (_) => _onReceiverTypeChanged(type),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildNotePresetChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 11)),
      backgroundColor: context.borderColor.withOpacity(0.3),
      side: BorderSide.none,
      onPressed: () {
        setState(() {
          if (_noteCtrl.text.isEmpty) {
            _noteCtrl.text = text;
          } else if (!_noteCtrl.text.contains(text)) {
            _noteCtrl.text = '${_noteCtrl.text}, $text';
          }
        });
      },
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDeliveryTypeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
  }) {
    final isSel = _deliveryType == value;
    final color = isSel ? const Color(0xFF10B981) : context.subtextColor;
    return InkWell(
      onTap: () => setState(() => _deliveryType = value),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF10B981).withOpacity(0.08) : context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSel ? const Color(0xFF10B981) : context.borderColor,
            width: isSel ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                      color: isSel ? context.inkColor : context.subtextColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: context.subtextColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
