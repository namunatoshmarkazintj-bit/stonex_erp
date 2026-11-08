import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';
import 'receipt_dialog.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final _search = TextEditingController();
  late Future<List<SaleResult>> _future;
  String _dateFilter = 'Barchasi'; // 'Barchasi', 'Katta qarzlar (> 1 mln)', 'Bugun', 'Shu hafta', 'Shu oy'
  String _sort = 'qarz_desc'; // 'qarz_desc', 'sana_desc', 'sana_asc'
  int _viewMode = 0; // 0: Cheklar bo'yicha, 1: Mijozlar bo'yicha

  SalesRepository get _repo => context.read<AppRepositories>().sales;

  @override
  void initState() {
    super.initState();
    _future = _repo.listDebts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final f = _repo.listDebts();
    if (mounted) {
      setState(() {
        _future = f;
      });
    }
    await f;
  }

  void _copyReminderText(SaleResult sale) {
    final name = sale.customerName?.isNotEmpty == true ? sale.customerName! : 'Hurmatli mijoz';
    final text = 'Assalomu alaykum, $name!\n'
        '${CompanyInfo.name} dan xaridlaringiz bo‘yicha #${sale.id}-sonli chekdan '
        '${money(sale.debt)} miqdorida nasiya qarzdorligingiz mavjud.\n'
        'Iltimos, imkon qadar tezroq to‘lovni amalga oshirishingizni so‘raymiz.\n'
        'Aloqa va ma‘lumot uchun:\n${CompanyInfo.phonesFormatted}\n'
        'Manzil: ${CompanyInfo.address}';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF10B981),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('$name uchun eslatma xati nusxalandi (SMS / Telegramga tashlashingiz mumkin)!')),
          ],
        ),
      ),
    );
  }

  void _copyCustomerTotalReminder(String name, String? phone, double totalDebt, int count) {
    final text = 'Assalomu alaykum, $name!\n'
        '${CompanyInfo.name} dan xaridlaringiz ($count ta chek) bo‘yicha jami '
        '${money(totalDebt)} miqdorida nasiya qarzdorligingiz mavjud.\n'
        'Iltimos, to‘lovni amalga oshirishingizni so‘raymiz.\n'
        'Aloqa va ma‘lumot uchun:\n${CompanyInfo.phonesFormatted}\n'
        'Manzil: ${CompanyInfo.address}';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF10B981),
        content: Text('$name uchun umumiy qarzdorlik eslatmasi nusxalandi!'),
      ),
    );
  }

  Future<void> _pay(SaleResult sale) async {
    final ctrl = TextEditingController(text: sale.debt.round().toString());
    String method = 'cash';
    String? error;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: context.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(
            'Qarz to‘lovi — Chek #${sale.id}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions_rounded, color: Color(0xFFEF4444), size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sale.customerName?.isNotEmpty == true ? sale.customerName! : 'Noma‘lum mijoz',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.inkColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Qoldiq qarz: ${money(sale.debt)}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFEF4444)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'To‘lanayotgan summa'),
                  onChanged: (_) {
                    setS(() {
                      error = null;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('To‘liq yopish'),
                      onPressed: () {
                        setS(() {
                          ctrl.text = sale.debt.round().toString();
                          error = null;
                        });
                      },
                    ),
                    if (sale.debt > 100000)
                      ActionChip(
                        label: Text('Yarmi (${money(sale.debt / 2)})'),
                        onPressed: () {
                          setS(() {
                            ctrl.text = (sale.debt / 2).round().toString();
                            error = null;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'To‘lov usuli'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Naqd pul')),
                    DropdownMenuItem(value: 'card', child: Text('Bank kartasi')),
                    DropdownMenuItem(value: 'transfer', child: Text('Hisob / O‘tkazma')),
                  ],
                  onChanged: (v) {
                    setS(() {
                      method = v ?? 'cash';
                    });
                  },
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
              ],
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
                      final val = parseInput(ctrl.text);
                      if (val == null || val <= 0) {
                        setS(() {
                          error = 'To‘lov summasini to‘g‘ri kiriting';
                        });
                        return;
                      }
                      if (val > sale.debt + 0.01) {
                        setS(() {
                          error = 'To‘lov qarzdan ko‘p bo‘lishi mumkin emas';
                        });
                        return;
                      }
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final updated = await _repo.payDebt(sale.id, val, method: method);
                        if (ctx.mounted) {
                          Navigator.pop(ctx, true);
                          ReceiptDialog.show(context, updated);
                        }
                      } catch (e) {
                        setS(() {
                          busy = false;
                          error = e.toString();
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.neonLime,
                foregroundColor: AppColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                  : const Text('Qabul qilish', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );

    ctrl.dispose();
    if (ok == true && mounted) {
      showMessage(context, 'Qarz to‘lovi muvaffaqiyatli saqlandi');
      _reload();
    }
  }

  List<SaleResult> _applyFiltersAndSort(List<SaleResult> source) {
    var list = source;

    // Search
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) {
        final name = (s.customerName ?? '').toLowerCase();
        final phone = (s.customerPhone ?? '').toLowerCase();
        final idStr = '#${s.id}';
        final items = s.items.map((i) => i.productName.toLowerCase()).join(' ');
        return name.contains(q) || phone.contains(q) || idStr.contains(q) || items.contains(q);
      }).toList();
    }

    // Date / Type Filter
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_dateFilter == 'Katta qarzlar (> 1 mln)') {
      list = list.where((s) => s.debt >= 1000000).toList();
    } else if (_dateFilter == 'Bugun') {
      list = list.where((s) {
        if (s.createdAt == null) return false;
        return s.createdAt!.isAfter(today);
      }).toList();
    } else if (_dateFilter == 'Shu hafta') {
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      list = list.where((s) {
        if (s.createdAt == null) return false;
        return s.createdAt!.isAfter(startOfWeek);
      }).toList();
    } else if (_dateFilter == 'Shu oy') {
      final startOfMonth = DateTime(now.year, now.month, 1);
      list = list.where((s) {
        if (s.createdAt == null) return false;
        return s.createdAt!.isAfter(startOfMonth);
      }).toList();
    }

    // Sort
    if (_sort == 'qarz_desc') {
      list.sort((a, b) => b.debt.compareTo(a.debt));
    } else if (_sort == 'sana_desc') {
      list.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    } else if (_sort == 'sana_asc') {
      list.sort((a, b) => (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000)));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<SaleResult>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.neonLime));
          }
          if (snap.hasError) {
            return ErrorView(message: snap.error.toString(), onRetry: _reload);
          }
          final rawList = snap.data ?? [];
          final list = _applyFiltersAndSort(rawList);

          // Hisob-kitoblar (KPI)
          final totalDebt = rawList.fold<double>(0, (a, b) => a + b.debt);
          final uniqueCustomers = <String>{};
          for (final s in rawList) {
            if (s.customerName != null && s.customerName!.trim().isNotEmpty) {
              uniqueCustomers.add(s.customerName!.trim());
            }
          }
          final bigDebts = rawList.where((s) => s.debt >= 1000000).toList();

          return RefreshIndicator(
            onRefresh: _reload,
            color: AppColors.neonLime,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // KPI Kartochkalari
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 640;
                    final cardWidth = isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _DebtsKpiCard(
                          title: 'Jami Nasiyalar',
                          value: money(totalDebt),
                          icon: Icons.pending_actions_rounded,
                          color: const Color(0xFFEF4444),
                          width: cardWidth,
                        ),
                        _DebtsKpiCard(
                          title: 'Qarzdor Mijozlar',
                          value: '${uniqueCustomers.length} kishi',
                          icon: Icons.people_outline_rounded,
                          color: const Color(0xFFF59E0B),
                          width: cardWidth,
                        ),
                        _DebtsKpiCard(
                          title: 'Katta Qarzlar (>1M)',
                          value: '${bigDebts.length} ta chek',
                          icon: Icons.warning_amber_rounded,
                          color: const Color(0xFFE11D48),
                          width: cardWidth,
                        ),
                        _DebtsKpiCard(
                          title: 'Nasiyali Cheklar',
                          value: '${rawList.length} ta',
                          icon: Icons.receipt_long_rounded,
                          color: const Color(0xFF3B82F6),
                          width: cardWidth,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Qidiruv va Filtr paneli
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                hintText: 'Mijoz ismi, telefon raqami yoki chek #...',
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () {
                                          _search.clear();
                                          setState(() {});
                                        },
                                      ),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // View Switcher (Cheklar vs Mijozlar)
                          Container(
                            decoration: BoxDecoration(
                              color: context.isDark ? const Color(0xFF21262D) : const Color(0xFFEFF2F6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _viewToggleBtn('Cheklar', 0, Icons.receipt_outlined),
                                _viewToggleBtn('Mijozlar', 1, Icons.group_outlined),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final f in ['Barchasi', 'Katta qarzlar (> 1 mln)', 'Bugun', 'Shu hafta', 'Shu oy'])
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: Text(f, style: const TextStyle(fontSize: 12)),
                                        selected: _dateFilter == f,
                                        onSelected: (sel) {
                                          if (sel) setState(() => _dateFilter = f);
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Saralash (Sort)
                          PopupMenuButton<String>(
                            tooltip: 'Saralash',
                            initialValue: _sort,
                            onSelected: (v) => setState(() => _sort = v),
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(value: 'qarz_desc', child: Text('Qarz: Kattadan kichikka')),
                              PopupMenuItem(value: 'sana_desc', child: Text('Sana: Yangidan eskiga')),
                              PopupMenuItem(value: 'sana_asc', child: Text('Sana: Eskidan yangiga')),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                border: Border.all(color: context.borderColor),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.sort_rounded, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    _sort == 'qarz_desc' ? 'Katta qarzlar' : (_sort == 'sana_desc' ? 'Eng yangi' : 'Eng eski'),
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
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

                // Natijalar ro'yxati
                if (list.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: context.cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: const BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
                          child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.green, size: 38),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Qarzdorliklar yo‘q',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.inkColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Barcha nasiyalar to‘liq to‘langan yoki qidiruv bo‘yicha topilmadi.',
                          style: TextStyle(color: context.subtextColor, fontSize: 12.5),
                        ),
                      ],
                    ),
                  )
                else if (_viewMode == 0)
                  // 1-REJIM: Cheklar bo'yicha ko'rinish
                  for (final s in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DebtCheckCard(
                        sale: s,
                        onPay: () => _pay(s),
                        onReceipt: () => ReceiptDialog.show(context, s),
                        onReminder: () => _copyReminderText(s),
                      ),
                    )
                else
                  // 2-REJIM: Mijozlar bo'yicha jamlangan ko'rinish
                  ..._buildGroupedByCustomer(list),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _viewToggleBtn(String label, int mode, IconData icon) {
    final sel = _viewMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? (context.isDark ? AppColors.neonLime : AppColors.darkCard) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: sel ? (context.isDark ? AppColors.ink : Colors.white) : context.subtextColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: sel ? (context.isDark ? AppColors.ink : Colors.white) : context.inkColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedByCustomer(List<SaleResult> list) {
    final map = <String, List<SaleResult>>{};
    for (final s in list) {
      final key = s.customerName?.isNotEmpty == true ? s.customerName! : 'Nomsiz Mijozlar';
      map.putIfAbsent(key, () => []).add(s);
    }

    final groups = map.entries.toList();
    // Sort groups by total debt descending
    groups.sort((a, b) {
      final sumA = a.value.fold<double>(0, (acc, item) => acc + item.debt);
      final sumB = b.value.fold<double>(0, (acc, item) => acc + item.debt);
      return sumB.compareTo(sumA);
    });

    return [
      for (final g in groups) ...[
        _CustomerDebtGroupCard(
          customerName: g.key,
          sales: g.value,
          onPay: (s) => _pay(s),
          onReceipt: (s) => ReceiptDialog.show(context, s),
          onSendGroupReminder: () {
            final total = g.value.fold<double>(0, (a, b) => a + b.debt);
            final phone = g.value.firstWhere((s) => s.customerPhone?.isNotEmpty == true, orElse: () => g.value.first).customerPhone;
            _copyCustomerTotalReminder(g.key, phone, total, g.value.length);
          },
        ),
        const SizedBox(height: 12),
      ],
    ];
  }
}

class _DebtsKpiCard extends StatelessWidget {
  const _DebtsKpiCard({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 10.5, color: context.subtextColor, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: context.inkColor),
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

class _DebtCheckCard extends StatelessWidget {
  const _DebtCheckCard({
    required this.sale,
    required this.onPay,
    required this.onReceipt,
    required this.onReminder,
  });

  final SaleResult sale;
  final VoidCallback onPay;
  final VoidCallback onReceipt;
  final VoidCallback onReminder;

  @override
  Widget build(BuildContext context) {
    final paidPercent = (sale.total > 0 ? (sale.paid / sale.total) : 0.0).clamp(0.0, 1.0);
    final itemsSummary = sale.items.map((i) => '${i.productName} (${i.quantity.toStringAsFixed(1)})').join(', ');

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFEF4444).withOpacity(0.12),
                  child: Text(
                    sale.customerName?.isNotEmpty == true ? sale.customerName![0].toUpperCase() : '#',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFEF4444), fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              sale.customerName?.isNotEmpty == true ? sale.customerName! : 'Nomsiz mijoz',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.borderColor.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Chek #${sale.id}',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.subtextColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${sale.customerPhone ?? 'Tel yo‘q'} · ${formatDateTime(sale.createdAt ?? DateTime.now())}',
                        style: TextStyle(fontSize: 11.5, color: context.subtextColor),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(sale.debt),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFFEF4444)),
                    ),
                    Text(
                      'Jami: ${money(sale.total)}',
                      style: TextStyle(fontSize: 11, color: context.subtextColor),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tovarlar ro'yxati qisqacha
          if (itemsSummary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF1B2129) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        itemsSummary,
                        style: TextStyle(fontSize: 11.5, color: context.inkColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // To'lov progressi
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'To‘langan: ${money(sale.paid)} (${(paidPercent * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(fontSize: 11, color: context.subtextColor),
                    ),
                    Text(
                      'Qarz: ${money(sale.debt)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF4444)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: paidPercent,
                    backgroundColor: const Color(0xFFEF4444).withOpacity(0.2),
                    color: const Color(0xFF10B981),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Action tugmalari
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onReminder,
                  icon: const Icon(Icons.send_rounded, size: 14),
                  label: const Text('Eslatma xati (SMS)', style: TextStyle(fontSize: 11.5)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onReceipt,
                  icon: const Icon(Icons.receipt_long_rounded, size: 14),
                  label: const Text('Chek', style: TextStyle(fontSize: 11.5)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                FilledButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.payment_rounded, size: 15),
                  label: const Text('Qarzni to‘lash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.neonLime,
                    foregroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    visualDensity: VisualDensity.compact,
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

class _CustomerDebtGroupCard extends StatefulWidget {
  const _CustomerDebtGroupCard({
    required this.customerName,
    required this.sales,
    required this.onPay,
    required this.onReceipt,
    required this.onSendGroupReminder,
  });

  final String customerName;
  final List<SaleResult> sales;
  final void Function(SaleResult) onPay;
  final void Function(SaleResult) onReceipt;
  final VoidCallback onSendGroupReminder;

  @override
  State<_CustomerDebtGroupCard> createState() => _CustomerDebtGroupCardState();
}

class _CustomerDebtGroupCardState extends State<_CustomerDebtGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final totalDebt = widget.sales.fold<double>(0, (a, b) => a + b.debt);
    final totalSum = widget.sales.fold<double>(0, (a, b) => a + b.total);
    final phone = widget.sales.firstWhere((s) => s.customerPhone?.isNotEmpty == true, orElse: () => widget.sales.first).customerPhone;

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFEF4444).withOpacity(0.12),
              child: Text(
                widget.customerName.isNotEmpty ? widget.customerName[0].toUpperCase() : '#',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFEF4444), fontSize: 18),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  money(totalDebt),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFEF4444)),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    phone != null && phone.isNotEmpty ? phone : 'Telefon raqamsiz',
                    style: TextStyle(fontSize: 12, color: context.subtextColor, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${widget.sales.length} ta chek',
                        style: TextStyle(fontSize: 11, color: context.subtextColor),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '•',
                        style: TextStyle(fontSize: 11, color: context.subtextColor),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Jami xarid: ${money(totalSum)}',
                          style: TextStyle(fontSize: 11, color: context.subtextColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            trailing: Icon(
              _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: context.subtextColor,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onSendGroupReminder,
                  icon: const Icon(Icons.send_rounded, size: 14),
                  label: const Text('Umumiy eslatma (SMS)', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            for (final s in widget.sales)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.isDark ? const Color(0xFF161B22) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chek #${s.id}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          Text(formatDateTime(s.createdAt ?? DateTime.now()), style: TextStyle(fontSize: 11, color: context.subtextColor)),
                        ],
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(money(s.debt), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFEF4444), fontSize: 14)),
                          Text('Jami: ${money(s.total)}', style: TextStyle(fontSize: 11, color: context.subtextColor)),
                        ],
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        tooltip: 'Chekni ko‘rish',
                        onPressed: () => widget.onReceipt(s),
                      ),
                      FilledButton(
                        onPressed: () => widget.onPay(s),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.neonLime,
                          foregroundColor: AppColors.ink,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('To‘lash', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
