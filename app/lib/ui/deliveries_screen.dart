import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key, this.currentUser});
  final AppUser? currentUser;

  @override
  State<DeliveriesScreen> createState() => DeliveriesScreenState();
}

class DeliveriesScreenState extends State<DeliveriesScreen> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all'; // 'all', 'open_pool', 'on_the_way', 'loading', 'delivered', 'cancelled'
  List<Delivery> _deliveries = [];
  bool _loading = true;
  String? _error;
  late bool _isOnShift;

  bool get isDriver => widget.currentUser?.role == Role.haydovchi;

  @override
  void initState() {
    super.initState();
    _isOnShift = widget.currentUser?.isOnShift ?? true;
    _loadDeliveries();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isTogglingShift = false;

  Future<void> _toggleShift(bool val) async {
    if (_isTogglingShift) return;
    _isTogglingShift = true;
    final prev = _isOnShift;
    setState(() => _isOnShift = val);
    try {
      final repos = context.read<AppRepositories>();
      final uid = widget.currentUser?.id;
      if (uid == null) {
        throw Exception('Foydalanuvchi aniqlanmadi');
      }
      await repos.users.toggleShift(uid, val);
      if (mounted) {
        showMessage(
          context,
          val ? '🟢 Smena ochildi! Buyurtmalarni qabul qilishingiz mumkin.' : '🔴 Smena yopildi. Dam olish rejimi.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOnShift = prev);
        showMessage(context, 'Xatolik: $e', error: true);
      }
    } finally {
      _isTogglingShift = false;
    }
  }

  Future<void> _loadDeliveries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repos = context.read<AppRepositories>();
      final list = await repos.deliveries.list();
      if (!mounted) return;
      // Agar haydovchi bo'lsa: unga biriktirilgan va barchaga ochiq buyurtmalar ko'rinadi
      final resultList = isDriver
          ? list.where((d) =>
              (widget.currentUser != null && d.driverId == widget.currentUser!.id) ||
              d.driverName.toLowerCase().contains(widget.currentUser!.fullName.toLowerCase()) ||
              (d.driverPhone != null && d.driverPhone == widget.currentUser!.username) ||
              d.driverId == null ||
              d.driverName.toLowerCase().contains('ochiq')).toList()
          : list;
      setState(() {
        _deliveries = resultList;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Delivery> get _filteredDeliveries {
    var list = _deliveries;
    if (_statusFilter == 'open_pool') {
      list = list.where((d) => (d.driverId == null || d.driverName.toLowerCase().contains('ochiq')) && d.status == 'loading').toList();
    } else if (_statusFilter != 'all') {
      list = list.where((d) => d.status == _statusFilter).toList();
    }
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) {
        return d.vehicleNumber.toLowerCase().contains(q) ||
            d.driverName.toLowerCase().contains(q) ||
            (d.driverPhone ?? '').toLowerCase().contains(q) ||
            d.recipientName.toLowerCase().contains(q) ||
            (d.recipientPhone ?? '').toLowerCase().contains(q) ||
            (d.destinationAddress ?? '').toLowerCase().contains(q) ||
            d.items.any((i) => i.productName.toLowerCase().contains(q));
      }).toList();
    }
    return list;
  }

  Future<void> openNewDeliveryDialog({
    int? saleId,
    String? recipientName,
    String? recipientPhone,
    String? address,
    List<DeliveryItem>? initialItems,
  }) async {
    final repos = context.read<AppRepositories>();
    final created = await showDialog<Delivery>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DeliveryEditDialog(
        saleId: saleId,
        initialRecipientName: recipientName,
        initialRecipientPhone: recipientPhone,
        initialAddress: address,
        initialItems: initialItems,
      ),
    );
    if (created != null && mounted) {
      try {
        final saved = await repos.deliveries.create(created);
        showMessage(context, '✓ Yetkazib berish ro‘yxatga qo‘shildi: ${saved.vehicleNumber}');
        _loadDeliveries();
      } catch (e) {
        showMessage(context, 'Xatolik: $e', error: true);
      }
    }
  }

  Future<void> _editDelivery(Delivery delivery) async {
    final repos = context.read<AppRepositories>();
    final updated = await showDialog<Delivery>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DeliveryEditDialog(delivery: delivery),
    );
    if (updated != null && mounted) {
      try {
        await repos.deliveries.update(updated);
        showMessage(context, '✓ Yetkazib berish ma’lumotlari yangilandi');
        _loadDeliveries();
      } catch (e) {
        showMessage(context, 'Xatolik: $e', error: true);
      }
    }
  }

  Future<void> _acceptDelivery(Delivery delivery) async {
    if (isDriver && !_isOnShift) {
      showMessage(context, 'Buyurtma olishdan oldin smenani oching! (Smena ochiq bo‘lishi kerak)', error: true);
      return;
    }
    final repos = context.read<AppRepositories>();
    try {
      await repos.deliveries.accept(delivery.id);
      if (mounted) {
        showMessage(context, '✓ Buyurtma qabul qilindi va yo‘lga chiqildi! Mijoz ma’lumotlari ochildi.');
        _loadDeliveries();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Xatolik: $e', error: true);
    }
  }

  Future<void> _rejectDelivery(Delivery delivery) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('Buyurtmani rad etish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          'Haqiqatan ham "${delivery.vehicleNumber}" buyurtmasini qabul qilmoqchi emasmisiz?\n\nBuyurtma umumiy ochiq bo‘limga qaytariladi va boshqa haydovchilar olishi mumkin bo‘ladi.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            ),
            child: const Text('Qabul qilmayman'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final repos = context.read<AppRepositories>();
    try {
      await repos.deliveries.reject(delivery.id);
      if (mounted) {
        showMessage(context, '✓ Buyurtma rad etildi va barcha haydovchilar uchun ochiq qilib qaytarildi.');
        _loadDeliveries();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Xatolik: $e', error: true);
    }
  }

  Future<void> _changeStatus(Delivery delivery, String newStatus) async {
    final repos = context.read<AppRepositories>();
    try {
      await repos.deliveries.updateStatus(delivery.id, newStatus);
      String statusTitle = 'holati yangilandi';
      if (newStatus == 'on_the_way') {
        statusTitle = isDriver
            ? 'qabul qilindi va yo‘lga chiqildi. Mijoz ma’lumotlari ochildi!'
            : 'yo‘lga chiqdi';
      }
      if (newStatus == 'delivered') {
        statusTitle = isDriver
            ? 'yetkazildi va mijozga topshirildi! Reys haqi hisobingizga qo‘shildi.'
            : 'yetkazildi deb belgilandi';
      }
      if (newStatus == 'cancelled') statusTitle = 'bekor qilindi';
      showMessage(context, '✓ ${delivery.vehicleNumber} $statusTitle');
      _loadDeliveries();
    } catch (e) {
      showMessage(context, 'Xatolik: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDeliveries;
    final totalCount = _deliveries.length;
    final openPoolCount = _deliveries.where((d) => (d.driverId == null || d.driverName.toLowerCase().contains('ochiq')) && d.status == 'loading').length;
    final onTheWayCount = _deliveries.where((d) => d.status == 'on_the_way').length;
    final loadingCount = _deliveries.where((d) => d.status == 'loading').length;
    final deliveredCount = _deliveries.where((d) => d.status == 'delivered').length;
    final cancelledCount = _deliveries.where((d) => d.status == 'cancelled').length;
    final earnedFee = _deliveries
        .where((d) => d.status == 'delivered')
        .fold(0.0, (sum, d) => sum + d.deliveryFee);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadDeliveries,
        color: AppColors.neonLime,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Haydovchi uchun xush kelibsiz profili va smena statusi
            if (isDriver) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: context.isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.local_shipping_rounded, color: Color(0xFF2563EB), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                widget.currentUser?.fullName ?? 'Haydovchi',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: context.inkColor),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: const Text(
                                  'Haydovchi',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _isOnShift
                                ? '🟢 Smena ochiq — Siz yangi buyurtmalarni qabul qilishingiz va yo‘lga chiqishingiz mumkin.'
                                : '🔴 Smena yopiq (Dam olmoqda) — Buyurtma olishdan oldin smenani yoqing.',
                            style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Smena ochish / yopish switch
                    InkWell(
                      onTap: () => _toggleShift(!_isOnShift),
                      borderRadius: BorderRadius.circular(100),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isOnShift
                              ? const Color(0xFF10B981).withOpacity(0.15)
                              : const Color(0xFFEF4444).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: _isOnShift ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            width: 1.3,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isOnShift ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                              size: 14,
                              color: _isOnShift ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isOnShift ? 'Smena ochiq' : 'Smena yopiq',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: _isOnShift ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IgnorePointer(
                              child: SizedBox(
                                height: 18,
                                width: 30,
                                child: Transform.scale(
                                  scale: 0.7,
                                  child: Switch.adaptive(
                                    value: _isOnShift,
                                    activeColor: const Color(0xFF10B981),
                                    onChanged: (_) {},
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Qayta yuklash',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _loadDeliveries,
                    ),
                  ],
                ),
              ),
            ],

            // 1. KPI kartochkalari
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 640;
                final cardWidth = isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _DeliveryKpiCard(
                      title: isDriver ? 'Mening topshiriqlarim' : 'Jami Qatnovlar',
                      value: '$totalCount ta',
                      icon: Icons.local_shipping_rounded,
                      color: const Color(0xFF3B82F6),
                      width: cardWidth,
                    ),
                    _DeliveryKpiCard(
                      title: isDriver ? 'Qabul qilish kerak' : 'Yuklanmoqda',
                      value: '$loadingCount ta',
                      icon: Icons.hourglass_top_rounded,
                      color: const Color(0xFFF59E0B),
                      width: cardWidth,
                    ),
                    _DeliveryKpiCard(
                      title: 'Yo‘lda',
                      value: '$onTheWayCount ta',
                      icon: Icons.near_me_rounded,
                      color: const Color(0xFF0284C7),
                      width: cardWidth,
                    ),
                    _DeliveryKpiCard(
                      title: isDriver ? 'Ishlab topilgan haq' : 'Yetkazilgan',
                      value: isDriver ? money(earnedFee) : '$deliveredCount ta',
                      icon: isDriver ? Icons.payments_rounded : Icons.check_circle_rounded,
                      color: const Color(0xFF10B981),
                      width: cardWidth,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // 2. Qidiruv, Filterlar va Yangi yetkazish tugmasi
            LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth > 880;

                final searchField = SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Mashina raqami, haydovchi, mijoz, manzil yoki tovar...',
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
                          ('Barchasi', 'all', totalCount, null),
                          if (openPoolCount > 0)
                            ('Barchaga ochiq', 'open_pool', openPoolCount, const Color(0xFF8B5CF6)),
                          if (isDriver) ...[
                            ('Qabul qilish kerak', 'loading', loadingCount, const Color(0xFFF59E0B)),
                            ('Yo‘lda', 'on_the_way', onTheWayCount, const Color(0xFF0284C7)),
                            ('Yetkazildi', 'delivered', deliveredCount, const Color(0xFF10B981)),
                          ] else ...[
                            ('Yo‘lda', 'on_the_way', onTheWayCount, const Color(0xFF0284C7)),
                            ('Yuklanmoqda', 'loading', loadingCount, const Color(0xFFF59E0B)),
                            ('Yetkazildi', 'delivered', deliveredCount, const Color(0xFF10B981)),
                          ],
                          ('Bekor qilingan', 'cancelled', cancelledCount, const Color(0xFFEF4444)),
                        ])
                          _buildFilterSegment(
                            label: item.$1,
                            code: item.$2,
                            count: item.$3,
                            dotColor: item.$4,
                            isSelected: _statusFilter == item.$2,
                            onTap: () => setState(() => _statusFilter = item.$2),
                          ),
                      ],
                    ),
                  ),
                );

                final actionButton = isDriver
                    ? FilledButton.icon(
                        onPressed: _loadDeliveries,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Yangilash', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                          foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: () => openNewDeliveryDialog(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Yangi Yetkazish', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                          foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        ),
                      );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 10),
                      filterCapsule,
                      const SizedBox(width: 10),
                      actionButton,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 8),
                        actionButton,
                      ],
                    ),
                    const SizedBox(height: 10),
                    filterCapsule,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // 3. Yetkazib berish kartochkalari ro'yxati
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
                      FilledButton(onPressed: _loadDeliveries, child: const Text('Qayta urinish')),
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
                    Icon(Icons.local_shipping_outlined, size: 54, color: context.subtextColor.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    Text(
                      isDriver ? 'Sizga biriktirilgan yetkazmalar yo‘q' : 'Yetkazib berish yozuvlari topilmadi',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.inkColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isDriver
                          ? 'Admin yoki kassir sizga yangi buyurtma biriktirganda bu yerda ko‘rinadi. Qayta tekshirish uchun yangilang.'
                          : 'Yangi yetkazib berish reysini qo‘shish yoki buyurtmalarni mashinaga yuklash orqali qatnovlarni boshqaring.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: context.subtextColor),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: isDriver ? _loadDeliveries : () => openNewDeliveryDialog(),
                      icon: Icon(isDriver ? Icons.refresh_rounded : Icons.add_rounded, size: 18),
                      label: Text(isDriver ? 'Qayta tekshirish' : '+ Yangi Yetkazish'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final delivery in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DeliveryCard(
                    delivery: delivery,
                    isDriver: isDriver,
                    isOnShift: _isOnShift,
                    onStatusChange: (status) => _changeStatus(delivery, status),
                    onAccept: () => _acceptDelivery(delivery),
                    onReject: () => _rejectDelivery(delivery),
                    onEdit: () => _editDelivery(delivery),
                    onWaybill: () => DeliveryWaybillDialog.show(context, delivery),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSegment({
    required String label,
    required String code,
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
}

class _DeliveryKpiCard extends StatelessWidget {
  const _DeliveryKpiCard({
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

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.delivery,
    this.isDriver = false,
    this.isOnShift = true,
    required this.onStatusChange,
    this.onAccept,
    this.onReject,
    required this.onEdit,
    required this.onWaybill,
  });

  final Delivery delivery;
  final bool isDriver;
  final bool isOnShift;
  final void Function(String status) onStatusChange;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback onEdit;
  final VoidCallback onWaybill;

  bool get isOpenPool =>
      (delivery.driverId == null || delivery.driverName.toLowerCase().contains('ochiq')) &&
      delivery.isLoading;

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (delivery.status) {
      case 'on_the_way':
        statusColor = const Color(0xFF0284C7);
        statusText = 'Yo‘lda';
        statusIcon = Icons.near_me_rounded;
        break;
      case 'delivered':
        statusColor = const Color(0xFF10B981);
        statusText = 'Yetkazildi';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'cancelled':
        statusColor = const Color(0xFFEF4444);
        statusText = 'Bekor qilingan';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusText = isDriver ? 'Yangi topshiriq (Kutilmoqda)' : 'Yuklanmoqda';
        statusIcon = Icons.hourglass_top_rounded;
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
          // 1. Header (Mashina raqami, Haydovchi, Holat)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                // Avtomobil Davlat Raqami (Uzbekistan Car Plate Badge)
                _buildCarPlate(context, delivery.vehicleNumber),
                const SizedBox(width: 10),

                // Mashina modeli kapsulasi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.isDark ? AppColors.darkCard : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: context.borderColor.withOpacity(0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_shipping_rounded, size: 12, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 4),
                      Text(
                        delivery.vehicleModel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.inkColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Holat kapsulasi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: statusColor.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOpenPool) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.35)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.public_rounded, size: 11, color: Color(0xFF8B5CF6)),
                        SizedBox(width: 4),
                        Text(
                          'Barchaga ochiq',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8B5CF6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),

                // Sana va vaqt
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: context.subtextColor),
                    const SizedBox(width: 4),
                    Text(
                      formatDateTime(delivery.createdAt),
                      style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Haydovchi va Mijoz ma'lumotlari
          if (isDriver && delivery.isLoading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF262014) : const Color(0xFFFEF3C7).withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_rounded, size: 20, color: Color(0xFFD97706)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mijoz ma’lumotlari va manzil kutilmoqda',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Color(0xFFB45309),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Buyurtmani qabul qilganingizdan so‘ng mijoz ismi, telefon raqami va aniq yetkazib berish manzili to‘liq ochiladi.',
                            style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        if (!isDriver) ...[
                          // Haydovchi (faqat admin/kassirga)
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6).withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.person_rounded, size: 15, color: Color(0xFF3B82F6)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Haydovchi: ${delivery.driverName}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                          color: context.inkColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (delivery.driverPhone != null && delivery.driverPhone!.isNotEmpty)
                                        Text(
                                          delivery.driverPhone!,
                                          style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 28, color: context.borderColor.withOpacity(0.6)),
                          const SizedBox(width: 12),
                        ],
                        // Qabul qiluvchi mijoz
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.location_on_rounded, size: 15, color: Color(0xFF10B981)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Mijoz: ${delivery.recipientName}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                        color: context.inkColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      delivery.destinationAddress ?? (delivery.recipientPhone ?? 'Manzil ko‘rsatilmagan'),
                                      style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (isDriver && (delivery.isOnTheWay || delivery.isDelivered)) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (delivery.recipientPhone != null && delivery.recipientPhone!.isNotEmpty)
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: delivery.recipientPhone!));
                                showMessage(context, 'Mijoz telefon raqami nusxalandi: ${delivery.recipientPhone}');
                              },
                              borderRadius: BorderRadius.circular(100),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.phone_in_talk_rounded, size: 13, color: Color(0xFF10B981)),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Tel: ${delivery.recipientPhone}',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.copy_rounded, size: 11, color: Color(0xFF059669)),
                                  ],
                                ),
                              ),
                            ),
                          if (delivery.destinationAddress != null && delivery.destinationAddress!.isNotEmpty) ...[
                            InkWell(
                              onTap: () {
                                final addr = delivery.destinationAddress!;
                                final mapUrl = 'https://yandex.uz/maps/?text=${Uri.encodeComponent(addr)}';
                                Clipboard.setData(ClipboardData(text: mapUrl));
                                try {
                                  if (Platform.isWindows) {
                                    Process.run('cmd', ['/c', 'start', '""', mapUrl], runInShell: true);
                                  }
                                } catch (_) {}
                                showMessage(context, '🗺️ Xarita havolasi ochilmoqda: $addr');
                              },
                              borderRadius: BorderRadius.circular(100),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(color: const Color(0xFF059669).withOpacity(0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.map_rounded, size: 13, color: Color(0xFF059669)),
                                    SizedBox(width: 5),
                                    Text(
                                      'Xaritada ochish',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: delivery.destinationAddress!));
                                showMessage(context, 'Yetkazish manzili nusxalandi: ${delivery.destinationAddress}');
                              },
                              borderRadius: BorderRadius.circular(100),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.directions_rounded, size: 13, color: Color(0xFF0284C7)),
                                    SizedBox(width: 5),
                                    Text(
                                      'Manzilni nusxalash',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0284C7)),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(Icons.copy_rounded, size: 11, color: Color(0xFF0284C7)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (delivery.note != null && delivery.note!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Divider(height: 10, thickness: 0.5, color: context.borderColor.withOpacity(0.4)),
                      Row(
                        children: [
                          const Icon(Icons.notes_rounded, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Izoh: ${delivery.note}',
                              style: TextStyle(fontSize: 11.5, color: context.inkColor, fontStyle: FontStyle.italic),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),

          // 3. Olib ketilayotgan mahsulotlar (agar mavjud bo'lsa)
          if (delivery.items.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF181D24) : const Color(0xFFF1F5F9).withOpacity(0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text(
                        'Yuklangan mahsulotlar (${delivery.items.length} xil):',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.subtextColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (int i = 0; i < delivery.items.length; i++) ...[
                    if (i > 0)
                      Divider(height: 10, thickness: 0.5, color: context.borderColor.withOpacity(0.4)),
                    Row(
                      children: [
                        Text(
                          '${i + 1}.',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.subtextColor),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            delivery.items[i].productName,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: context.inkColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.isDark ? AppColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: context.borderColor.withOpacity(0.6)),
                          ),
                          child: Text(
                            '${delivery.items[i].quantity} ${delivery.items[i].unit}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: context.isDark ? AppColors.neonLime : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 4. Yo'l haqi va Yetkazish vaqtlari
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Yo'l haqi kapsulasi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.payments_outlined, size: 13, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 5),
                      Text(
                        'Yo‘l haqi: ${money(delivery.deliveryFee)} (${delivery.feePayerLabel})',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (delivery.dispatchTime != null) ...[
                  Text(
                    'Jo‘nadi: ${formatDateTime(delivery.dispatchTime!)}',
                    style: TextStyle(fontSize: 11, color: context.subtextColor),
                  ),
                ],
                if (delivery.deliveredTime != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Yetdi: ${formatDateTime(delivery.deliveredTime!)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: context.borderColor.withOpacity(0.6)),

          // 5. Harakat tugmalari (Burchaksiz kapsulalar)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (isDriver) ...[
                  if (delivery.isLoading) ...[
                    if (isOpenPool) ...[
                      // Barchaga ochiq buyurtmani olish
                      FilledButton.icon(
                        onPressed: onAccept,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text(
                          'Olish va Qabul qilish',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        ),
                      ),
                    ] else ...[
                      // Haydovchiga biriktirilgan buyurtma: rad etish yoki qabul qilish
                      OutlinedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFEF4444)),
                        label: const Text(
                          'Qabul qilmayman',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFEF4444)),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.4)),
                          backgroundColor: const Color(0xFFEF4444).withOpacity(0.06),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: onAccept ?? () => onStatusChange('on_the_way'),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                        label: const Text(
                          'Buyurtmani qabul qilish',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        ),
                      ),
                    ],
                  ] else if (delivery.isOnTheWay) ...[
                    // Yo'l varaqasi
                    OutlinedButton.icon(
                      onPressed: onWaybill,
                      icon: const Icon(Icons.receipt_long_rounded, size: 15),
                      label: const Text('Yo‘l varaqasi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.inkColor,
                        side: BorderSide(color: context.borderColor),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    // Yetkaza olmadim
                    OutlinedButton.icon(
                      onPressed: () => onStatusChange('cancelled'),
                      icon: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFEF4444)),
                      label: const Text('Yetkaza olmadim', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.4)),
                        backgroundColor: const Color(0xFFEF4444).withOpacity(0.05),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    // Yetkazildi (Mijozga topshirdim)
                    FilledButton.icon(
                      onPressed: () => onStatusChange('delivered'),
                      icon: const Icon(Icons.task_alt_rounded, size: 16),
                      label: const Text(
                        'Yetkazildi (Mijozga topshirdim)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      ),
                    ),
                  ] else ...[
                    // Topshirilgan
                    OutlinedButton.icon(
                      onPressed: onWaybill,
                      icon: const Icon(Icons.receipt_long_rounded, size: 15),
                      label: const Text('Yo‘l varaqasi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.inkColor,
                        side: BorderSide(color: context.borderColor),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                          SizedBox(width: 5),
                          Text(
                            'Muvaffaqiyatli topshirilgan',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // Admin / Kassir ko'rinishi
                  OutlinedButton.icon(
                    onPressed: onWaybill,
                    icon: const Icon(Icons.receipt_long_rounded, size: 15),
                    label: const Text('Yo‘l varaqasi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.inkColor,
                      side: BorderSide(color: context.borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Tahrirlash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.inkColor,
                      side: BorderSide(color: context.borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  if (delivery.isLoading) ...[
                    OutlinedButton.icon(
                      onPressed: () => onStatusChange('cancelled'),
                      icon: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFEF4444)),
                      label: const Text('Bekor qilish', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.4)),
                        backgroundColor: const Color(0xFFEF4444).withOpacity(0.05),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => onStatusChange('on_the_way'),
                      icon: const Icon(Icons.local_shipping_rounded, size: 15),
                      label: const Text('Yo‘lga chiqdi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ] else if (delivery.isOnTheWay) ...[
                    FilledButton.icon(
                      onPressed: () => onStatusChange('delivered'),
                      icon: const Icon(Icons.check_circle_rounded, size: 15),
                      label: const Text('Yetkazildi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarPlate(BuildContext context, String plate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: context.isDark ? const Color(0xFF64748B) : const Color(0xFF0F172A),
          width: 1.4,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'UZ',
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Color(0xFF0284C7)),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            plate,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: context.inkColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Yangi yetkazish yaratish yoki tahrirlash dialogi
class DeliveryEditDialog extends StatefulWidget {
  const DeliveryEditDialog({
    super.key,
    this.delivery,
    this.saleId,
    this.initialRecipientName,
    this.initialRecipientPhone,
    this.initialAddress,
    this.initialItems,
  });

  final Delivery? delivery;
  final int? saleId;
  final String? initialRecipientName;
  final String? initialRecipientPhone;
  final String? initialAddress;
  final List<DeliveryItem>? initialItems;

  @override
  State<DeliveryEditDialog> createState() => _DeliveryEditDialogState();
}

class _DeliveryEditDialogState extends State<DeliveryEditDialog> {
  final _formKey = GlobalKey<FormState>();

  int? _driverId;
  List<AppUser> _systemDrivers = [];

  late TextEditingController _vehicleNumberCtrl;
  late TextEditingController _driverNameCtrl;
  late TextEditingController _driverPhoneCtrl;
  late TextEditingController _recipientNameCtrl;
  late TextEditingController _recipientPhoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _deliveryFeeCtrl;
  late TextEditingController _noteCtrl;

  String _vehicleModel = 'Labo';
  String _feePayer = 'customer';
  String _status = 'loading';

  List<({String name, double quantity, String unit})> _items = [];

  final _prodNameCtrl = TextEditingController();
  final _prodQtyCtrl = TextEditingController(text: '1.0');
  String _prodUnit = 'dona';

  @override
  void initState() {
    super.initState();
    final d = widget.delivery;
    _driverId = d?.driverId;
    _vehicleNumberCtrl = TextEditingController(text: d?.vehicleNumber ?? '');
    _vehicleModel = d?.vehicleModel ?? 'Labo';
    _driverNameCtrl = TextEditingController(text: d?.driverName ?? '');
    _driverPhoneCtrl = TextEditingController(text: d?.driverPhone ?? '');
    _recipientNameCtrl = TextEditingController(text: d?.recipientName ?? widget.initialRecipientName ?? '');
    _recipientPhoneCtrl = TextEditingController(text: d?.recipientPhone ?? widget.initialRecipientPhone ?? '');
    _addressCtrl = TextEditingController(text: d?.destinationAddress ?? widget.initialAddress ?? '');
    _deliveryFeeCtrl = TextEditingController(text: d != null ? d.deliveryFee.toInt().toString() : '0');
    _feePayer = d?.feePayer ?? 'customer';
    _status = d?.status ?? 'loading';
    _noteCtrl = TextEditingController(text: d?.note ?? '');

    if (d != null) {
      _items = d.items.map((i) => (name: i.productName, quantity: i.quantity, unit: i.unit)).toList();
    } else if (widget.initialItems != null) {
      _items = widget.initialItems!.map((i) => (name: i.productName, quantity: i.quantity, unit: i.unit)).toList();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      final repos = context.read<AppRepositories>();
      final users = await repos.users.list();
      if (mounted) {
        setState(() {
          _systemDrivers = users.where((u) => u.role == Role.haydovchi && u.isActive).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _vehicleNumberCtrl.dispose();
    _driverNameCtrl.dispose();
    _driverPhoneCtrl.dispose();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _deliveryFeeCtrl.dispose();
    _noteCtrl.dispose();
    _prodNameCtrl.dispose();
    _prodQtyCtrl.dispose();
    super.dispose();
  }

  void _addItem() {
    final name = _prodNameCtrl.text.trim();
    final qty = double.tryParse(_prodQtyCtrl.text.trim()) ?? 0;
    if (name.isEmpty || qty <= 0) {
      showMessage(context, 'Tovar nomi va miqdorini to‘g‘ri kiriting', error: true);
      return;
    }
    setState(() {
      _items.add((name: name, quantity: qty, unit: _prodUnit));
      _prodNameCtrl.clear();
      _prodQtyCtrl.text = '1.0';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.delivery != null;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.cardBg,
      child: Container(
        width: isMobile ? double.infinity : 620,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
        padding: EdgeInsets.all(isMobile ? 16 : 22),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dialog sarlavhasi
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_shipping_rounded, color: Color(0xFF3B82F6), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEdit ? 'Yetkazib berishni tahrirlash' : 'Yangi Yetkazib berish (Mashinaga yuklash)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.inkColor),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 18),

              // Form maydonlari (Scrollable)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Mashina ma'lumotlari
                    Text('Avtotransport ma’lumotlari', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.subtextColor)),
                    const SizedBox(height: 8),
                    if (isMobile) ...[
                      TextFormField(
                        controller: _vehicleNumberCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Mashina raqami *',
                          hintText: '01 A 777 AA',
                          prefixIcon: Icon(Icons.pin_rounded, size: 18),
                          isDense: true,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Mashina raqami shart' : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _vehicleModel,
                        decoration: const InputDecoration(labelText: 'Turi', isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'Labo', child: Text('Labo')),
                          DropdownMenuItem(value: 'Gazel', child: Text('Gazel')),
                          DropdownMenuItem(value: 'Isuzu', child: Text('Isuzu')),
                          DropdownMenuItem(value: 'Kamaz', child: Text('Kamaz')),
                          DropdownMenuItem(value: 'Damas', child: Text('Damas')),
                          DropdownMenuItem(value: 'Boshqa', child: Text('Boshqa')),
                        ],
                        onChanged: (v) => setState(() => _vehicleModel = v ?? 'Labo'),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          // Mashina raqami
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _vehicleNumberCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Mashina raqami *',
                                hintText: '01 A 777 AA',
                                prefixIcon: Icon(Icons.pin_rounded, size: 18),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Mashina raqami shart' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Mashina turi
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: _vehicleModel,
                              decoration: const InputDecoration(labelText: 'Turi', isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'Labo', child: Text('Labo')),
                                DropdownMenuItem(value: 'Gazel', child: Text('Gazel')),
                                DropdownMenuItem(value: 'Isuzu', child: Text('Isuzu')),
                                DropdownMenuItem(value: 'Kamaz', child: Text('Kamaz')),
                                DropdownMenuItem(value: 'Damas', child: Text('Damas')),
                                DropdownMenuItem(value: 'Boshqa', child: Text('Boshqa')),
                              ],
                              onChanged: (v) => setState(() => _vehicleModel = v ?? 'Labo'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Tizimdagi haydovchilarni biriktirish
                    if (_systemDrivers.isNotEmpty) ...[
                      Text(
                        'Haydovchini biriktirish:',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.subtextColor),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            // 🌐 Barchaga ochiq (hali tayinlanmagan)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                avatar: const Icon(Icons.public_rounded, size: 14, color: Color(0xFF8B5CF6)),
                                label: const Text('🌐 Barchaga ochiq', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                                selected: _driverId == null && _driverNameCtrl.text.toLowerCase().contains('ochiq'),
                                onSelected: (sel) {
                                  setState(() {
                                    _driverId = null;
                                    _driverNameCtrl.text = 'Ochiq (barchaga)';
                                    _driverPhoneCtrl.clear();
                                  });
                                },
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                              ),
                            ),
                            for (final u in _systemDrivers) ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  avatar: Icon(
                                    u.isOnShift ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                                    size: 14,
                                    color: u.isOnShift ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  ),
                                  label: Text(
                                    u.isOnShift ? u.fullName : '${u.fullName} (Dam olmoqda)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: u.isOnShift ? null : Colors.grey,
                                    ),
                                  ),
                                  selected: _driverId == u.id || _driverNameCtrl.text.trim() == u.fullName,
                                  onSelected: (sel) {
                                    setState(() {
                                      if (sel) {
                                        _driverId = u.id;
                                        _driverNameCtrl.text = u.fullName;
                                        if (u.username.isNotEmpty && !u.username.contains('@')) {
                                          _driverPhoneCtrl.text = u.username;
                                        }
                                        if (!u.isOnShift) {
                                          showMessage(
                                            context,
                                            'Eslatma: ${u.fullName} hozirda dam olmoqda (smenasi yopiq)',
                                          );
                                        }
                                      } else {
                                        _driverId = null;
                                      }
                                    });
                                  },
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Haydovchi
                    if (isMobile) ...[
                      TextFormField(
                        controller: _driverNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Haydovchi ismi *',
                          hintText: 'Farhod Haydovchi',
                          prefixIcon: Icon(Icons.badge_rounded, size: 18),
                          isDense: true,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Haydovchi ismi shart' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _driverPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Haydovchi telefoni',
                          hintText: '+998 90 ...',
                          prefixIcon: Icon(Icons.phone_rounded, size: 18),
                          isDense: true,
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _driverNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Haydovchi ismi *',
                                hintText: 'Farhod Haydovchi',
                                prefixIcon: Icon(Icons.badge_rounded, size: 18),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Haydovchi ismi shart' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _driverPhoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Haydovchi telefoni',
                                hintText: '+998 90 ...',
                                prefixIcon: Icon(Icons.phone_rounded, size: 18),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Qabul qiluvchi mijoz va Manzil
                    Text('Qabul qiluvchi mijoz va Manzil', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.subtextColor)),
                    const SizedBox(height: 8),
                    if (isMobile) ...[
                      TextFormField(
                        controller: _recipientNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mijoz ismi *',
                          hintText: 'Akmal aka',
                          prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                          isDense: true,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Mijoz ismi shart' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _recipientPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mijoz telefoni',
                          hintText: '+998 93 ...',
                          prefixIcon: Icon(Icons.phone_iphone_rounded, size: 18),
                          isDense: true,
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _recipientNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Mijoz ismi *',
                                hintText: 'Akmal aka',
                                prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Mijoz ismi shart' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _recipientPhoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Mijoz telefoni',
                                hintText: '+998 93 ...',
                                prefixIcon: Icon(Icons.phone_iphone_rounded, size: 18),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Yetkazib berish manzili / Lokatsiya',
                        hintText: 'Toshkent sh., Chilonzor 9-mavze, 14-uy',
                        prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Yo‘l haqi va Holat
                    if (isMobile) ...[
                      TextFormField(
                        controller: _deliveryFeeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Yo‘l haqi summasi',
                          suffixText: 'so‘m',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _feePayer,
                        decoration: const InputDecoration(labelText: 'To‘lovchi', isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'customer', child: Text('Mijoz to‘laydi')),
                          DropdownMenuItem(value: 'store', child: Text('Do‘kon hisobidan')),
                          DropdownMenuItem(value: 'included', child: Text('Narx ichida')),
                        ],
                        onChanged: (v) => setState(() => _feePayer = v ?? 'customer'),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _deliveryFeeCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Yo‘l haqi summasi',
                                suffixText: 'so‘m',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _feePayer,
                              decoration: const InputDecoration(labelText: 'To‘lovchi', isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'customer', child: Text('Mijoz to‘laydi')),
                                DropdownMenuItem(value: 'store', child: Text('Do‘kon hisobidan')),
                                DropdownMenuItem(value: 'included', child: Text('Narx ichida')),
                              ],
                              onChanged: (v) => setState(() => _feePayer = v ?? 'customer'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Holat va Izoh
                    if (isMobile) ...[
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(labelText: 'Holat', isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'loading', child: Text('Yuklanmoqda')),
                          DropdownMenuItem(value: 'on_the_way', child: Text('Yo‘lda')),
                          DropdownMenuItem(value: 'delivered', child: Text('Yetkazildi')),
                          DropdownMenuItem(value: 'cancelled', child: Text('Bekor qilingan')),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? 'loading'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Izoh / Qo‘shimcha',
                          hintText: 'Qurilish joyi, topshirish...',
                          isDense: true,
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _status,
                              decoration: const InputDecoration(labelText: 'Holat', isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'loading', child: Text('Yuklanmoqda')),
                                DropdownMenuItem(value: 'on_the_way', child: Text('Yo‘lda')),
                                DropdownMenuItem(value: 'delivered', child: Text('Yetkazildi')),
                                DropdownMenuItem(value: 'cancelled', child: Text('Bekor qilingan')),
                              ],
                              onChanged: (v) => setState(() => _status = v ?? 'loading'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _noteCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Izoh / Qo‘shimcha',
                                hintText: 'Qurilish joyi, topshirish...',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 20),

              // Harakat tugmalari
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Bekor qilish'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                      foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      final fee = double.tryParse(_deliveryFeeCtrl.text.replaceAll(' ', '')) ?? 0;
                      final deliveryItems = _items
                          .map((i) => DeliveryItem(productName: i.name, quantity: i.quantity, unit: i.unit))
                          .toList();

                      final d = Delivery(
                        id: widget.delivery?.id ?? 0,
                        saleId: widget.delivery?.saleId ?? widget.saleId,
                        driverId: _driverId,
                        vehicleNumber: _vehicleNumberCtrl.text.trim().toUpperCase(),
                        vehicleModel: _vehicleModel,
                        driverName: _driverNameCtrl.text.trim(),
                        driverPhone: _driverPhoneCtrl.text.trim().isEmpty ? null : _driverPhoneCtrl.text.trim(),
                        recipientName: _recipientNameCtrl.text.trim(),
                        recipientPhone: _recipientPhoneCtrl.text.trim().isEmpty ? null : _recipientPhoneCtrl.text.trim(),
                        destinationAddress: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
                        deliveryFee: fee,
                        feePayer: _feePayer,
                        status: _status,
                        dispatchTime: widget.delivery?.dispatchTime ?? (_status == 'on_the_way' ? DateTime.now() : null),
                        deliveredTime: widget.delivery?.deliveredTime ?? (_status == 'delivered' ? DateTime.now() : null),
                        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                        createdAt: widget.delivery?.createdAt ?? DateTime.now(),
                        items: deliveryItems,
                      );
                      Navigator.pop(context, d);
                    },
                    child: Text(isEdit ? 'Saqlash' : 'Ro‘yxatga olish', style: const TextStyle(fontWeight: FontWeight.w800)),
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

/// Yo'l varaqasi (Delivery Waybill / Nakladnoy) chop etish va ko'rish dialogi
class DeliveryWaybillDialog extends StatelessWidget {
  const DeliveryWaybillDialog({super.key, required this.delivery});

  final Delivery delivery;

  static Future<void> show(BuildContext context, Delivery delivery) {
    return showDialog(
      context: context,
      builder: (_) => DeliveryWaybillDialog(delivery: delivery),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: 580,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sarlavha va Yopish
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: Color(0xFF0F172A), size: 24),
                const SizedBox(width: 8),
                const Text(
                  'YUK XATI / YO‘L VARAQASI',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A), letterSpacing: 0.8),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF0F172A)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Color(0xFF0F172A), thickness: 1.5),

            Flexible(
              child: ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                children: [
                  // Kompaniya rekviziti
                  const Center(
                    child: Column(
                      children: [
                        Text('NAMUNA TOSH JILO · NTJ ERP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        SizedBox(height: 2),
                        Text('Tovarlarni avtotransport orqali yetkazib berish hujjati', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Hujjat raqami va sana
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Reys raqami: #${delivery.id}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        Text('Sana: ${formatDateTime(delivery.createdAt)}', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Mashina va Haydovchi bloki
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text('Mashina:', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            const SizedBox(width: 6),
                            Text('${delivery.vehicleModel} (${delivery.vehicleNumber})', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                            const Spacer(),
                            const Text('Haydovchi:', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            const SizedBox(width: 6),
                            Text(delivery.driverName, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                          ],
                        ),
                        if (delivery.driverPhone != null) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text('Tel: ${delivery.driverPhone}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Qabul qiluvchi mijoz va manzil
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Qabul qiluvchi: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            Text(delivery.recipientName, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                            if (delivery.recipientPhone != null)
                              Text(' (${delivery.recipientPhone})', style: const TextStyle(color: Color(0xFF64748B))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Yetkazish manzili: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            Expanded(
                              child: Text(
                                delivery.destinationAddress ?? 'Ko‘rsatilmagan',
                                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Tovarlar jadvali
                  const Text('Yuklangan tovarlar ro‘yxati:', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  Table(
                    border: TableBorder.all(color: const Color(0xFFCBD5E1), width: 1),
                    columnWidths: const {
                      0: FixedColumnWidth(36),
                      1: FlexColumnWidth(4),
                      2: FlexColumnWidth(2),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                        children: const [
                          Padding(padding: EdgeInsets.all(6), child: Text('№', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5))),
                          Padding(padding: EdgeInsets.all(6), child: Text('Mahsulot nomi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5))),
                          Padding(padding: EdgeInsets.all(6), child: Text('Miqdori', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5))),
                        ],
                      ),
                      for (int i = 0; i < delivery.items.length; i++)
                        TableRow(
                          children: [
                            Padding(padding: const EdgeInsets.all(6), child: Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(6), child: Text(delivery.items[i].productName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text('${delivery.items[i].quantity} ${delivery.items[i].unit}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Yo'l haqi
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Yo‘l haqi / Yetkazish narxi:', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                      Text('${money(delivery.deliveryFee)} (${delivery.feePayerLabel})', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Imzolar bloki
                  const Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Yukni topshirdi (Haydovchi):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                            SizedBox(height: 24),
                            Divider(color: Color(0xFF94A3B8)),
                            Text('Imzo: _______________', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      SizedBox(width: 30),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Yukni qabul qildi (Mijoz):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                            SizedBox(height: 24),
                            Divider(color: Color(0xFF94A3B8)),
                            Text('Imzo: _______________', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            // Tugmalar
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: 'YUK XATI #${delivery.id}\n'
                          'Mashina: ${delivery.vehicleModel} ${delivery.vehicleNumber}\n'
                          'Haydovchi: ${delivery.driverName} (${delivery.driverPhone ?? ""})\n'
                          'Mijoz: ${delivery.recipientName} (${delivery.recipientPhone ?? ""})\n'
                          'Manzil: ${delivery.destinationAddress ?? ""}\n'
                          'Tovarlar: ${delivery.items.map((i) => "${i.productName} - ${i.quantity} ${i.unit}").join(", ")}\n'
                          'Yo‘l haqi: ${money(delivery.deliveryFee)}',
                    ));
                    showMessage(context, '✓ Hujjat ma’lumotlari nusxalandi');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Nusxa olish'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    showMessage(context, '✓ Yo‘l varaqasi printerga yuborildi');
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text('Chop etish'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

