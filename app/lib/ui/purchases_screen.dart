import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late Future<List<StockMovementRecord>> _movementsFuture;
  late Future<List<Product>> _productsFuture;
  final _searchCtrl = TextEditingController();
  String _dateFilter = 'Barchasi';

  StockRepository get _stockRepo => context.read<AppRepositories>().stock;
  ProductRepository get _productRepo => context.read<AppRepositories>().products;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _movementsFuture = _stockRepo.movements();
      _productsFuture = _productRepo.list();
    });
  }

  bool _matchesDate(DateTime dt) {
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

  Future<void> _openNewPurchaseDialog(List<Product> products) async {
    if (products.isEmpty) {
      showMessage(context, 'Kirim qilish uchun avval mahsulot qo‘shilgan bo‘lishi kerak', error: true);
      return;
    }

    Product selected = products.first;
    final qtyCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: selected.costPrice > 0 ? selected.costPrice.round().toString() : '');
    final supplierCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String paymentMethod = 'cash';
    bool inDona = false;
    bool inPachka = false;
    bool busy = false;
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final q = parseInput(qtyCtrl.text) ?? 0;
          final c = parseInput(costCtrl.text) ?? 0;
          final totalEst = q * c;

          return AlertDialog(
            backgroundColor: context.dialogBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                const Icon(Icons.add_shopping_cart_rounded, color: AppColors.neonLime, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Yangi Xarid Kirimi',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: MediaQuery.sizeOf(context).width < 450 ? 16 : 18,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (errorText != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ),

                    // Mahsulot tanlash
                    DropdownButtonFormField<Product>(
                      value: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Xarid qilinayotgan tovar / xomashyo'),
                      items: products.map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          '${p.name} (Hozir: ${p.stock.toStringAsFixed(1)} ${p.unit})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )).toList(),
                      onChanged: (p) {
                        if (p != null) {
                          setS(() {
                            selected = p;
                            inDona = false;
                            inPachka = false;
                            if (p.costPrice > 0) {
                              costCtrl.text = p.costPrice.round().toString();
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Miqdor va O'lchov
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Miqdor (${inPachka ? 'pachka' : (inDona ? 'dona' : selected.unit)})',
                              hintText: 'Masalan: 50',
                            ),
                            onChanged: (_) => setS(() {}),
                          ),
                        ),
                        if (selected.hasPachka) ...[
                          const SizedBox(width: 8),
                          FilterChip(
                            label: Text('pachka (${qty(selected.effectiveBoxM2 ?? 1)} m²)', style: const TextStyle(fontSize: 12)),
                            selected: inPachka,
                            onSelected: (v) => setS(() {
                              inPachka = v;
                              if (inPachka) inDona = false;
                            }),
                          ),
                        ] else if (selected.hasDona) ...[
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('dona', style: TextStyle(fontSize: 12)),
                            selected: inDona,
                            onSelected: (v) => setS(() {
                              inDona = v;
                              if (inDona) inPachka = false;
                            }),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Xarid narxi (Tannarx)
                    TextField(
                      controller: costCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Birlik xarid narxi (so‘m)',
                        hintText: '1 ${selected.unit} narxi',
                        suffixText: 'so‘m',
                      ),
                      onChanged: (_) => setS(() {}),
                    ),
                    const SizedBox(height: 12),

                    // Jami xarid summasi indikatori
                    if (totalEst > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.neonLime.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.neonLime.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Jami xarid summasi:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(money(totalEst), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.neonLime)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Yetkazib beruvchi / Ta'minotchi
                    TextField(
                      controller: supplierCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Yetkazib beruvchi (Ta‘minotchi)',
                        hintText: 'Masalan: Navoiy Marmar MCHJ, Xurshid aka',
                        prefixIcon: Icon(Icons.business_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // To'lov turi
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'To‘lov usuli'),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Naqd pul', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'bank', child: Text('Bank o‘tkazmasi (Hisob raqam)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'card', child: Text('Korporativ karta', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        if (v != null) setS(() => paymentMethod = v);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Qo'shimcha izoh / Yuk xati
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Hujjat raqami / Izoh',
                        hintText: 'Masalan: Yuk xati #4582, Toshkent omboriga',
                        prefixIcon: Icon(Icons.note_alt_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx, false),
                child: const Text('Bekor qilish'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final qVal = parseInput(qtyCtrl.text);
                        final cVal = parseInput(costCtrl.text);
                        if (qVal == null || qVal <= 0) {
                          setS(() => errorText = 'Miqdorni to‘g‘ri kiriting');
                          return;
                        }
                        if (cVal == null || cVal < 0) {
                          setS(() => errorText = 'Xarid narxini to‘g‘ri kiriting');
                          return;
                        }

                        setS(() {
                          busy = true;
                          errorText = null;
                        });

                        final baseQty = (inPachka && selected.hasPachka)
                            ? qVal * (selected.effectiveBoxM2 ?? 1.0)
                            : ((inDona && selected.hasDona) ? qVal * selected.donaM2! : qVal);
                        final fullNoteParts = <String>[];
                        if (supplierCtrl.text.trim().isNotEmpty) {
                          fullNoteParts.add('Yetkazib beruvchi: ${supplierCtrl.text.trim()}');
                        }
                        if (paymentMethod != 'cash') {
                          fullNoteParts.add('To‘lov: $paymentMethod');
                        }
                        if (noteCtrl.text.trim().isNotEmpty) {
                          fullNoteParts.add(noteCtrl.text.trim());
                        }
                        final combinedNote = fullNoteParts.isNotEmpty ? fullNoteParts.join(' • ') : 'Xarid kirimi';

                        try {
                          await _stockRepo.purchase(
                            productId: selected.id,
                            quantity: baseQty,
                            unitCost: cVal,
                            note: combinedNote,
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setS(() {
                            busy = false;
                            errorText = e.toString();
                          });
                        }
                      },
                style: FilledButton.styleFrom(backgroundColor: AppColors.neonLime, foregroundColor: AppColors.ink),
                child: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Kirim qilish', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true && mounted) {
      showMessage(context, 'Xarid muvaffaqiyatli kirim qilindi');
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<dynamic>>(
        future: Future.wait([_movementsFuture, _productsFuture]),
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
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Qayta yuklash'),
                  ),
                ],
              ),
            );
          }

          final movements = snapshot.data![0] as List<StockMovementRecord>;
          final products = snapshot.data![1] as List<Product>;
          final prodMap = {for (final p in products) p.id: p};

          // Filter faqat xaridlar (purchase)
          final purchases = movements.where((m) => m.kind == 'purchase').toList();
          final query = _searchCtrl.text.trim().toLowerCase();

          final filtered = purchases.where((p) {
            if (!_matchesDate(p.createdAt)) return false;
            if (query.isNotEmpty) {
              final prod = prodMap[p.productId];
              final pName = p.productName ?? prod?.name ?? '';
              final note = p.note ?? '';
              final user = p.createdByName ?? '';
              if (!pName.toLowerCase().contains(query) &&
                  !note.toLowerCase().contains(query) &&
                  !user.toLowerCase().contains(query)) {
                return false;
              }
            }
            return true;
          }).toList();

          // Statistika
          double totalSpent = 0;
          for (final p in filtered) {
            final prod = prodMap[p.productId];
            final cost = p.unitCost ?? prod?.costPrice ?? 0;
            totalSpent += p.qtyDelta.abs() * cost;
          }

          return RefreshIndicator(
            onRefresh: () async => _loadData(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Top header
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Xaridlar & Ta‘minot',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Xomashyo va tovarlar xaridi, yetkazib beruvchilar va tannarx hisoboti',
                          style: TextStyle(color: context.subtextColor, fontSize: 13),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: () => _openNewPurchaseDialog(products),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.neonLime,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                      label: const Text('Yangi Xarid Kirimi', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // KPI Stat Cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmall = constraints.maxWidth < 440;
                    final cardWidth = isSmall
                        ? (constraints.maxWidth < 360 ? constraints.maxWidth : (constraints.maxWidth - 12) / 2)
                        : (constraints.maxWidth < 800 ? (constraints.maxWidth - 24) / 3 : 220.0);
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _kpiCard(
                          context,
                          title: 'Jami Xaridlar Summasi',
                          value: money(totalSpent),
                          icon: Icons.account_balance_rounded,
                          color: AppColors.neonLime,
                          width: cardWidth,
                        ),
                        _kpiCard(
                          context,
                          title: 'Xarid Operatsiyalari',
                          value: '${filtered.length} ta',
                          icon: Icons.shopping_bag_rounded,
                          color: const Color(0xFF38BDF8),
                          width: cardWidth,
                        ),
                        _kpiCard(
                          context,
                          title: 'Ombordagi Mahsulotlar',
                          value: '${products.length} xil',
                          icon: Icons.inventory_2_rounded,
                          color: const Color(0xFF10B981),
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
                          hintText: 'Mahsulot nomi, yetkazib beruvchi, izoh yoki xodim...',
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
                      const SizedBox(height: 10),
                      SingleChildScrollView(
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Xaridlar ro'yxati
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.shopping_bag_outlined, size: 52, color: context.subtextColor.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'Birorta ham xarid yozuvi topilmadi',
                          style: TextStyle(color: context.subtextColor, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                else
                  for (final item in filtered)
                    _purchaseCard(context, item, prodMap[item.productId]),
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
      width: width ?? 220,
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

  Widget _purchaseCard(BuildContext context, StockMovementRecord m, Product? prod) {
    final pName = m.productName ?? prod?.name ?? 'Mahsulot #${m.productId}';
    final unit = prod?.unit ?? 'birlik';
    final cost = m.unitCost ?? prod?.costPrice ?? 0;
    final totalCost = m.qtyDelta.abs() * cost;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF10B981), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        pName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '+${m.qtyDelta.toStringAsFixed(1)} $unit',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (cost > 0) ...[
                      Text(
                        'Tannarx: ${money(cost)} / $unit',
                        style: TextStyle(color: context.subtextColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Jami: ${money(totalCost)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.neonLime),
                      ),
                    ],
                  ],
                ),
                if (m.note != null && m.note!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      m.note!,
                      style: TextStyle(color: context.subtextColor, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time_rounded, size: 13, color: context.subtextColor),
                        const SizedBox(width: 4),
                        Text(
                          formatDateTime(m.createdAt),
                          style: TextStyle(color: context.subtextColor, fontSize: 11),
                        ),
                      ],
                    ),
                    if (m.createdByName != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_rounded, size: 13, color: context.subtextColor),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              'Qabul qildi: ${m.createdByName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.subtextColor, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
