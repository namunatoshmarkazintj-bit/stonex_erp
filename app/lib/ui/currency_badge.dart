import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../state/currency_controller.dart';
import 'common.dart';

/// Topbarda va mobil ekranda ko'rinadigan valyuta kursi vidjeti.
class CurrencyBadge extends StatelessWidget {
  const CurrencyBadge({super.key, this.isCompact = false});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => showCurrencyDialog(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2530) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: currency.isCustom
                ? const Color(0xFFF59E0B).withOpacity(0.5)
                : const Color(0xFF10B981).withOpacity(0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currency.isLoading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
              )
            else
              Text(
                isCompact
                    ? '\$1 = ${money(currency.usdRate).replaceAll(" so‘m", "")}'
                    : '\$1 = ${money(currency.usdRate)}',
                style: TextStyle(
                  fontSize: isCompact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF065F46),
                ),
              ),
            if (currency.isCustom && !isCompact) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Do‘kon',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kursni ko'rish, Markaziy Bankdan yangilash yoki o'zgartirish dialogi
Future<void> showCurrencyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const _CurrencySettingsDialog(),
  );
}

class _CurrencySettingsDialog extends StatefulWidget {
  const _CurrencySettingsDialog();

  @override
  State<_CurrencySettingsDialog> createState() => _CurrencySettingsDialogState();
}

class _CurrencySettingsDialogState extends State<_CurrencySettingsDialog> {
  late final TextEditingController _customRateCtrl;
  bool _useCustom = false;
  double _calcUsd = 100;
  double _calcUzs = 1000000;

  @override
  void initState() {
    super.initState();
    final currency = context.read<CurrencyController>();
    _useCustom = currency.isCustom;
    _customRateCtrl = TextEditingController(text: currency.usdRate.round().toString());
  }

  @override
  void dispose() {
    _customRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: context.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.currency_exchange_rounded, color: Color(0xFF10B981), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Valyuta kursi (USD / UZS)',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Markaziy Bank kursi va do‘kon narxlari',
                  style: TextStyle(fontSize: 12, color: context.mutedColor),
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
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Markaziy Bank (CBU) Rasmiy Kursi Kartochkasi
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C222B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2C3340) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '🇺🇿 O‘zbekiston Markaziy Banki (CBU)',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (currency.isLoading)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                          )
                        else
                          InkWell(
                            onTap: () => currency.fetchLiveRate(),
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF10B981)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Yangilash',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        const Text(
                          '1 USD = ',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.muted),
                        ),
                        Text(
                          money(currency.cbuRate),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (currency.cbuDiff.isNotEmpty && currency.cbuDiff != '0.00')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: currency.cbuDiff.startsWith('-')
                                  ? const Color(0xFFEF4444).withOpacity(0.12)
                                  : const Color(0xFF10B981).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              currency.cbuDiff,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: currency.cbuDiff.startsWith('-')
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF10B981),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (currency.cbuDate.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Rasmiy sana: ${currency.cbuDate}',
                        style: TextStyle(fontSize: 11, color: context.mutedColor),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. Do'kon kursi rejimini tanlash
              const Text(
                'Savdoda qo‘llaniladigan kurs:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              RadioListTile<bool>(
                value: false,
                groupValue: _useCustom,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Markaziy Bank rasmiy kursi (avtomatik)'),
                subtitle: Text('Har kuni internetdan yangilanadi: ${money(currency.cbuRate)}',
                    style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
                onChanged: (val) {
                  setState(() {
                    _useCustom = false;
                  });
                  currency.resetToCbuRate();
                },
              ),

              RadioListTile<bool>(
                value: true,
                groupValue: _useCustom,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Do‘konning maxsus kursi (qo‘lda kiritish)'),
                subtitle: const Text('Kassa va hisob-kitoblarda belgilangan qat’iy kurs',
                    style: TextStyle(fontSize: 11.5)),
                onChanged: (val) {
                  setState(() {
                    _useCustom = true;
                  });
                },
              ),

              if (_useCustom) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customRateCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '1 USD kursi (so‘m)',
                          prefixText: '\$1 = ',
                          suffixText: 'so‘m',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF161B22) : const Color(0xFFF1F5F9),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final val = parseInput(_customRateCtrl.text);
                        if (val != null && val > 0) {
                          currency.setCustomRate(val);
                          showMessage(context, 'Do‘kon kursi \$1 = ${money(val)} qilib belgilandi');
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Saqlash'),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // 3. Tezkor konvertor kalkulyatori
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141820) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tezkor hisob-kitob (Kalkulyator):',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '\$100 = ${money(currency.toUzs(_calcUsd))}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '1 mln so‘m = ${moneyUsd(currency.toUsd(_calcUzs))}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Yopish'),
        ),
      ],
    );
  }
}

