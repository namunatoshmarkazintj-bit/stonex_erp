import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';
import 'receipt_dialog.dart';

class ReturnProductDialog extends StatefulWidget {
  const ReturnProductDialog({super.key, required this.sale, this.onSuccess});

  final SaleResult sale;
  final VoidCallback? onSuccess;

  static Future<void> show(BuildContext context, SaleResult sale, {VoidCallback? onSuccess}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ReturnProductDialog(sale: sale, onSuccess: onSuccess),
    );
  }

  @override
  State<ReturnProductDialog> createState() => _ReturnProductDialogState();
}

class _ReturnProductDialogState extends State<ReturnProductDialog> {
  late final Map<int, double> _returnQuantities;
  final Set<int> _forcedCutReturnIds = {};
  final _reasonCtrl = TextEditingController(text: 'Ortib qolgan butun mahsulot qaytarildi');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _returnQuantities = {};
    for (final it in widget.sale.items) {
      _returnQuantities[it.productId] = 0.0;
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _daysAgo {
    final created = widget.sale.createdAt ?? DateTime.now();
    return DateTime.now().difference(created).inDays;
  }

  bool get _isExpired => _daysAgo > 10;

  double get _totalRefund {
    double sum = 0;
    for (final it in widget.sale.items) {
      if (it.isCut && !_forcedCutReturnIds.contains(it.productId)) continue;
      final q = _returnQuantities[it.productId] ?? 0.0;
      sum += q * it.unitPrice;
    }
    return sum;
  }

  double get _debtReduction {
    final remDebt = widget.sale.debt;
    return _totalRefund < remDebt ? _totalRefund : remDebt;
  }

  double get _cashRefund {
    return _totalRefund - _debtReduction;
  }

  bool get _canSubmit {
    if (_isExpired || _busy) return false;
    return _totalRefund > 0;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final itemsToReturn = <({int productId, double quantity})>[];
      for (final it in widget.sale.items) {
        if (it.isCut && !_forcedCutReturnIds.contains(it.productId)) continue;
        final q = _returnQuantities[it.productId] ?? 0.0;
        if (q > 0) {
          itemsToReturn.add((productId: it.productId, quantity: q));
        }
      }

      if (itemsToReturn.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'Kamida bitta tovar qaytarish miqdorini tanlang';
        });
        return;
      }

      final repo = context.read<AppRepositories>().sales;
      final updated = await repo.returnSale(
        widget.sale.id,
        items: itemsToReturn,
        reason: _reasonCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSuccess?.call();

      showMessage(
        context,
        'Chek #${widget.sale.id} bo‘yicha tovar muvaffaqiyatli qaytarildi!\nKassadan qaytarildi: ${money(_cashRefund)}',
      );

      // Yangilangan chekni ko'rsatish
      await ReceiptDialog.show(context, updated);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final sale = widget.sale;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.cardColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Sarlavhasi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_return_rounded, color: Color(0xFFD97706), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mahsulotni qaytarish (Vozvrat)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.inkColor),
                        ),
                        Text(
                          'Chek №: #${sale.id.toString().padLeft(6, '0')} • ${formatDateTime(sale.createdAt ?? DateTime.now())}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
            ),

            // Asosiy kontent
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 10 KUNLIK MUDDAT BANNERI
                    if (_isExpired)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Qaytarish muddati (10 kun) o‘tgan!',
                                    style: TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Ushbu savdo bundan $_daysAgo kun oldin amalga oshirilgan. Nizomga muvofiq, mahsulot faqat 10 kun ichida qaytarib olinishi mumkin.',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
                                      fontSize: 11.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_rounded, color: AppColors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Qaytarish kafolati amalda: savdo ${_daysAgo == 0 ? "bugun" : "$_daysAgo kun oldin"} qilingan (10 kunlik muddat ichida ✅).',
                                style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),
                    Text(
                      'Chekdagi mahsulotlar ro‘yxati',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.inkColor),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Maxsus o‘lchamda kesib berilgan kafellar qaytarib olinmaydi. Faqat butun tovarlar qabul qilinadi.',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),

                    // Mahsulotlar kartochkalari
                    for (final it in sale.items) ...[
                      _buildItemReturnCard(context, it),
                      const SizedBox(height: 10),
                    ],

                    const SizedBox(height: 12),

                    // Sabab / Izoh
                    TextField(
                      controller: _reasonCtrl,
                      decoration: InputDecoration(
                        labelText: 'Qaytarish sababi (izoh)',
                        hintText: 'Masalan: mijoz ortib qolgan toshlarni qaytardi',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Moliyaviy yakuniy hisob
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131920) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Qaytariladigan tovarlar:', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                              Text(money(_totalRefund), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.inkColor)),
                            ],
                          ),
                          if (_debtReduction > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Nasiyadan chegiriladi:', style: TextStyle(fontSize: 12, color: Color(0xFFD97706))),
                                Text('- ${money(_debtReduction)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                              ],
                            ),
                          ],
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Kassadan qaytariladigan naqd pul:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              Text(
                                money(_cashRefund),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? AppColors.neonLime : const Color(0xFF047857),
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
            ),

            // Modal pastki harakatlar paneli
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Bekor qilish'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
                      foregroundColor: isDark ? AppColors.ink : Colors.white,
                      disabledBackgroundColor: AppColors.muted.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.assignment_return_rounded, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _busy ? 'Qaytarilmoqda...' : 'Tasdiqlash (${money(_cashRefund)})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

  Widget _buildItemReturnCard(BuildContext context, SaleItemRecord it) {
    final isDark = context.isDark;
    final isCut = it.isCut;
    final isForced = _forcedCutReturnIds.contains(it.productId);
    final selectedQty = _returnQuantities[it.productId] ?? 0.0;

    Color cardBg;
    Color borderColor;
    if (isCut && !isForced) {
      cardBg = isDark ? const Color(0xFF241517) : const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFF87171).withValues(alpha: 0.4);
    } else if (isForced) {
      cardBg = isDark ? const Color(0xFF2E2413) : const Color(0xFFFEFCE8);
      borderColor = const Color(0xFFF59E0B).withValues(alpha: selectedQty > 0 ? 0.8 : 0.4);
    } else if (selectedQty > 0) {
      cardBg = isDark ? const Color(0xFF1E281F) : const Color(0xFFF0FDF4);
      borderColor = AppColors.green.withValues(alpha: 0.6);
    } else {
      cardBg = context.cardColor;
      borderColor = context.borderColor;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: selectedQty > 0 ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.productName,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: (isCut && !isForced)
                            ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B))
                            : context.inkColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sotilgan narx: ${money(it.unitPrice)} • Jami olingan: ${qty(it.quantity)} dona/m²',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (isCut && !isForced)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block_rounded, size: 12, color: AppColors.danger),
                      SizedBox(width: 4),
                      Text(
                        'Kesilgan (Olinmaydi)',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.danger),
                      ),
                    ],
                  ),
                )
              else if (isCut && isForced)
                InkWell(
                  onTap: () {
                    setState(() {
                      _forcedCutReturnIds.remove(it.productId);
                      _returnQuantities[it.productId] = 0.0;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFD97706)),
                        SizedBox(width: 4),
                        Text(
                          'Majburiy yoqildi ✕',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Butun holatda ✅',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.green),
                  ),
                ),
            ],
          ),

          if (isCut && !isForced) ...[
            const SizedBox(height: 8),
            const Text(
              'Xaridor talabiga ko‘ra maxsus razmerda kesib berilgan kafellar nizom bo‘yicha qaytarib olinmaydi.',
              style: TextStyle(fontSize: 10.5, color: AppColors.danger, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                setState(() {
                  _forcedCutReturnIds.add(it.productId);
                  if ((_returnQuantities[it.productId] ?? 0) == 0) {
                    _returnQuantities[it.productId] = it.quantity;
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_open_rounded, size: 14, color: Color(0xFFD97706)),
                    SizedBox(width: 6),
                    Text(
                      'Majburlab tanlash (Kesilgan bo‘lsa ham qaytarish)',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            if (isCut && isForced) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFFD97706)),
                    SizedBox(width: 4),
                    Text(
                      'Diqqat: Ushbu kesilgan mahsulot majburiy qabul qilinmoqda',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Qaytarish miqdori:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.subtextColor),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Stepper: [-] [qty] [+]
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1B232A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 16),
                                padding: const EdgeInsets.all(5),
                                constraints: const BoxConstraints(),
                                onPressed: selectedQty > 0
                                    ? () {
                                        setState(() {
                                          final next = (selectedQty - 1).clamp(0.0, it.quantity);
                                          _returnQuantities[it.productId] = next;
                                        });
                                      }
                                    : null,
                              ),
                              Container(
                                constraints: const BoxConstraints(minWidth: 40),
                                alignment: Alignment.center,
                                child: Text(
                                  qty(selectedQty),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: selectedQty > 0 ? (isDark ? AppColors.neonLime : AppColors.ink) : AppColors.muted,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, size: 16),
                                padding: const EdgeInsets.all(5),
                                constraints: const BoxConstraints(),
                                onPressed: selectedQty < it.quantity
                                    ? () {
                                        setState(() {
                                          final next = (selectedQty + 1).clamp(0.0, it.quantity);
                                          _returnQuantities[it.productId] = next;
                                        });
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          onPressed: () {
                            setState(() {
                              _returnQuantities[it.productId] = it.quantity;
                            });
                          },
                          child: const Text('Barchasi', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

