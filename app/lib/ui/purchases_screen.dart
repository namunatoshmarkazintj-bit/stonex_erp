import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import '../state/auth_controller.dart';
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
      case 'Nasiyalar':
        return true;
      default:
        return true;
    }
  }

  static Widget _buildPaymentMethodCard({
    required BuildContext context,
    required String id,
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = context.isDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: isDark ? 0.22 : 0.12)
                : (isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color
                  : (isDark ? const Color(0xFF333A44) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.25)
                      : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: isSelected ? color : context.subtextColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? (isDark ? Colors.white : color)
                        : context.inkColor,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: color,
                ),
            ],
          ),
        ),
      ),
    );
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
    DateTime? debtDueDate = DateTime.now().add(const Duration(days: 30));
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

                    // Mahsulot tanlash (Qidiruv oynali zamonaviy tanlov)
                    InkWell(
                      onTap: () async {
                        final chosen = await showDialog<Product>(
                          context: context,
                          builder: (c) => _PurchaseProductPickerDialog(
                            products: products,
                            current: selected,
                          ),
                        );
                        if (chosen != null) {
                          setS(() {
                            selected = chosen;
                            inDona = false;
                            inPachka = false;
                            if (chosen.costPrice > 0) {
                              costCtrl.text = chosen.costPrice.round().toString();
                            }
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF21262D) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.greenSoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.inventory_2_rounded, color: AppColors.green, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Xarid qilinayotgan tovar / xomashyo:',
                                    style: TextStyle(fontSize: 11, color: context.mutedColor, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${selected.name} (Hozir: ${selected.stock.toStringAsFixed(1)} ${selected.unit})',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: context.inkColor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: context.isDark ? const Color(0xFF30363D) : const Color(0xFFF1F3F5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_rounded, size: 14),
                                  SizedBox(width: 4),
                                  Text('Qidirish', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

                    // Jami xarid summasi va Qarz oynasi
                    if (totalEst > 0) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: AppColors.neonLime.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.neonLime.withValues(alpha: 0.35)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.shopping_bag_outlined, size: 13, color: AppColors.neonLime),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Jami xarid:',
                                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: context.subtextColor),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      money(totalEst),
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.neonLime),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (paymentMethod == 'debt') ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.handshake_rounded, size: 13, color: Color(0xFFD97706)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Qarz summasi:',
                                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFFD97706)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        money(totalEst),
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFFD97706)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

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

                    // To'lov turi tanlash (Zamonaviy stil)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.payments_outlined, size: 16, color: context.subtextColor),
                            const SizedBox(width: 6),
                            Text(
                              'To‘lov usuli:',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: context.inkColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPaymentMethodCard(
                                context: context,
                                id: 'cash',
                                label: 'Naqd pul',
                                icon: Icons.payments_rounded,
                                color: const Color(0xFF10B981),
                                isSelected: paymentMethod == 'cash',
                                onTap: () => setS(() => paymentMethod = 'cash'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildPaymentMethodCard(
                                context: context,
                                id: 'debt',
                                label: 'Qarz (Nasiya)',
                                icon: Icons.handshake_rounded,
                                color: const Color(0xFFF59E0B),
                                isSelected: paymentMethod == 'debt',
                                onTap: () => setS(() => paymentMethod = 'debt'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPaymentMethodCard(
                                context: context,
                                id: 'bank',
                                label: 'Bank o‘tkazmasi',
                                icon: Icons.account_balance_rounded,
                                color: const Color(0xFF0284C7),
                                isSelected: paymentMethod == 'bank',
                                onTap: () => setS(() => paymentMethod = 'bank'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildPaymentMethodCard(
                                context: context,
                                id: 'card',
                                label: 'Karta',
                                icon: Icons.credit_card_rounded,
                                color: const Color(0xFF8B5CF6),
                                isSelected: paymentMethod == 'card',
                                onTap: () => setS(() => paymentMethod = 'card'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Qarz qaytarilish sanasi (agar to'lov turi Qarz bo'lsa)
                    if (paymentMethod == 'debt') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF2B2211) : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event_available_rounded, size: 18, color: Color(0xFFD97706)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Qarz qaytarilish sanasi:',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: context.inkColor,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () async {
                                    final now = DateTime.now();
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: debtDueDate ?? now.add(const Duration(days: 30)),
                                      firstDate: now,
                                      lastDate: now.add(const Duration(days: 730)),
                                    );
                                    if (picked != null) {
                                      setS(() => debtDueDate = picked);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD97706).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.edit_calendar_rounded, size: 14, color: Color(0xFFD97706)),
                                        const SizedBox(width: 5),
                                        Text(
                                          debtDueDate != null ? formatDate(debtDueDate!) : 'Sanani tanlash',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFD97706),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final d in [7, 14, 30, 60])
                                  ChoiceChip(
                                    label: Text(
                                      '+$d kun',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: (debtDueDate != null && (debtDueDate!.difference(DateTime.now()).inDays - d).abs() <= 1)
                                            ? Colors.white
                                            : context.inkColor,
                                      ),
                                    ),
                                    selected: debtDueDate != null &&
                                        (debtDueDate!.difference(DateTime.now()).inDays - d).abs() <= 1,
                                    selectedColor: const Color(0xFFD97706),
                                    backgroundColor: context.isDark ? const Color(0xFF1E232B) : Colors.white,
                                    side: BorderSide(
                                      color: (debtDueDate != null && (debtDueDate!.difference(DateTime.now()).inDays - d).abs() <= 1)
                                          ? const Color(0xFFD97706)
                                          : (context.isDark ? const Color(0xFF3B3322) : const Color(0xFFFDE68A)),
                                    ),
                                    onSelected: (sel) {
                                      if (sel) {
                                        setS(() {
                                          debtDueDate = DateTime.now().add(Duration(days: d));
                                        });
                                      }
                                    },
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

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
                          if (paymentMethod == 'debt') {
                            final dueStr = debtDueDate != null ? formatDate(debtDueDate!) : 'muddatsiz';
                            fullNoteParts.add('To‘lov: Nasiya/Qarz [Qaytarish: $dueStr]');
                          } else if (paymentMethod == 'bank') {
                            fullNoteParts.add('To‘lov: Bank o‘tkazmasi');
                          } else if (paymentMethod == 'card') {
                            fullNoteParts.add('To‘lov: Korporativ karta');
                          } else {
                            fullNoteParts.add('To‘lov: $paymentMethod');
                          }
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

  Future<void> _confirmClearAllPurchases(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Xaridlarni tozalash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Text(
          'Haqiqatan ham barcha $count ta xarid yozuvlarini o‘chirmoqchimisiz?\n\n'
          'Ushbu xaridlar orqali omborga kirim qilingan tovarlar miqdori ham ombor zaxirasidan bekor qilinadi.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ha, tozalansin'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        await _stockRepo.cleanPurchases();
        if (mounted) {
          showMessage(context, 'Barcha xaridlar muvaffaqiyatli tozalandi');
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          showMessage(context, 'Tozalashda xatolik: $e', error: true);
        }
      }
    }
  }

  Future<void> _confirmDeletePurchase(StockMovementRecord m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Xaridni o‘chirish', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Text(
          'Haqiqatan ham "${m.productName ?? 'Mahsulot'}" xarid yozuvini o‘chirmoqchimisiz?\n\n'
          'Ombor zaxirasidan ${m.qtyDelta.abs()} miqdor ayirib tashlanadi.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('O‘chirish'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        await _stockRepo.deleteMovement(m.id);
        if (mounted) {
          showMessage(context, 'Xarid yozuvi o‘chirildi');
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          showMessage(context, 'O‘chirishda xatolik: $e', error: true);
        }
      }
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
            if (_dateFilter == 'Nasiyalar') {
              final isDebt = p.note != null && (p.note!.contains('Qarz') || p.note!.contains('Nasiya'));
              if (!isDebt) return false;
            }
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
          double totalDebt = 0;
          int debtCount = 0;
          for (final p in filtered) {
            final prod = prodMap[p.productId];
            final cost = p.unitCost ?? prod?.costPrice ?? 0;
            final lineTotal = p.qtyDelta.abs() * cost;
            totalSpent += lineTotal;
            final isDebt = p.note != null && (p.note!.contains('Qarz') || p.note!.contains('Nasiya'));
            if (isDebt) {
              totalDebt += lineTotal;
              debtCount++;
            }
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (purchases.isNotEmpty) ...[
                          OutlinedButton.icon(
                            onPressed: () => _confirmClearAllPurchases(purchases.length),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                            label: const Text('Tozalash', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Builder(
                          builder: (context) {
                            Role? currentRole;
                            try {
                              currentRole = Provider.of<AuthController?>(context, listen: true)?.user?.role;
                            } catch (_) {}
                            if (currentRole == Role.boshliq) return const SizedBox.shrink();
                            return FilledButton.icon(
                              onPressed: () => _openNewPurchaseDialog(products),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.neonLime,
                                foregroundColor: AppColors.ink,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                              label: const Text('Yangi Xarid Kirimi', style: TextStyle(fontWeight: FontWeight.w800)),
                            );
                          },
                        ),
                      ],
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
                        : (constraints.maxWidth < 950 ? (constraints.maxWidth - 12) / 2 : 220.0);
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
                          title: debtCount > 0 ? 'Nasiyaga Qarz ($debtCount ta)' : 'Nasiyaga Qarz',
                          value: money(totalDebt),
                          icon: Icons.handshake_rounded,
                          color: const Color(0xFFF59E0B),
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
                            for (final d in ['Barchasi', 'Bugun', 'Shu hafta', 'Shu oy', 'Nasiyalar'])
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+${m.qtyDelta.toStringAsFixed(1)} $unit',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                          tooltip: 'O‘chirish',
                          splashRadius: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => _confirmDeletePurchase(m),
                        ),
                      ],
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
                      color: (m.note!.contains('Qarz') || m.note!.contains('Nasiya'))
                          ? const Color(0xFFD97706).withOpacity(0.15)
                          : Colors.black.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: (m.note!.contains('Qarz') || m.note!.contains('Nasiya'))
                          ? Border.all(color: const Color(0xFFD97706).withOpacity(0.4))
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (m.note!.contains('Qarz') || m.note!.contains('Nasiya')) ...[
                          const Icon(Icons.event_available_rounded, size: 14, color: Color(0xFFD97706)),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            m.note!,
                            style: TextStyle(
                              color: (m.note!.contains('Qarz') || m.note!.contains('Nasiya'))
                                  ? const Color(0xFFD97706)
                                  : context.subtextColor,
                              fontSize: 12,
                              fontWeight: (m.note!.contains('Qarz') || m.note!.contains('Nasiya'))
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
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

// ---------------------------------------------------------------------------
// Mahsulot tanlash uchun qidiruv oynasi (Searchable Picker)
// ---------------------------------------------------------------------------

class _PurchaseProductPickerDialog extends StatefulWidget {
  const _PurchaseProductPickerDialog({
    required this.products,
    required this.current,
  });

  final List<Product> products;
  final Product current;

  @override
  State<_PurchaseProductPickerDialog> createState() => _PurchaseProductPickerDialogState();
}

class _PurchaseProductPickerDialogState extends State<_PurchaseProductPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _selectedCategory = 'Barchasi';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final categories = <String>{'Barchasi'};
    for (final p in widget.products) {
      if (p.category != null && p.category!.trim().isNotEmpty) {
        categories.add(p.category!.trim());
      }
    }

    final filtered = widget.products.where((p) {
      if (_selectedCategory != 'Barchasi' && (p.category ?? '').trim() != _selectedCategory) {
        return false;
      }
      if (query.isNotEmpty) {
        final nameMatch = p.name.toLowerCase().contains(query);
        final skuMatch = p.sku.toLowerCase().contains(query);
        final qrMatch = p.qrCode.toLowerCase().contains(query);
        final catMatch = (p.category ?? '').toLowerCase().contains(query);
        return nameMatch || skuMatch || qrMatch || catMatch;
      }
      return true;
    }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: context.dialogBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Sarlavha
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.greenSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, color: AppColors.green, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Xarid uchun mahsulotni tanlang',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                        Text(
                          'Jami: ${widget.products.length} ta mahsulot mavjud',
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

            // Qidiruv maydoni
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Mahsulot nomi, kodi yoki artikul bo‘yicha qidirish...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setState(() => _searchCtrl.clear()),
                        )
                      : null,
                  filled: true,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            // Kategoriya chip-filtrlari
            if (categories.length > 2) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: categories.map((cat) {
                    final sel = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(cat, style: TextStyle(fontSize: 11.5, fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
                        selected: sel,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _selectedCategory = cat),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1),

            // Mahsulotlar ro'yxati
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, size: 40, color: context.mutedColor),
                          const SizedBox(height: 8),
                          Text(
                            'Hech qanday mahsulot topilmadi',
                            style: TextStyle(fontSize: 13, color: context.mutedColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemBuilder: (ctx, idx) {
                        final p = filtered[idx];
                        final isSel = p.id == widget.current.id;

                        return InkWell(
                          onTap: () => Navigator.pop(context, p),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? (context.isDark ? const Color(0xFF1B2E24) : const Color(0xFFE8F5E9))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? AppColors.green : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: context.isDark ? const Color(0xFF21262D) : const Color(0xFFF1F3F5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.inventory_2_outlined,
                                      size: 18,
                                      color: isSel ? AppColors.green : context.mutedColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: isSel ? AppColors.green : context.inkColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: p.stock > 0
                                                  ? AppColors.greenSoft
                                                  : Colors.orange.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Hozir: ${p.stock.toStringAsFixed(1)} ${p.unit}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: p.stock > 0 ? AppColors.green : Colors.orange[800],
                                              ),
                                            ),
                                          ),
                                          if (p.costPrice > 0) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              'Tannarx: ${money(p.costPrice)}',
                                              style: TextStyle(fontSize: 11, color: context.mutedColor),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSel)
                                  const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
