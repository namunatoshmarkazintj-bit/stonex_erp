import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';

/// Moliya va Kirim-Chiqimlar bo'limi
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  bool _loading = true;
  String? _error;

  FinanceSummary? _summary;
  MonthlyComparison? _comparison;
  List<RevenueBreakdownItem> _breakdown = [];
  List<FinanceTransaction> _transactions = [];

  int _selectedTab = 0; // 0: Hisobot & Tahlil, 1: Kirim-chiqimlar jurnali

  // Solishtirish davri parametrlari
  String _comparisonPeriodKey = 'current_vs_prev';
  DateTime? _compCurFrom;
  DateTime? _compCurTo;
  DateTime? _compPrevFrom;
  DateTime? _compPrevTo;
  String? _compCurLabel;
  String? _compPrevLabel;
  bool _compLoading = false;

  // Jurnal filtrlari
  String _filterType = 'Barchasi'; // 'Barchasi', 'income', 'expense'
  String _filterCategory = 'Barchasi';
  String _dateFilter = 'bu_oy'; // 'bu_oy', 'hafta', 'bugun', 'barchasi'
  final _searchCtrl = TextEditingController();

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

  DateTime? get _dateFrom {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'bugun':
        return DateTime(now.year, now.month, now.day);
      case 'hafta':
        return now.subtract(Duration(days: now.weekday - 1));
      case 'bu_oy':
        return DateTime(now.year, now.month, 1);
      default:
        return null;
    }
  }

  DateTime? get _dateTo {
    return _dateFilter == 'barchasi' ? null : DateTime.now();
  }

  Future<MonthlyComparison> _fetchComparison(AppRepositories repos) {
    DateTime? curFrom, curTo, prevFrom, prevTo;
    String? curLabel, prevLabel;

    final now = DateTime.now();
    const monthNames = [
      '', 'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun',
      'Iyul', 'Avgust', 'Sentyabr', 'Oktyabr', 'Noyabr', 'Dekabr'
    ];

    if (_comparisonPeriodKey == 'current_vs_prev') {
      // Standart: backend joriy oy va o'tgan oyni hisoblaydi
    } else if (_comparisonPeriodKey == 'prev_vs_before') {
      final lastMonth = DateTime(now.year, now.month - 1, 1);
      final twoMonthsAgo = DateTime(now.year, now.month - 2, 1);
      curFrom = lastMonth;
      curTo = DateTime(now.year, now.month, 0);
      prevFrom = twoMonthsAgo;
      prevTo = DateTime(now.year, now.month - 1, 0);
      curLabel = monthNames[lastMonth.month];
      prevLabel = monthNames[twoMonthsAgo.month];
    } else if (_comparisonPeriodKey == 'last30_vs_prev30') {
      curFrom = now.subtract(const Duration(days: 29));
      curTo = now;
      prevFrom = now.subtract(const Duration(days: 59));
      prevTo = now.subtract(const Duration(days: 30));
      curLabel = 'Oxirgi 30 kun';
      prevLabel = 'Oldingi 30 kun';
    } else if (_comparisonPeriodKey == 'last7_vs_prev7') {
      curFrom = now.subtract(const Duration(days: 6));
      curTo = now;
      prevFrom = now.subtract(const Duration(days: 13));
      prevTo = now.subtract(const Duration(days: 7));
      curLabel = 'Oxirgi 7 kun';
      prevLabel = 'Oldingi 7 kun';
    } else if (_comparisonPeriodKey == 'custom') {
      curFrom = _compCurFrom;
      curTo = _compCurTo;
      prevFrom = _compPrevFrom;
      prevTo = _compPrevTo;
      curLabel = _compCurLabel;
      prevLabel = _compPrevLabel;
    }

    return repos.finance.monthlyComparison(
      curDateFrom: curFrom,
      curDateTo: curTo,
      prevDateFrom: prevFrom,
      prevDateTo: prevTo,
      curLabel: curLabel,
      prevLabel: prevLabel,
    );
  }

  Future<void> _reloadComparison() async {
    setState(() => _compLoading = true);
    try {
      final repos = context.read<AppRepositories>();
      final res = await _fetchComparison(repos);
      if (mounted) {
        setState(() {
          _comparison = res;
          _compLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _compLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Solishtirishni yuklashda xatolik: $e'),
          ),
        );
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repos = context.read<AppRepositories>();
      final results = await Future.wait([
        repos.finance.summary(),
        _fetchComparison(repos),
        repos.finance.revenueBreakdown(dateFrom: _dateFrom, dateTo: _dateTo),
        repos.finance.listTransactions(
          type: _filterType == 'Barchasi' ? null : _filterType,
          category: _filterCategory == 'Barchasi' ? null : _filterCategory,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        ),
      ]);

      if (mounted) {
        setState(() {
          _summary = results[0] as FinanceSummary;
          _comparison = results[1] as MonthlyComparison;
          _breakdown = results[2] as List<RevenueBreakdownItem>;
          _transactions = results[3] as List<FinanceTransaction>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ma’lumotlarni yuklashda xatolik: $e';
          _loading = false;
        });
      }
    }
  }

  String _generateLocalCsv() {
    final buf = StringBuffer();
    buf.writeln('\uFEFF#;Sana;Turi;Kategoriya;To\'lov usuli;Summa (so\'m);Izoh;Mas\'ul');
    var totalIn = 0.0;
    var totalOut = 0.0;
    for (var i = 0; i < _transactions.length; i++) {
      final t = _transactions[i];
      final dt = '${t.date.day.toString().padLeft(2, '0')}.${t.date.month.toString().padLeft(2, '0')}.${t.date.year} ${t.date.hour.toString().padLeft(2, '0')}:${t.date.minute.toString().padLeft(2, '0')}';
      final typeStr = t.isIncome ? 'Kirim' : 'Chiqim';
      final methodStr = t.paymentMethod == 'cash' ? 'Naqd' : (t.paymentMethod == 'card' ? 'Karta' : 'Bank');
      final cleanNote = (t.note ?? '').replaceAll(';', ' ');
      buf.writeln('${i + 1};$dt;$typeStr;${t.category};$methodStr;${t.amount.toInt()};$cleanNote;${t.createdByName ?? ''}');
      if (t.isIncome) {
        totalIn += t.amount;
      } else {
        totalOut += t.amount;
      }
    }
    buf.writeln();
    buf.writeln('MOLIYAVIY XULOSA:');
    buf.writeln('Jami Kirim;${totalIn.toInt()} so\'m');
    buf.writeln('Jami Chiqim;${totalOut.toInt()} so\'m');
    buf.writeln('Sof Foyda;${(totalIn - totalOut).toInt()} so\'m');
    return buf.toString();
  }

  Future<void> _exportExcel() async {
    try {
      final repos = context.read<AppRepositories>();
      String csv = '';
      try {
        csv = await repos.finance.exportCsv(dateFrom: _dateFrom, dateTo: _dateTo);
      } catch (e) {
        debugPrint('Export error from API: $e');
      }

      if (csv.isEmpty || csv.trim() == 'null') {
        csv = _generateLocalCsv();
      }

      if (!csv.startsWith('\uFEFF')) {
        csv = '\uFEFF$csv';
      }

      final now = DateTime.now();
      final defaultFileName = 'Moliya_hisoboti_${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}.csv';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      Uri? savedUri;
      try {
        savedUri = await FilePicker.saveFile(
          dialogTitle: 'Excel hisobotini saqlash joyini tanlang',
          fileName: defaultFileName,
          bytes: bytes,
        );
      } catch (_) {
        savedUri = null;
      }

      // Agar foydalanuvchi oynani bekor qilsa
      if (savedUri == null) {
        return;
      }

      final savedPath = savedUri.scheme == 'file' ? savedUri.toFilePath() : savedUri.path;

      // Desktop tizimlarda faylga to'g'ridan-to'g'ri yozilishini ta'minlash
      try {
        final f = File(savedPath);
        await f.writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint('Fayl yozishda eslatma: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.table_view_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Excel hisoboti muvaffaqiyatli saqlandi!',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        savedPath,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
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
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Eksport qilishda xatolik yuz berdi: $e');
      }
    }
  }

  Future<void> _openAddTransactionDialog({
    String? initialCategory,
    String? initialType,
    bool autoPayAll = false,
  }) async {
    final ok = await FinanceTransactionDialog.show(
      context,
      initialCategory: initialCategory,
      initialType: initialType,
      autoPayAll: autoPayAll,
    );
    if (ok == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sarlavha va Yuqori amallar paneli
              _buildHeader(context, isDark),
              const SizedBox(height: 18),

              // Asosiy KPI Kartalari
              if (_summary != null) ...[
                _buildKpiGrid(context, isDark),
                const SizedBox(height: 20),
              ],

              // Tablar (0: Oylik tahlil & Taqqoslash, 1: Kirim-chiqimlar jurnali)
              _buildTabSelector(context, isDark),
              const SizedBox(height: 16),

              if (_loading)
                Container(
                  padding: const EdgeInsets.all(40),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                )
              else if (_error != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
                      TextButton(onPressed: _loadData, child: const Text('Qayta urinish')),
                    ],
                  ),
                )
              else if (_selectedTab == 0)
                _buildAnalysisTab(context, isDark)
              else
                _buildTransactionsTab(context, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 780;

          final titleRow = Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.neonLime.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: isDark ? AppColors.neonLime : const Color(0xFF2563EB),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Moliya va Hisobotlar',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: context.inkColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kirim-chiqimlar, oylik hisobotlar, o‘tgan oy bilan solishtirish va daromad tahlili',
                      style: TextStyle(fontSize: 12.5, color: context.mutedColor),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = [
            OutlinedButton.icon(
              onPressed: _exportExcel,
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('Excel', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.inkColor,
                side: BorderSide(color: context.borderColor),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openAddTransactionDialog(
                initialCategory: 'Ish haqi / Avans',
                initialType: 'expense',
              ),
              icon: const Icon(Icons.payments_rounded, size: 17),
              label: const Text('Oylik to‘lash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openAddTransactionDialog(),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
              label: const Text('+ Chiqim / Kirim', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
                foregroundColor: isDark ? AppColors.ink : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ];

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleRow,
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: titleRow),
              const SizedBox(width: 14),
              ...actions.map((btn) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: btn,
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiGrid(BuildContext context, bool isDark) {
    final s = _summary!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final isPhone = constraints.maxWidth < 480;
        final cardWidth = isPhone
            ? constraints.maxWidth
            : (isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2);

        final items = [
          _KpiData(
            title: 'Jami Savdo & Tushum',
            value: money(s.revenue),
            subtitle: 'Kassaga tushgan: ${money(s.cashCollected)}',
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF10B981),
          ),
          _KpiData(
            title: 'Jami Chiqimlar',
            value: money(s.expenses),
            subtitle: 'Ish haqi, xom-ashyo, ijara va b.',
            icon: Icons.trending_down_rounded,
            color: const Color(0xFFEF4444),
          ),
          _KpiData(
            title: 'Sof Foyda',
            value: money(s.netProfit),
            subtitle: 'Kirim - Chiqim - Tannarx',
            icon: Icons.auto_awesome_rounded,
            color: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
          ),
          _KpiData(
            title: 'Umumiy Nasiyalar',
            value: money(s.receivables),
            subtitle: 'Mijozlardan kutilayotgan qarzlar',
            icon: Icons.pending_actions_rounded,
            color: const Color(0xFFF59E0B),
          ),
        ];

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((item) {
            return SizedBox(
              width: cardWidth,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, color: item.color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: TextStyle(fontSize: 12, color: context.mutedColor, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(
                            item.value,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: context.inkColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            style: TextStyle(fontSize: 11, color: context.mutedColor),
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
          }).toList(),
        );
      },
    );
  }

  Widget _buildTabSelector(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E232B) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTabPill(
              idx: 0,
              label: '📊 Oylik tahlil & Taqqoslash',
              isDark: isDark,
            ),
            const SizedBox(width: 4),
            _buildTabPill(
              idx: 1,
              label: '📋 Kirim-chiqimlar jurnali',
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill({required int idx, required String label, required bool isDark}) {
    final active = _selectedTab == idx;
    return InkWell(
      onTap: () => setState(() => _selectedTab = idx),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? (isDark ? AppColors.neonLime : Colors.white) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: active
                ? (isDark ? AppColors.ink : const Color(0xFF0F172A))
                : context.mutedColor,
          ),
        ),
      ),
    );
  }

  // TAB 1: OYLIK TAHLIL VA SOLISHTIRISH
  Widget _buildAnalysisTab(BuildContext context, bool isDark) {
    final comp = _comparison;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. O'tgan oy va Bu oy o'rtasida solishtirish
        if (comp != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 620;
                    final titleWidget = Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.compare_arrows_rounded, color: Color(0xFF3B82F6), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _comparisonPeriodKey == 'current_vs_prev'
                                    ? 'O‘tgan oy va bu oy o‘rtasida solishtirish'
                                    : 'Davrlarni solishtirish va dinamika',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: context.inkColor,
                                ),
                              ),
                              Text(
                                '${comp.current.monthName} vs ${comp.previous.monthName} dinamikasi',
                                style: TextStyle(fontSize: 12, color: context.mutedColor),
                              ),
                            ],
                          ),
                        ),
                        if (_compLoading) ...[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ],
                    );

                    final buttonWidget = _buildComparisonPeriodButton(context, isDark);

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          titleWidget,
                          const SizedBox(height: 12),
                          buttonWidget,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: titleWidget),
                        const SizedBox(width: 12),
                        buttonWidget,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),

                // Solishtirish kartalari
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isHorizontalScroll = constraints.maxWidth < 720;
                    final itemW = isHorizontalScroll ? 250.0 : (constraints.maxWidth - 24) / 3;

                    final card1 = SizedBox(
                      width: itemW,
                      child: _buildComparisonCard(
                        title: 'Savdo Tushumi',
                        curVal: comp.current.revenue,
                        prevVal: comp.previous.revenue,
                        growthPct: comp.revenueGrowthPercent,
                        curMonth: comp.current.monthName,
                        prevMonth: comp.previous.monthName,
                        accentColor: const Color(0xFF10B981),
                        icon: Icons.trending_up_rounded,
                        context: context,
                        isDark: isDark,
                      ),
                    );

                    final card2 = SizedBox(
                      width: itemW,
                      child: _buildComparisonCard(
                        title: 'Jami Xarajatlar',
                        curVal: comp.current.expenses,
                        prevVal: comp.previous.expenses,
                        growthPct: comp.expenseGrowthPercent,
                        curMonth: comp.current.monthName,
                        prevMonth: comp.previous.monthName,
                        accentColor: const Color(0xFFEF4444),
                        icon: Icons.trending_down_rounded,
                        context: context,
                        isDark: isDark,
                      ),
                    );

                    final card3 = SizedBox(
                      width: itemW,
                      child: _buildComparisonCard(
                        title: 'Sof Foyda',
                        curVal: comp.current.netProfit,
                        prevVal: comp.previous.netProfit,
                        growthPct: comp.netProfitGrowthPercent,
                        curMonth: comp.current.monthName,
                        prevMonth: comp.previous.monthName,
                        accentColor: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
                        icon: Icons.auto_awesome_rounded,
                        context: context,
                        isDark: isDark,
                        isProfitCard: true,
                      ),
                    );

                    if (isHorizontalScroll) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            card1,
                            const SizedBox(width: 10),
                            card2,
                            const SizedBox(width: 10),
                            card3,
                          ],
                        ),
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        card1,
                        const SizedBox(width: 12),
                        card2,
                        const SizedBox(width: 12),
                        card3,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 2. Nimadan ko'p pul tushdi (Diagramma va Reyting)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.pie_chart_rounded, color: Color(0xFF10B981), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nimadan ko‘p pul tushdi? (Daromad manbalari)',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                        Text(
                          'Tovarlar va toshga ishlov berish xizmatlari bo‘yicha tushumlar taqsimoti',
                          style: TextStyle(fontSize: 12, color: context.mutedColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_breakdown.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: Text('Ushbu davrda tushumlar mavjud emas', style: TextStyle(color: context.mutedColor)),
                )
              else
                Column(
                  children: [
                    for (int i = 0; i < _breakdown.length; i++)
                      _buildBreakdownItem(i + 1, _breakdown[i], context, isDark),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _getComparisonPeriodLabel() {
    switch (_comparisonPeriodKey) {
      case 'prev_vs_before':
        return 'O‘tgan oy vs Undan oldingi';
      case 'last30_vs_prev30':
        return 'Oxirgi 30 kun vs Oldingi 30';
      case 'last7_vs_prev7':
        return 'Oxirgi 7 kun vs Oldingi 7';
      case 'custom':
        if (_compCurLabel != null && _compPrevLabel != null) {
          return '$_compCurLabel vs $_compPrevLabel';
        }
        return 'Ixtiyoriy davr';
      default:
        return 'Joriy oy vs O‘tgan oy';
    }
  }

  PopupMenuItem<String> _buildPeriodMenuItem(
    String value,
    String title,
    IconData icon,
    bool isDark,
  ) {
    final selected = _comparisonPeriodKey == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: selected
                ? (isDark ? AppColors.neonLime : const Color(0xFF0284C7))
                : (isDark ? Colors.white70 : const Color(0xFF64748B)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? (isDark ? AppColors.neonLime : const Color(0xFF0284C7))
                    : (isDark ? Colors.white : const Color(0xFF1E293B)),
              ),
            ),
          ),
          if (selected)
            Icon(
              Icons.check_rounded,
              size: 16,
              color: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
            ),
        ],
      ),
    );
  }

  Widget _buildComparisonPeriodButton(BuildContext context, bool isDark) {
    return PopupMenuButton<String>(
      tooltip: 'Solishtirish davrini tanlash',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E232B) : Colors.white,
      onSelected: (val) {
        if (val == 'custom') {
          _openCustomPeriodDialog(context, isDark);
        } else {
          setState(() {
            _comparisonPeriodKey = val;
          });
          _reloadComparison();
        }
      },
      itemBuilder: (ctx) => [
        _buildPeriodMenuItem('current_vs_prev', 'Joriy oy vs O‘tgan oy', Icons.calendar_today_rounded, isDark),
        _buildPeriodMenuItem('prev_vs_before', 'O‘tgan oy vs Undan oldingi oy', Icons.history_rounded, isDark),
        _buildPeriodMenuItem('last30_vs_prev30', 'Oxirgi 30 kun vs Oldingi 30 kun', Icons.date_range_rounded, isDark),
        _buildPeriodMenuItem('last7_vs_prev7', 'Oxirgi 7 kun vs Oldingi 7 kun', Icons.view_week_rounded, isDark),
        const PopupMenuDivider(),
        _buildPeriodMenuItem('custom', 'Ixtiyoriy davr tanlash...', Icons.edit_calendar_rounded, isDark),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14181F) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 16,
              color: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
            ),
            const SizedBox(width: 8),
            Text(
              _getComparisonPeriodLabel(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: context.inkColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: context.mutedColor),
          ],
        ),
      ),
    );
  }

  Future<void> _openCustomPeriodDialog(BuildContext context, bool isDark) async {
    final now = DateTime.now();

    // Rejim: 0 = Oylar bo'yicha, 1 = Aniq kunlar (Sana oralig'i)
    int selectedMode = 0;

    // Oylar bo'yicha parametrlar
    int year1 = _compCurTo?.year ?? now.year;
    int month1 = _compCurTo?.month ?? now.month;

    int year2 = _compPrevTo?.year ?? (now.month == 1 ? now.year - 1 : now.year);
    int month2 = _compPrevTo?.month ?? (now.month == 1 ? 12 : now.month - 1);

    // Kunlar bo'yicha parametrlar
    DateTime curStart = _compCurFrom ?? DateTime(now.year, now.month, 1);
    DateTime curEnd = _compCurTo ?? now;
    DateTime prevStart = _compPrevFrom ?? (now.month == 1 ? DateTime(now.year - 1, 12, 1) : DateTime(now.year, now.month - 1, 1));
    DateTime prevEnd = _compPrevTo ?? (now.month == 1 ? DateTime(now.year - 1, 12, 31) : DateTime(now.year, now.month, 0));

    const uzMonths = [
      'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun',
      'Iyul', 'Avgust', 'Sentyabr', 'Oktyabr', 'Noyabr', 'Dekabr'
    ];
    const uzMonthsShort = [
      'Yan', 'Fev', 'Mar', 'Apr', 'May', 'Iyun',
      'Iyul', 'Avg', 'Sen', 'Okt', 'Noy', 'Dek'
    ];

    String formatD(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> pickDate({
              required DateTime initial,
              required ValueChanged<DateTime> onPicked,
            }) async {
              final res = await StonexDatePickerDialog.show(
                context: dialogCtx,
                initialDate: initial,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (res != null) {
                setDialogState(() {
                  onPicked(res);
                });
              }
            }

            // Oylar bo'yicha grid qatori
            Widget buildMonthGrid({
              required int selectedMonth,
              required Color activeColor,
              required ValueChanged<int> onSelect,
              int crossAxisCount = 3,
            }) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 12,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: crossAxisCount == 4 ? 2.4 : 2.1,
                ),
                itemBuilder: (c, idx) {
                  final mNum = idx + 1;
                  final isSel = mNum == selectedMonth;
                  return InkWell(
                    onTap: () => onSelect(mNum),
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? activeColor
                            : (isDark ? const Color(0xFF14181F) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSel
                              ? activeColor
                              : (isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1)),
                          width: isSel ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        uzMonthsShort[idx],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                          color: isSel
                              ? (isDark && activeColor == AppColors.neonLime ? AppColors.ink : Colors.white)
                              : (isDark ? Colors.white : const Color(0xFF1E293B)),
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            // Sana tanlash kartochkasi
            Widget buildDateTile({
              required String label,
              required DateTime date,
              required ValueChanged<DateTime> onDateChanged,
            }) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF14181F) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(fontSize: 10.5, color: context.mutedColor, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: () => pickDate(initial: date, onPicked: onDateChanged),
                            borderRadius: BorderRadius.circular(6),
                            child: Row(
                              children: [
                                Icon(Icons.event_rounded, size: 15, color: isDark ? AppColors.neonLime : const Color(0xFF0284C7)),
                                const SizedBox(width: 6),
                                Text(
                                  formatD(date),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: context.inkColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // [-] va [+] tugmalari
                    InkWell(
                      onTap: () => onDateChanged(date.subtract(const Duration(days: 1))),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E232B) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.remove_rounded, size: 14, color: context.inkColor),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => onDateChanged(date.add(const Duration(days: 1))),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E232B) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.add_rounded, size: 14, color: context.inkColor),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Dialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
                  maxHeight: MediaQuery.of(dialogCtx).size.height * 0.9,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Sarlavha va Yopish
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.compare_arrows_rounded, color: Color(0xFF3B82F6), size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Solishtirish davrini tanlash',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: context.inkColor,
                                    ),
                                  ),
                                  Text(
                                    'Ikkita davrni tanlang va dinamikani taqqoslang',
                                    style: TextStyle(fontSize: 11.5, color: context.mutedColor),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              color: context.mutedColor,
                              onPressed: () => Navigator.pop(dialogCtx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Rejim tanlagich (Segmented bar)
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF14181F) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => setDialogState(() => selectedMode = 0),
                                  borderRadius: BorderRadius.circular(9),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selectedMode == 0
                                          ? (isDark ? AppColors.neonLime : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                      boxShadow: selectedMode == 0
                                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.calendar_month_rounded,
                                          size: 15,
                                          color: selectedMode == 0
                                              ? (isDark ? AppColors.ink : const Color(0xFF0F172A))
                                              : context.mutedColor,
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            'Oylar bo‘yicha',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: selectedMode == 0 ? FontWeight.w800 : FontWeight.w600,
                                              color: selectedMode == 0
                                                  ? (isDark ? AppColors.ink : const Color(0xFF0F172A))
                                                  : context.mutedColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () => setDialogState(() => selectedMode = 1),
                                  borderRadius: BorderRadius.circular(9),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selectedMode == 1
                                          ? (isDark ? AppColors.neonLime : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                      boxShadow: selectedMode == 1
                                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.date_range_rounded,
                                          size: 15,
                                          color: selectedMode == 1
                                              ? (isDark ? AppColors.ink : const Color(0xFF0F172A))
                                              : context.mutedColor,
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            'Aniq sanalar',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: selectedMode == 1 ? FontWeight.w800 : FontWeight.w600,
                                              color: selectedMode == 1
                                                  ? (isDark ? AppColors.ink : const Color(0xFF0F172A))
                                                  : context.mutedColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ASOSIY KONTENT: Rejim 0 (Oylar bo'yicha)
                        if (selectedMode == 0) ...[
                          LayoutBuilder(
                            builder: (context, box) {
                              final isNarrow = box.maxWidth < 480;

                              Widget buildCard1() => Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            '1-davr (Yangi):',
                                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.inkColor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Yil steppri
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () => setDialogState(() => year1--),
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: Icon(Icons.chevron_left_rounded, size: 18, color: context.inkColor),
                                              ),
                                            ),
                                            Text(
                                              '$year1',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.inkColor),
                                            ),
                                            InkWell(
                                              onTap: () => setDialogState(() => year1++),
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: Icon(Icons.chevron_right_rounded, size: 18, color: context.inkColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    buildMonthGrid(
                                      selectedMonth: month1,
                                      activeColor: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
                                      onSelect: (m) => setDialogState(() => month1 = m),
                                      crossAxisCount: isNarrow ? 4 : 3,
                                    ),
                                  ],
                                ),
                              );

                              Widget buildVsBadge() => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'VS',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF3B82F6)),
                                ),
                              );

                              Widget buildCard2() => Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            '2-davr (Taqqoslovchi):',
                                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.inkColor),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Yil steppri
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () => setDialogState(() => year2--),
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: Icon(Icons.chevron_left_rounded, size: 18, color: context.inkColor),
                                              ),
                                            ),
                                            Text(
                                              '$year2',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.inkColor),
                                            ),
                                            InkWell(
                                              onTap: () => setDialogState(() => year2++),
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: Icon(Icons.chevron_right_rounded, size: 18, color: context.inkColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    buildMonthGrid(
                                      selectedMonth: month2,
                                      activeColor: const Color(0xFF8B5CF6),
                                      onSelect: (m) => setDialogState(() => month2 = m),
                                      crossAxisCount: isNarrow ? 4 : 3,
                                    ),
                                  ],
                                ),
                              );

                              if (isNarrow) {
                                return Column(
                                  children: [
                                    buildCard1(),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Center(child: buildVsBadge()),
                                    ),
                                    buildCard2(),
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: buildCard1()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 50),
                                    child: buildVsBadge(),
                                  ),
                                  Expanded(child: buildCard2()),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          // Tezkor oylar presetlari
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                label: const Text('Joriy vs O‘tgan oy', style: TextStyle(fontSize: 11)),
                                avatar: const Icon(Icons.flash_on_rounded, size: 14),
                                onPressed: () {
                                  setDialogState(() {
                                    year1 = now.year;
                                    month1 = now.month;
                                    year2 = now.month == 1 ? now.year - 1 : now.year;
                                    month2 = now.month == 1 ? 12 : now.month - 1;
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('O‘tgan oy vs Undan oldingi', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  setDialogState(() {
                                    final p1Month = now.month == 1 ? 12 : now.month - 1;
                                    final p1Year = now.month == 1 ? now.year - 1 : now.year;
                                    final p2Month = p1Month == 1 ? 12 : p1Month - 1;
                                    final p2Year = p1Month == 1 ? p1Year - 1 : p1Year;
                                    year1 = p1Year;
                                    month1 = p1Month;
                                    year2 = p2Year;
                                    month2 = p2Month;
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('O‘tgan yilgi shu oy bilan (YoY)', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  setDialogState(() {
                                    year1 = now.year;
                                    month1 = now.month;
                                    year2 = now.year - 1;
                                    month2 = now.month;
                                  });
                                },
                              ),
                            ],
                          ),
                        ] else ...[
                          // ASOSIY KONTENT: Rejim 1 (Kunbay sanalar)
                          // Tezkor filtrlar
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                label: const Text('Oxirgi 7 kun', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  setDialogState(() {
                                    curStart = now.subtract(const Duration(days: 6));
                                    curEnd = now;
                                    prevStart = now.subtract(const Duration(days: 13));
                                    prevEnd = now.subtract(const Duration(days: 7));
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('Oxirgi 30 kun', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  setDialogState(() {
                                    curStart = now.subtract(const Duration(days: 29));
                                    curEnd = now;
                                    prevStart = now.subtract(const Duration(days: 59));
                                    prevEnd = now.subtract(const Duration(days: 30));
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('Joriy oy boshi — Bugun', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  setDialogState(() {
                                    curStart = DateTime(now.year, now.month, 1);
                                    curEnd = now;
                                    final days = curEnd.difference(curStart).inDays;
                                    prevEnd = curStart.subtract(const Duration(days: 1));
                                    prevStart = prevEnd.subtract(Duration(days: days));
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, box) {
                              final isNarrow = box.maxWidth < 480;

                              Widget buildDateCard1() => Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '1-davr (Asosiy):',
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.inkColor),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${curEnd.difference(curStart).inDays + 1} kun',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    buildDateTile(
                                      label: 'Boshlanish sanasi',
                                      date: curStart,
                                      onDateChanged: (d) => setDialogState(() {
                                        curStart = d;
                                        if (curEnd.isBefore(curStart)) curEnd = curStart;
                                      }),
                                    ),
                                    const SizedBox(height: 6),
                                    buildDateTile(
                                      label: 'Tugash sanasi',
                                      date: curEnd,
                                      onDateChanged: (d) => setDialogState(() {
                                        curEnd = d;
                                        if (curStart.isAfter(curEnd)) curStart = curEnd;
                                      }),
                                    ),
                                  ],
                                ),
                              );

                              Widget buildVsBadge() => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'VS',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF3B82F6)),
                                ),
                              );

                              Widget buildDateCard2() => Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '2-davr (Taqqoslovchi):',
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.inkColor),
                                        ),
                                        InkWell(
                                          onTap: () {
                                            final dur = curEnd.difference(curStart);
                                            setDialogState(() {
                                              prevEnd = curStart.subtract(const Duration(days: 1));
                                              prevStart = prevEnd.subtract(dur);
                                            });
                                          },
                                          child: Text(
                                            'Teng muddat',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    buildDateTile(
                                      label: 'Boshlanish sanasi',
                                      date: prevStart,
                                      onDateChanged: (d) => setDialogState(() {
                                        prevStart = d;
                                        if (prevEnd.isBefore(prevStart)) prevEnd = prevStart;
                                      }),
                                    ),
                                    const SizedBox(height: 6),
                                    buildDateTile(
                                      label: 'Tugash sanasi',
                                      date: prevEnd,
                                      onDateChanged: (d) => setDialogState(() {
                                        prevEnd = d;
                                        if (prevStart.isAfter(prevEnd)) prevStart = prevEnd;
                                      }),
                                    ),
                                  ],
                                ),
                              );

                              if (isNarrow) {
                                return Column(
                                  children: [
                                    buildDateCard1(),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Center(child: buildVsBadge()),
                                    ),
                                    buildDateCard2(),
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: buildDateCard1()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 40),
                                    child: buildVsBadge(),
                                  ),
                                  Expanded(child: buildDateCard2()),
                                ],
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Pastki xulosa va Harakat tugmalari
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF14181F) : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? const Color(0xFF2D3748) : const Color(0xFFBFDBFE),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF3B82F6)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  selectedMode == 0
                                      ? 'Tanlangan: ${uzMonths[month1 - 1]} $year1  vs  ${uzMonths[month2 - 1]} $year2'
                                      : 'Tanlangan: ${formatD(curStart)}—${formatD(curEnd)} vs ${formatD(prevStart)}—${formatD(prevEnd)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.inkColor,
                              side: BorderSide(color: context.borderColor),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Bekor qilish'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              if (selectedMode == 0) {
                                final s1 = DateTime(year1, month1, 1);
                                final e1 = (year1 == now.year && month1 == now.month)
                                    ? now
                                    : DateTime(year1, month1 + 1, 0);

                                final s2 = DateTime(year2, month2, 1);
                                final e2 = DateTime(year2, month2 + 1, 0);

                                final l1 = '${uzMonths[month1 - 1]}${year1 != now.year ? ' $year1' : ''}';
                                final l2 = '${uzMonths[month2 - 1]}${year2 != now.year ? ' $year2' : ''}';

                                setState(() {
                                  _comparisonPeriodKey = 'custom';
                                  _compCurFrom = s1;
                                  _compCurTo = e1;
                                  _compPrevFrom = s2;
                                  _compPrevTo = e2;
                                  _compCurLabel = l1;
                                  _compPrevLabel = l2;
                                });
                              } else {
                                final l1 = '${curStart.day.toString().padLeft(2, '0')}.${curStart.month.toString().padLeft(2, '0')}-${curEnd.day.toString().padLeft(2, '0')}.${curEnd.month.toString().padLeft(2, '0')}';
                                final l2 = '${prevStart.day.toString().padLeft(2, '0')}.${prevStart.month.toString().padLeft(2, '0')}-${prevEnd.day.toString().padLeft(2, '0')}.${prevEnd.month.toString().padLeft(2, '0')}';

                                setState(() {
                                  _comparisonPeriodKey = 'custom';
                                  _compCurFrom = curStart;
                                  _compCurTo = curEnd;
                                  _compPrevFrom = prevStart;
                                  _compPrevTo = prevEnd;
                                  _compCurLabel = l1;
                                  _compPrevLabel = l2;
                                });
                              }
                              _reloadComparison();
                            },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Solishtirish', style: TextStyle(fontWeight: FontWeight.w800)),
                            style: FilledButton.styleFrom(
                              backgroundColor: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
                              foregroundColor: isDark ? AppColors.ink : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          },
        );
      },
    );
  }

  Widget _buildComparisonCard({
    required String title,
    required double curVal,
    required double prevVal,
    required double growthPct,
    required String curMonth,
    required String prevMonth,
    required Color accentColor,
    required IconData icon,
    required BuildContext context,
    required bool isDark,
    bool isProfitCard = false,
    bool isExpenseCard = false,
    double cogs = 0,
    double opExp = 0,
  }) {
    final diff = curVal - prevVal;
    final isPos = growthPct >= 0;
    final isLoss = isProfitCard && curVal < 0;

    final maxVal = [curVal.abs(), prevVal.abs(), 1.0].reduce((a, b) => a > b ? a : b);
    final curRatio = (curVal.abs() / maxVal).clamp(0.06, 1.0);
    final prevRatio = (prevVal.abs() / maxVal).clamp(0.06, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLoss
              ? AppColors.danger.withValues(alpha: 0.5)
              : context.borderColor,
          width: isLoss ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sarlavha va O'sish / Pasayish nishoni
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (isLoss ? AppColors.danger : accentColor).withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isLoss ? Icons.trending_down_rounded : icon,
                  color: isLoss ? AppColors.danger : accentColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: context.inkColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (isPos ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPos ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 13,
                      color: isPos ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${growthPct > 0 ? '+' : ''}${growthPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isPos ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1-Qism: Bu oy (Noyabr / Joriy)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$curMonth (Joriy):',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: isLoss ? const Color(0xFFEF4444) : context.inkColor,
                ),
              ),
              Flexible(
                child: Text(
                  isLoss ? '-${money(curVal.abs())}' : money(curVal),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: isLoss ? const Color(0xFFEF4444) : context.inkColor,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: curRatio,
              minHeight: 6,
              backgroundColor: isDark ? const Color(0xFF14181F) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                isLoss ? const Color(0xFFEF4444) : accentColor,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 2-Qism: O'tgan oy (Oktyabr / O'tgan)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$prevMonth (O‘tgan):',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.mutedColor,
                ),
              ),
              Flexible(
                child: Text(
                  money(prevVal),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.mutedColor,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: prevRatio,
              minHeight: 6,
              backgroundColor: isDark ? const Color(0xFF14181F) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                context.mutedColor.withValues(alpha: 0.4),
              ),
            ),
          ),

          const Divider(height: 16),

          // Aniq izoh va Farq qatori
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14181F) : const Color(0xFFEFF2F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isLoss ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                  size: 14,
                  color: isLoss ? const Color(0xFFEF4444) : context.mutedColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isLoss
                        ? 'Zarar: xarajatlar tushumdan ${money(curVal.abs())} ko‘p'
                        : (isExpenseCard && (cogs > 0 || opExp > 0)
                            ? 'Tannarx: ${money(cogs)} · Chiqim: ${money(opExp)}'
                            : 'Farq: ${diff >= 0 ? '+' : ''}${money(diff)}'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isLoss ? FontWeight.w800 : FontWeight.w600,
                      color: isLoss ? const Color(0xFFEF4444) : context.mutedColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownItem(int rank, RevenueBreakdownItem item, BuildContext context, bool isDark) {
    Color barColor;
    try {
      final hex = item.colorHex.replaceFirst('#', '');
      barColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      barColor = const Color(0xFF10B981);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1-qator: #Rank, Kategoriya to'liq nomi va Foiz
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank == 1
                      ? const Color(0xFFF59E0B)
                      : (isDark ? const Color(0xFF28313E) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: rank == 1 ? Colors.white : context.mutedColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.category,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: context.inkColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 2-qator: Savdolar soni va Summa
          Row(
            children: [
              const SizedBox(width: 34),
              if (item.count > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF28313E) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${item.count} ta savdo',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.mutedColor),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                money(item.amount),
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: context.inkColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (item.percentage / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: isDark ? const Color(0xFF14181F) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  // TAB 2: KIRIM-CHIQIMLAR JURNALI
  Widget _buildTransactionsTab(BuildContext context, bool isDark) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _transactions.where((t) {
      if (query.isNotEmpty) {
        final matchNote = (t.note ?? '').toLowerCase().contains(query);
        final matchCat = t.category.toLowerCase().contains(query);
        final matchCreator = (t.createdByName ?? '').toLowerCase().contains(query);
        if (!matchNote && !matchCat && !matchCreator) return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filtrlar paneli
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Qidiruv
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Izoh, kategoriya yoki mas’ul bo‘yicha qidiruv...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Turi bo'yicha filter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filterType,
                        items: const [
                          DropdownMenuItem(value: 'Barchasi', child: Text('Barcha amallar')),
                          DropdownMenuItem(value: 'income', child: Text('Faqat Kirimlar')),
                          DropdownMenuItem(value: 'expense', child: Text('Faqat Chiqimlar')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _filterType = val);
                            _loadData();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Sana oralig'i
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _dateFilter,
                        items: const [
                          DropdownMenuItem(value: 'bu_oy', child: Text('Shu oy')),
                          DropdownMenuItem(value: 'hafta', child: Text('Shu hafta')),
                          DropdownMenuItem(value: 'bugun', child: Text('Bugun')),
                          DropdownMenuItem(value: 'barchasi', child: Text('Barcha davr')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _dateFilter = val);
                            _loadData();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Operatsiyalar ro'yxati
        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_rounded, size: 48, color: context.mutedColor),
                const SizedBox(height: 10),
                Text('Ushbu filtrlar bo‘yicha operatsiyalar topilmadi', style: TextStyle(color: context.mutedColor)),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => Divider(height: 1, thickness: 0.8, color: context.borderColor),
              itemBuilder: (context, idx) {
                final t = filtered[idx];
                final isInc = t.isIncome;
                final dt = '${t.date.day.toString().padLeft(2, '0')}.${t.date.month.toString().padLeft(2, '0')}.${t.date.year} ${t.date.hour.toString().padLeft(2, '0')}:${t.date.minute.toString().padLeft(2, '0')}';
                final methodLabel = t.paymentMethod == 'cash' ? 'Naqd' : (t.paymentMethod == 'card' ? 'Karta' : 'Bank');

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // Kirim / Chiqim belgisi
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: (isInc ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isInc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: isInc ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Tafsilotlar
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  t.category,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: context.inkColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF28313E) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    methodLabel,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.mutedColor),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${t.note ?? 'Izohsiz'} · ${t.createdByName ?? 'Admin'}',
                              style: TextStyle(fontSize: 11.5, color: context.mutedColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Sana va Summa
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isInc ? '+' : '-'} ${money(t.amount)}',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: isInc ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(dt, style: TextStyle(fontSize: 11, color: context.mutedColor)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _KpiData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

/// Yangi Kirim yoki Chiqim qo'shish oynasi (shu jumladan barchaga yoki individual xodimlarga oylik to'lash)
class FinanceTransactionDialog extends StatefulWidget {
  final String? initialCategory;
  final String? initialType;
  final bool autoPayAll;
  final int? initialUserId;
  final double? initialAmount;

  const FinanceTransactionDialog({
    super.key,
    this.initialCategory,
    this.initialType,
    this.autoPayAll = false,
    this.initialUserId,
    this.initialAmount,
  });

  static Future<bool?> show(
    BuildContext context, {
    String? initialCategory,
    String? initialType,
    bool autoPayAll = false,
    int? initialUserId,
    double? initialAmount,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => FinanceTransactionDialog(
        initialCategory: initialCategory,
        initialType: initialType,
        autoPayAll: autoPayAll,
        initialUserId: initialUserId,
        initialAmount: initialAmount,
      ),
    );
  }

  @override
  State<FinanceTransactionDialog> createState() => _FinanceTransactionDialogState();
}

class _FinanceTransactionDialogState extends State<FinanceTransactionDialog> {
  late String _type; // 'expense' yoki 'income'
  late String _category;
  String _paymentMethod = 'cash';
  final DateTime _date = DateTime.now();

  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final Map<int, TextEditingController> _employeeAmountCtrls = {};

  bool _saving = false;
  String? _error;

  List<AppUser> _allEmployees = [];
  Map<int, SalaryReportItem> _salaryReportMap = {};
  final Set<int> _selectedUserIds = {};
  bool _loadingEmployees = false;

  final List<String> _expenseCategories = [
    'Ish haqi / Avans',
    'Mukofot / Bonus',
    'Xom-ashyo (granit bloklar)',
    'Ijara to‘lovi',
    'Kommunal / Elektr',
    'Transport / Yoqilg‘i',
    'Uskunalar ta’miri',
    'Boshqa chiqimlar',
  ];

  final List<String> _incomeCategories = [
    'Qo‘shimcha investitsiya',
    'Qarz qaytarilishi',
    'Boshqa kirim',
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? 'expense';
    _category = widget.initialCategory ?? 'Ish haqi / Avans';
    _loadEmployees();
  }

  TextEditingController _getEmployeeCtrl(AppUser u) {
    if (!_employeeAmountCtrls.containsKey(u.id)) {
      _employeeAmountCtrls[u.id] = TextEditingController(
        text: u.salary > 0 ? u.salary.toInt().toString() : '',
      );
    }
    return _employeeAmountCtrls[u.id]!;
  }

  void _recalculateTotalFromEmployees() {
    double total = 0;
    for (final u in _employees) {
      if (_selectedUserIds.contains(u.id)) {
        final ctrl = _getEmployeeCtrl(u);
        final amt = double.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        total += amt;
      }
    }
    if (total > 0) {
      _amountCtrl.text = total.toInt().toString();
    } else if (_selectedUserIds.isEmpty) {
      _amountCtrl.clear();
    }
    setState(() {});
  }

  double getEarnedSoFar(AppUser u) {
    final rep = _salaryReportMap[u.id];
    if (rep != null && rep.calculatedSalary > 0) {
      return rep.calculatedSalary;
    }
    if (rep != null && rep.netSalary > 0) {
      return rep.netSalary;
    }
    if (u.salary <= 0) return 0;

    // Davomat yozilmagan bo'lsa: Joriy oyda bugungacha bo'lgan ish kunlari hisobi bo'yicha
    final now = DateTime.now();
    int passedWorkDays = 0;
    for (int d = 1; d <= now.day; d++) {
      final dt = DateTime(now.year, now.month, d);
      if (dt.weekday != DateTime.sunday) {
        passedWorkDays++;
      }
    }
    passedWorkDays = passedWorkDays.clamp(1, 26);
    final earned = (u.salary / 26) * passedWorkDays;
    return ((earned / 1000).round() * 1000).toDouble();
  }

  double getPaidSoFar(AppUser u) {
    final rep = _salaryReportMap[u.id];
    return rep?.paidAmount ?? 0.0;
  }

  double getRemainingSoFar(AppUser u) {
    final rep = _salaryReportMap[u.id];
    if (rep != null) {
      return rep.remainingSalary;
    }
    return getEarnedSoFar(u);
  }

  int getDaysWorkedSoFar(AppUser u) {
    final rep = _salaryReportMap[u.id];
    if (rep != null && rep.daysWorked > 0) {
      return rep.daysWorked;
    }
    final now = DateTime.now();
    int passedWorkDays = 0;
    for (int d = 1; d <= now.day; d++) {
      final dt = DateTime(now.year, now.month, d);
      if (dt.weekday != DateTime.sunday) {
        passedWorkDays++;
      }
    }
    return passedWorkDays.clamp(1, 26);
  }

  void _payAllEmployeesEarnedSalary() {
    setState(() {
      _selectedUserIds.clear();
      for (final u in _employees) {
        _selectedUserIds.add(u.id);
        final ctrl = _getEmployeeCtrl(u);
        final rem = getRemainingSoFar(u);
        ctrl.text = rem > 0 ? rem.toInt().toString() : '0';
      }
    });
    _recalculateTotalFromEmployees();
  }

  void _payAllEmployeesFullSalary() {
    setState(() {
      _selectedUserIds.clear();
      for (final u in _employees) {
        _selectedUserIds.add(u.id);
        final ctrl = _getEmployeeCtrl(u);
        ctrl.text = u.salary > 0 ? u.salary.toInt().toString() : '0';
      }
    });
    _recalculateTotalFromEmployees();
  }

  void _clearEmployeeSelection() {
    setState(() {
      _selectedUserIds.clear();
      _amountCtrl.clear();
    });
  }

  Future<void> _loadEmployees() async {
    setState(() => _loadingEmployees = true);
    final repos = context.read<AppRepositories>();
    try {
      final users = await repos.users.list();
      if (mounted) {
        setState(() {
          _allEmployees = users;
        });
        for (final u in users) {
          _getEmployeeCtrl(u);
        }
      }
    } catch (_) {}

    try {
      final now = DateTime.now();
      final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final reps = await repos.attendance.getSalaryReport(month: monthStr);
      if (mounted) {
        setState(() {
          _salaryReportMap = {for (final r in reps) r.userId: r};
          _loadingEmployees = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingEmployees = false);
      }
    }

    if (widget.autoPayAll) {
      _payAllEmployeesEarnedSalary();
    } else if (widget.initialUserId != null) {
      _selectedUserIds.clear();
      for (final u in _employees) {
        if (u.id == widget.initialUserId) {
          _selectedUserIds.add(u.id);
          final ctrl = _getEmployeeCtrl(u);
          if (widget.initialAmount != null && widget.initialAmount! > 0) {
            ctrl.text = widget.initialAmount!.toInt().toString();
          } else {
            final rem = getRemainingSoFar(u);
            ctrl.text = rem > 0 ? rem.toInt().toString() : '';
          }
          break;
        }
      }
      _recalculateTotalFromEmployees();
    }
  }

  List<AppUser> get _employees {
    final list = _allEmployees.isNotEmpty
        ? _allEmployees
        : const [
            AppUser(id: 1, username: 'bobur', fullName: 'Bobur Yoqubov', role: Role.ishchi, salary: 4500000),
            AppUser(id: 2, username: 'alisher', fullName: 'Alisher Saidov', role: Role.ishchi, salary: 4200000),
            AppUser(id: 3, username: 'aziz', fullName: 'Aziz Kassir', role: Role.kassir, salary: 4000000),
            AppUser(id: 4, username: 'jamshid', fullName: 'Jamshid Haydovchi', role: Role.haydovchi, salary: 3800000),
            AppUser(id: 5, username: 'nodir', fullName: 'Nodir Boshqaruvchi', role: Role.ishBoshqaruvchi, salary: 6000000),
          ];
    // Xo'jayinga (admin) oylik to'lanmaydi
    return list.where((u) => u.role != Role.admin).toList();
  }

  double get _totalSelectedSalaries {
    double sum = 0;
    for (final u in _employees) {
      if (_selectedUserIds.contains(u.id)) {
        final ctrl = _getEmployeeCtrl(u);
        final amt = double.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        sum += amt;
      }
    }
    return sum;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    for (final c in _employeeAmountCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addQuickAmount(int add) {
    final cur = (int.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) + add;
    _amountCtrl.text = cur.toString();
    setState(() {});
  }

  Future<void> _save() async {
    final isSalary = _type == 'expense' &&
        (_category.toLowerCase().contains('ish haqi') ||
            _category.toLowerCase().contains('oylik') ||
            _category.toLowerCase().contains('avans'));

    // Xodimlar tanlangan bo'lsa: Har bir xodim uchun alohida tranzaksiya yoziladi
    if (isSalary && _selectedUserIds.isNotEmpty) {
      final itemsToPay = <(AppUser, double)>[];
      for (final u in _employees) {
        if (_selectedUserIds.contains(u.id)) {
          final ctrl = _getEmployeeCtrl(u);
          var amt = double.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          if (amt == 0 && _selectedUserIds.length == 1) {
            amt = double.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          }
          if (amt > 0) {
            itemsToPay.add((u, amt));
          }
        }
      }

      if (itemsToPay.isEmpty) {
        setState(() => _error = 'Kamida bitta xodim uchun to‘lov miqdorini kiriting (0 dan katta bo‘lsin)');
        return;
      }

      setState(() {
        _saving = true;
        _error = null;
      });

      try {
        final repos = context.read<AppRepositories>();
        final customNote = _noteCtrl.text.trim();

        for (final item in itemsToPay) {
          final user = item.$1;
          final empAmount = item.$2;
          final mStr = '${_date.year}-${_date.month.toString().padLeft(2, '0')}';
          final note = customNote.isEmpty
              ? 'Ish haqi / Avans: ${user.fullName} ($mStr)'
              : 'Ish haqi / Avans: ${user.fullName} ($mStr) — $customNote';

          await repos.finance.addTransaction(
            FinanceTransaction(
              id: 0,
              type: 'expense',
              category: _category,
              amount: empAmount,
              paymentMethod: _paymentMethod,
              note: note,
              date: _date,
            ),
          );

          // Oylik to'langandan keyin to'langan deb belgilash
          try {
            final mStr = '${_date.year}-${_date.month.toString().padLeft(2, '0')}';
            await repos.attendance.paySalary(user.id, mStr, empAmount);
          } catch (_) {}
        }

        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Saqlashda xatolik: $e';
            _saving = false;
          });
        }
      }
      return;
    }

    // Standart yagona tranzaksiya
    final amount = double.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Iltimos, to‘g‘ri miqdor kiriting');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repos = context.read<AppRepositories>();
      final noteText = _noteCtrl.text.trim();
      await repos.finance.addTransaction(
        FinanceTransaction(
          id: 0,
          type: _type,
          category: _category,
          amount: amount,
          paymentMethod: _paymentMethod,
          note: noteText.isEmpty ? null : noteText,
          date: _date,
        ),
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Saqlashda xatolik: $e';
          _saving = false;
        });
      }
    }
  }

  Widget _buildEmployeeSelector(BuildContext context, bool isDark) {
    final list = _employees;
    final totalSalary = _totalSelectedSalaries;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14181F) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sarlavha paneli
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.payments_rounded,
                  size: 16,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xodimlarni tanlang (Bir yoki bir nechtasini):',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: context.inkColor,
                      ),
                    ),
                    Text(
                      'Har bir xodimga alohida miqdor belgilashingiz yoki birdaniga to‘lashingiz mumkin',
                      style: TextStyle(fontSize: 11, color: context.mutedColor),
                    ),
                  ],
                ),
              ),
              if (_selectedUserIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_selectedUserIds.length} ta tanlandi',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Tezkor harakatlar tugmalari
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Barchasiga hozirgacha ishlagan / qoldiq haqini to'lash (Asosiy qulay tugma)
              FilledButton.icon(
                onPressed: _payAllEmployeesEarnedSalary,
                icon: const Icon(Icons.work_history_rounded, size: 15),
                label: const Text('Ishlagan haqini to‘lash', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(
                  backgroundColor: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                  foregroundColor: isDark ? AppColors.ink : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              // Barchasiga to'liq oylik to'lash tugmasi (Secondary)
              OutlinedButton.icon(
                onPressed: _payAllEmployeesFullSalary,
                icon: const Icon(Icons.flash_on_rounded, size: 15),
                label: const Text('Barchasiga to‘liq oylik to‘lash', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.inkColor,
                  side: BorderSide(color: context.borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (_selectedUserIds.isNotEmpty)
                TextButton.icon(
                  onPressed: _clearEmployeeSelection,
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: const Text('Tozalash', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_loadingEmployees)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            // Xodimlar ro'yxati (Scrollable)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, index) {
                  final u = list[index];
                  final isSelected = _selectedUserIds.contains(u.id);
                  final ctrl = _getEmployeeCtrl(u);
                  final earned = getEarnedSoFar(u);
                  final daysWorked = getDaysWorkedSoFar(u);
                  final paid = getPaidSoFar(u);
                  final remaining = getRemainingSoFar(u);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark ? const Color(0xFF1B2A23) : const Color(0xFFF0FDF4))
                          : (isDark ? const Color(0xFF1E232B) : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF10B981)
                            : (isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0)),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Xodim asosiy qatori (Avatar, Ism, Lavozim va Tanlash holati)
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedUserIds.remove(u.id);
                              } else {
                                _selectedUserIds.add(u.id);
                                if (_amountCtrl.text.isNotEmpty && _selectedUserIds.length == 1) {
                                  ctrl.text = _amountCtrl.text;
                                }
                              }
                            });
                            _recalculateTotalFromEmployees();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                activeColor: const Color(0xFF10B981),
                                checkColor: Colors.white,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedUserIds.add(u.id);
                                      if (_amountCtrl.text.isNotEmpty && _selectedUserIds.length == 1) {
                                        ctrl.text = _amountCtrl.text;
                                      }
                                    } else {
                                      _selectedUserIds.remove(u.id);
                                    }
                                  });
                                  _recalculateTotalFromEmployees();
                                },
                              ),
                              const SizedBox(width: 4),
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isSelected
                                    ? const Color(0xFF10B981).withValues(alpha: 0.25)
                                    : (isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0)),
                                child: Text(
                                  u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? const Color(0xFF10B981) : context.inkColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            u.fullName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                              color: context.inkColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            u.role.label,
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.mutedColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      u.salary > 0 ? 'Stavka: ${money(u.salary)} / oy' : 'Stavka belgilanmagan',
                                      style: TextStyle(fontSize: 10.5, color: context.mutedColor, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (!isSelected)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '+ Tanlash',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.inkColor),
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: Color(0xFF10B981),
                                ),
                            ],
                          ),
                        ),

                        // 2. Aniq 3 ustunli moliyaviy hisobot paneli (Yozuvlar aralashib ketmaydi!)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF14181F) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.borderColor.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            children: [
                              // 1-ustun: Ishlagani
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ishlagani: ($daysWorked kun)',
                                      style: TextStyle(fontSize: 9.5, color: context.mutedColor, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      money(earned),
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.inkColor),
                                    ),
                                  ],
                                ),
                              ),
                              Container(width: 1, height: 24, color: context.borderColor.withValues(alpha: 0.7)),
                              // 2-ustun: To'langan (Avans)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'To‘langan',
                                        style: TextStyle(fontSize: 9.5, color: context.mutedColor, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        paid > 0 ? money(paid) : '0 so‘m',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: paid > 0 ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)) : context.mutedColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 24, color: context.borderColor.withValues(alpha: 0.7)),
                              // 3-ustun: Qoldiq maosh
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Qoldiq',
                                        style: TextStyle(fontSize: 9.5, color: context.mutedColor, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        remaining > 0 ? money(remaining) : (paid > 0 ? 'To‘liq to‘langan' : '0 so‘m'),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w900,
                                          color: remaining > 0
                                              ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                              : (paid > 0 ? const Color(0xFF10B981) : context.mutedColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 3. Agar tanlangan bo'lsa: Qulay to'lov va tezkor tanlash maydoni
                        if (isSelected) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF13171E) : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Qator 1: To'lov miqdorini kiritish
                                Row(
                                  children: [
                                    Icon(
                                      Icons.payments_rounded,
                                      size: 16,
                                      color: isDark ? AppColors.neonLime : const Color(0xFF10B981),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'To‘lov / Avans summasi:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: context.inkColor,
                                      ),
                                    ),
                                    const Spacer(),
                                    SizedBox(
                                      width: 145,
                                      height: 35,
                                      child: TextField(
                                        controller: ctrl,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w900,
                                          color: context.inkColor,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          suffixText: "so'm",
                                          suffixStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.mutedColor),
                                          hintText: remaining > 0 ? money(remaining) : (earned > 0 ? money(earned) : "0"),
                                          filled: true,
                                          fillColor: isDark ? const Color(0xFF1E232B) : const Color(0xFFF8FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: context.borderColor),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: context.borderColor),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                                          ),
                                        ),
                                        onChanged: (val) => _recalculateTotalFromEmployees(),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Qator 2: Tezkor tugmalar (Presets)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (remaining > 0)
                                      InkWell(
                                        onTap: () {
                                          ctrl.text = remaining.toInt().toString();
                                          _recalculateTotalFromEmployees();
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.check_rounded, size: 12, color: Color(0xFF10B981)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Qoldiq (${money(remaining)})',
                                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (earned > 0 && earned != remaining)
                                      InkWell(
                                        onTap: () {
                                          ctrl.text = earned.toInt().toString();
                                          _recalculateTotalFromEmployees();
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                                          ),
                                          child: const Text('Ishlagan haqi', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF3B82F6))),
                                        ),
                                      ),
                                    if (u.salary > 0) ...[
                                      InkWell(
                                        onTap: () {
                                          ctrl.text = (u.salary * 0.5).toInt().toString();
                                          _recalculateTotalFromEmployees();
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                                          ),
                                          child: const Text('50% avans', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF6366F1))),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          ctrl.text = u.salary.toInt().toString();
                                          _recalculateTotalFromEmployees();
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text('To‘liq stavka', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );                },
              ),
            ),

          // Jami oylik xulosa kartasi
          if (_selectedUserIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_selectedUserIds.length} ta xodim uchun jami to‘lov:',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                    ),
                  ),
                  Text(
                    money(totalSalary),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
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
    final isDark = context.isDark;
    final isExpense = _type == 'expense';
    final isSalary = isExpense &&
        (_category.toLowerCase().contains('ish haqi') ||
            _category.toLowerCase().contains('oylik') ||
            _category.toLowerCase().contains('avans'));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 580,
        decoration: BoxDecoration(
          color: context.dialogBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sarlavha
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (isExpense ? const Color(0xFFEF4444) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isExpense ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                      color: isExpense ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isExpense ? 'Chiqim kiritish (Xarajat)' : 'Kirim kiritish (Tushum)',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                        Text(
                          'Moliya kassasi uchun yangi operatsiya',
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
            const Divider(height: 1, thickness: 1),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                      ),

                    // Turi: Chiqim vs Kirim
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E232B) : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _type = 'expense';
                                  _category = _expenseCategories.first;
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isExpense ? (isDark ? const Color(0xFF2E3846) : Colors.white) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Chiqim (Xarajat)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: isExpense ? const Color(0xFFEF4444) : context.mutedColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _type = 'income';
                                  _category = _incomeCategories.first;
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: !isExpense ? (isDark ? const Color(0xFF2E3846) : Colors.white) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Kirim (Qo‘shimcha)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: !isExpense ? const Color(0xFF10B981) : context.mutedColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Kategoriya
                    Text('Kategoriya:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: context.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _category,
                          isExpanded: true,
                          items: (isExpense ? _expenseCategories : _incomeCategories).map((c) {
                            return DropdownMenuItem(value: c, child: Text(c, style: TextStyle(fontWeight: FontWeight.w700, color: context.inkColor)));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _category = val);
                          },
                        ),
                      ),
                    ),
                    if (isSalary) ...[
                      const SizedBox(height: 16),
                      _buildEmployeeSelector(context, isDark),
                    ],
                    const SizedBox(height: 16),

                    // To'lov miqdori
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          isSalary && _selectedUserIds.isNotEmpty ? 'Jami to‘lov miqdori (so‘m):' : 'To‘lov miqdori (so‘m):',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor),
                        ),
                        if (isSalary && _selectedUserIds.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Xodimlar hisobi bo‘yicha',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isSalary && _selectedUserIds.isNotEmpty ? const Color(0xFF10B981) : context.inkColor,
                      ),
                      onChanged: (val) {
                        if (isSalary && _selectedUserIds.length == 1) {
                          final singleUser = _employees.firstWhere((e) => _selectedUserIds.contains(e.id));
                          _getEmployeeCtrl(singleUser).text = val;
                        }
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: '0',
                        suffixText: "so'm",
                        filled: true,
                        fillColor: context.cardColor,
                        helperText: isSalary && _selectedUserIds.isNotEmpty
                            ? 'Ushbu to‘lov yuqoridagi xodimlar uchun kiritilgan hisoblar yig‘indisidan olinadi.'
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                      ),
                    ),
                    if (!(isSalary && _selectedUserIds.isNotEmpty)) ...[
                      const SizedBox(height: 8),

                      // Tezkor summa tugmalari
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final chip in [
                            (label: '+100k', val: 100000),
                            (label: '+500k', val: 500000),
                            (label: '+1 mln', val: 1000000),
                            (label: '+5 mln', val: 5000000),
                          ])
                            InkWell(
                              onTap: () => _addQuickAmount(chip.val),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E232B) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: context.borderColor),
                                ),
                                child: Text(chip.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.inkColor)),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    // To'lov usuli
                    Text('To‘lov usuli:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final m in [
                          (key: 'cash', label: 'Naqd pul', icon: Icons.payments_rounded),
                          (key: 'card', label: 'Plastik karta', icon: Icons.credit_card_rounded),
                          (key: 'bank', label: 'Bank o‘tkazmasi', icon: Icons.account_balance_rounded),
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                onTap: () => setState(() => _paymentMethod = m.key),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _paymentMethod == m.key
                                        ? (isDark ? AppColors.neonLime.withValues(alpha: 0.15) : const Color(0xFFEFF6FF))
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _paymentMethod == m.key
                                          ? (isDark ? AppColors.neonLime : const Color(0xFF3B82F6))
                                          : context.borderColor,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        m.icon,
                                        size: 18,
                                        color: _paymentMethod == m.key
                                            ? (isDark ? AppColors.neonLime : const Color(0xFF3B82F6))
                                            : context.mutedColor,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        m.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _paymentMethod == m.key
                                              ? context.inkColor
                                              : context.mutedColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Izoh
                    Text('Izoh / Asos:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _noteCtrl,
                      decoration: InputDecoration(
                        hintText: 'Operatsiya sababi yoki hujjati haqida qisqacha izoh...',
                        filled: true,
                        fillColor: context.cardColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // Tugmalar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text('Bekor qilish', style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.shrink()
                        : const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? AppColors.ink : Colors.white),
                          )
                        : const Text('Kiritish', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(
                      backgroundColor: isExpense
                          ? const Color(0xFFEF4444)
                          : (isDark ? AppColors.neonLime : const Color(0xFF10B981)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
