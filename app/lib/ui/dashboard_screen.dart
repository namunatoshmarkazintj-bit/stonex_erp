import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';
import 'production_screen.dart';
import 'stock_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onNavigate, this.searchCtrl});
  final void Function(int index)? onNavigate;
  final TextEditingController? searchCtrl;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<
      ({
        FinanceSummary finance,
        List<Product> products,
        List<ProductionTask> tasks,
        List<SaleResult> sales,
        List<StockMovementRecord> movements,
      })> _future;
  String _selectedCategory = 'Barchasi';
  String _selectedPeriod = 'Oylik';
  String _selectedTopPeriod = 'Oylik';
  String _selectedTag = 'Barchasi';
  int? _chartHoverIndex;

  @override
  void initState() {
    super.initState();
    _future = _fetchData();
    widget.searchCtrl?.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.searchCtrl?.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<
      ({
        FinanceSummary finance,
        List<Product> products,
        List<ProductionTask> tasks,
        List<SaleResult> sales,
        List<StockMovementRecord> movements,
      })> _fetchData() {
    final repos = context.read<AppRepositories>();
    return Future.wait([
      repos.finance.summary(),
      repos.products.list(),
      repos.production.list(),
      repos.sales.listSales(limit: 200),
      repos.stock.movements().catchError((_) => <StockMovementRecord>[]),
    ]).then((results) => (
          finance: results[0] as FinanceSummary,
          products: results[1] as List<Product>,
          tasks: results[2] as List<ProductionTask>,
          sales: results[3] as List<SaleResult>,
          movements: results[4] as List<StockMovementRecord>,
        ));
  }

  void _reload() {
    if (!mounted) return;
    final next = _fetchData();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
        ({
          FinanceSummary finance,
          List<Product> products,
          List<ProductionTask> tasks,
          List<SaleResult> sales,
          List<StockMovementRecord> movements,
        })>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: snap.error.toString(), onRetry: _reload);
        }

        final data = snap.data!;
        final f = data.finance;
        final products = data.products;
        final tasks = data.tasks;
        final sales = data.sales;
        final movements = data.movements;

        final searchQ = widget.searchCtrl?.text.trim().toLowerCase() ?? '';
        var displayProducts = products;
        var displaySales = sales;

        if (searchQ.isNotEmpty) {
          displayProducts = displayProducts.where((p) {
            return p.name.toLowerCase().contains(searchQ) ||
                p.sku.toLowerCase().contains(searchQ) ||
                p.qrCode.toLowerCase().contains(searchQ);
          }).toList();
          displaySales = displaySales.where((s) {
            final name = (s.customerName ?? '').toLowerCase();
            final phone = (s.customerPhone ?? '').toLowerCase();
            return name.contains(searchQ) ||
                phone.contains(searchQ) ||
                s.id.toString() == searchQ;
          }).toList();
        }

        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _future;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 1024;
              final isTablet =
                  constraints.maxWidth >= 720 && constraints.maxWidth < 1024;
              final padH = isDesktop ? 28.0 : (isTablet ? 18.0 : 12.0);

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(padH, 6, padH, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Yuqori 4 ta Karta qatori (Mockupdagi Row 1)
                    _buildTopStatsRow(
                      f: f,
                      sales: sales,
                      products: products,
                      isDesktop: isDesktop,
                      isTablet: isTablet,
                    ),

                    const SizedBox(
                        height:
                            20), // 2. O‘rta bo‘lim: Dinamika grafigi + Mahsulotlar jadvali (Sinxron balandlikda simmetrik)
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildStockWaveChartCard(
                              f,
                              products,
                              sales,
                              movements,
                              height: 440,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 4,
                            child: _buildTagsAndStockTableCard(
                              displayProducts,
                              height: 440,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildStockWaveChartCard(f, products, sales, movements),
                      const SizedBox(height: 16),
                      _buildTagsAndStockTableCard(displayProducts),
                    ],

                    const SizedBox(height: 18),

                    // 3. Pastki bo‘lim: 3 ta karta (Sinxron balandlikda simmetrik)
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: _buildRecentOrdersCard(
                              f,
                              displaySales,
                              height: 390,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
                            child: _buildRestockAiCard(
                              products,
                              sales,
                              height: 390,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
                            child: _buildTasksQueueCard(
                              tasks,
                              height: 390,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildRecentOrdersCard(f, displaySales),
                      const SizedBox(height: 16),
                      _buildRestockAiCard(products, sales),
                      const SizedBox(height: 16),
                      _buildTasksQueueCard(tasks),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Yuqori 4 ta Karta qatori (Moliyaviy ko'rsatkichlar & Davr filtri)
  // ---------------------------------------------------------------------------

  ({
    double revenue,
    double cash,
    double debt,
    double profit,
    double margin,
    int salesCount,
    int debtCount,
    double prevRevenue,
    double prevProfit,
  }) _getPeriodFinanceStats({
    required FinanceSummary f,
    required List<SaleResult> sales,
    required List<Product> products,
    required String period,
  }) {
    if (period == 'Barchasi') {
      final margin = f.revenue > 0 ? (f.netProfit / f.revenue * 100) : 33.7;
      final debtCount = sales.where((s) => s.debt > 0).length;
      return (
        revenue: f.revenue,
        cash: f.cashCollected,
        debt: f.receivables,
        profit: f.netProfit,
        margin: margin,
        salesCount: sales.length,
        debtCount: debtCount,
        prevRevenue: 0.0,
        prevProfit: 0.0,
      );
    }

    final now = DateTime.now();
    DateTime filterStart;
    final filterEnd = now.add(const Duration(minutes: 5));
    DateTime prevStart;
    DateTime prevEnd;

    if (period == 'Bugun') {
      filterStart = DateTime(now.year, now.month, now.day);
      prevStart = DateTime(now.year, now.month, now.day - 1);
      prevEnd = filterStart;
    } else if (period == 'Haftalik') {
      filterStart = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      prevStart = filterStart.subtract(const Duration(days: 7));
      prevEnd = filterStart;
    } else if (period == 'Oylik') {
      filterStart = DateTime(now.year, now.month, 1);
      prevStart = DateTime(now.year, now.month - 1, 1);
      prevEnd = filterStart;
    } else {
      // Yillik
      filterStart = DateTime(now.year, 1, 1);
      prevStart = DateTime(now.year - 1, 1, 1);
      prevEnd = filterStart;
    }

    final prodCostMap = {
      for (final p in products)
        p.id: (p.costPrice > 0 ? p.costPrice : p.price * 0.65)
    };

    double periodRev = 0.0;
    double periodPaid = 0.0;
    double periodDebt = 0.0;
    double periodCogs = 0.0;
    int salesCount = 0;
    int debtCount = 0;

    double prevRev = 0.0;
    double prevCogs = 0.0;

    for (final s in sales) {
      final dt = s.createdAt?.toLocal();
      if (dt == null) continue;

      if (!dt.isBefore(filterStart) && dt.isBefore(filterEnd)) {
        periodRev += s.total;
        periodPaid += s.paid;
        periodDebt += s.debt;
        salesCount++;
        if (s.debt > 0) debtCount++;

        if (s.items.isNotEmpty) {
          for (final it in s.items) {
            final cost = prodCostMap[it.productId] ?? (it.unitPrice * 0.65);
            periodCogs += it.quantity * cost;
          }
        } else {
          periodCogs += s.total * 0.65;
        }
      } else if (!dt.isBefore(prevStart) && dt.isBefore(prevEnd)) {
        prevRev += s.total;
        if (s.items.isNotEmpty) {
          for (final it in s.items) {
            final cost = prodCostMap[it.productId] ?? (it.unitPrice * 0.65);
            prevCogs += it.quantity * cost;
          }
        } else {
          prevCogs += s.total * 0.65;
        }
      }
    }

    final periodProfit = periodRev > 0 ? (periodRev - periodCogs) : 0.0;
    final periodMargin = periodRev > 0 ? (periodProfit / periodRev * 100) : 0.0;
    final prevProfit = prevRev > 0 ? (prevRev - prevCogs) : 0.0;

    return (
      revenue: periodRev,
      cash: periodPaid,
      debt: periodDebt,
      profit: periodProfit,
      margin: periodMargin,
      salesCount: salesCount,
      debtCount: debtCount,
      prevRevenue: prevRev,
      prevProfit: prevProfit,
    );
  }

  Widget _buildTopStatsRow({
    required FinanceSummary f,
    required List<SaleResult> sales,
    required List<Product> products,
    required bool isDesktop,
    required bool isTablet,
  }) {
    final stats = _getPeriodFinanceStats(
      f: f,
      sales: sales,
      products: products,
      period: _selectedTopPeriod,
    );

    // 1. Daromad kartasi badge matni (Real o'sish foizi)
    String badgeRevenue;
    if (_selectedTopPeriod == 'Barchasi') {
      badgeRevenue = '${stats.salesCount} ta savdo cheki';
    } else if (stats.prevRevenue > 0) {
      final revGrowth =
          ((stats.revenue - stats.prevRevenue) / stats.prevRevenue * 100);
      final sign = revGrowth >= 0 ? '+' : '';
      final compText = _selectedTopPeriod == 'Bugun'
          ? 'Kechagiga nisbatan'
          : _selectedTopPeriod == 'Haftalik'
              ? 'O‘tgan haftaga nisbatan'
              : _selectedTopPeriod == 'Oylik'
                  ? 'O‘tgan oyga nisbatan'
                  : 'O‘tgan yilga nisbatan';
      badgeRevenue = '$sign${revGrowth.toStringAsFixed(0)}% $compText';
    } else {
      badgeRevenue = stats.revenue > 0
          ? '${stats.salesCount} ta savdo cheki'
          : 'Savdo yo‘q';
    }

    // 2. Kassa tushumi badge matni (Real tushum sur'ati / to'lov foizi)
    final cashRate = stats.revenue > 0
        ? (stats.cash / stats.revenue * 100).clamp(0.0, 100.0)
        : (stats.cash > 0 ? 100.0 : 0.0);
    final badgeCash = stats.revenue > 0
        ? '${cashRate.toStringAsFixed(0)}% Tushum sur’ati'
        : (stats.cash > 0 ? 'To‘langan' : '0% Tushum');

    // 3. Qarzdorlik kartasi (Nasiya foizi va cheklar soni)
    final debtProgress = stats.revenue > 0
        ? (stats.debt / stats.revenue).clamp(0.05, 0.95)
        : (stats.debt > 0 ? 0.95 : 0.05);
    final debtPercent = stats.revenue > 0
        ? '${((stats.debt / stats.revenue) * 100).toStringAsFixed(0)}%'
        : (stats.debt > 0 ? '100%' : '0%');
    final debtSubText = stats.debt > 0
        ? (stats.debtCount > 0
            ? '${stats.debtCount} ta nasiya cheki'
            : 'Undirish kutilmoqda')
        : 'Nasiya yo‘q';

    // 4. Sof Foyda badge matni (Mantiqan to'g'ri: zarar bo'lganda rentabellik/zarar ko'rsatiladi)
    String badgeProfit;
    bool isPositiveProfit;

    if (stats.profit < 0) {
      isPositiveProfit = false;
      if (stats.revenue > 0) {
        badgeProfit = '-${stats.margin.abs().toStringAsFixed(1)}% zarar';
      } else {
        badgeProfit = 'Zararda';
      }
    } else if (stats.profit == 0) {
      isPositiveProfit = true;
      badgeProfit = 'Hozircha foyda 0';
    } else {
      isPositiveProfit = true;
      if (_selectedTopPeriod == 'Barchasi') {
        badgeProfit = '+${stats.margin.toStringAsFixed(1)}% foyda';
      } else if (stats.prevProfit > 0) {
        final profitGrowth =
            ((stats.profit - stats.prevProfit) / stats.prevProfit * 100);
        if (profitGrowth >= 0) {
          badgeProfit = '+${profitGrowth.toStringAsFixed(0)}% o‘sish';
        } else {
          badgeProfit = '-${profitGrowth.abs().toStringAsFixed(0)}% pasayish';
        }
      } else {
        badgeProfit = '+${stats.margin.toStringAsFixed(1)}% foyda';
      }
    }

    final double? topCardHeight = (isDesktop || isTablet) ? 182.0 : null;

    final card1 = _TopDarkStatCard(
      title: 'Jami Savdolar (Daromad)',
      value: money(stats.revenue),
      badgeText: badgeRevenue,
      icon: Icons.shopping_bag_outlined,
      height: topCardHeight,
      onTap: () => widget.onNavigate?.call(1),
    );

    final card2 = _TopLightStatCard(
      title: 'Kassaga Tushgan Pul',
      value: money(stats.cash),
      badgeText: badgeCash,
      icon: Icons.payments_outlined,
      iconColor: AppColors.green,
      iconBg: AppColors.greenSoft,
      height: topCardHeight,
      onTap: () => widget.onNavigate?.call(1),
    );

    final card3 = _TopGaugeStatCard(
      title: 'Qarzdorlik (Nasiya)',
      value: money(stats.debt),
      subText: debtSubText,
      icon: Icons.pending_actions_rounded,
      ringColor: const Color(0xFFC77700),
      height: topCardHeight,
      onTap: () => widget.onNavigate?.call(2),
    );

    final card4 = _TopSpeedGaugeCard(
      title: 'Sof Foyda',
      value: money(stats.profit),
      badgeText: badgeProfit,
      isPositive: isPositiveProfit,
      icon: isPositiveProfit
          ? Icons.trending_up_rounded
          : Icons.trending_down_rounded,
      height: topCardHeight,
      onTap: () => _reload(),
    );

    final periods = ['Bugun', 'Haftalik', 'Oylik', 'Yillik', 'Barchasi'];

    Widget buildPeriodSelector({bool isFullWidth = false}) {
      return Container(
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
        ),
        child: isFullWidth
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final availableW = constraints.maxWidth;
                  final canDistributeEvenly =
                      availableW >= (periods.length * 62.0);
                  if (canDistributeEvenly) {
                    return Row(
                      children: [
                        for (final p in periods) ...[
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedTopPeriod = p),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _selectedTopPeriod == p
                                      ? (context.isDark
                                          ? AppColors.neonLime
                                          : AppColors.darkCard)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  p,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: _selectedTopPeriod == p
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: _selectedTopPeriod == p
                                        ? (context.isDark
                                            ? AppColors.ink
                                            : Colors.white)
                                        : context.mutedColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (p != periods.last) const SizedBox(width: 4),
                        ],
                      ],
                    );
                  } else {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final p in periods) ...[
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedTopPeriod = p),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: _selectedTopPeriod == p
                                      ? (context.isDark
                                          ? AppColors.neonLime
                                          : AppColors.darkCard)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: _selectedTopPeriod == p
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: _selectedTopPeriod == p
                                        ? (context.isDark
                                            ? AppColors.ink
                                            : Colors.white)
                                        : context.mutedColor,
                                  ),
                                ),
                              ),
                            ),
                            if (p != periods.last) const SizedBox(width: 4),
                          ],
                        ],
                      ),
                    );
                  }
                },
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in periods) ...[
                      GestureDetector(
                        onTap: () => setState(() => _selectedTopPeriod = p),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _selectedTopPeriod == p
                                ? (context.isDark
                                    ? AppColors.neonLime
                                    : AppColors.darkCard)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            p,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _selectedTopPeriod == p
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: _selectedTopPeriod == p
                                  ? (context.isDark
                                      ? AppColors.ink
                                      : Colors.white)
                                  : context.mutedColor,
                            ),
                          ),
                        ),
                      ),
                      if (p != periods.last) const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
      );
    }

    Widget headerRow;
    if (isDesktop || isTablet) {
      headerRow = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Moliyaviy Ko‘rsatkichlar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: context.inkColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_selectedTopPeriod bo‘yicha tushum va sof foyda hisobi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.mutedColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          buildPeriodSelector(isFullWidth: false),
        ],
      );
    } else {
      headerRow = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Moliyaviy Ko‘rsatkichlar',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.inkColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$_selectedTopPeriod bo‘yicha tushum va sof foyda hisobi',
            style: TextStyle(fontSize: 12, color: context.mutedColor),
          ),
          const SizedBox(height: 10),
          buildPeriodSelector(isFullWidth: true),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        headerRow,
        const SizedBox(height: 14),
        if (isDesktop)
          Row(
            children: [
              Expanded(child: card1),
              const SizedBox(width: 16),
              Expanded(child: card2),
              const SizedBox(width: 16),
              Expanded(child: card3),
              const SizedBox(width: 16),
              Expanded(child: card4),
            ],
          )
        else if (isTablet)
          Column(
            children: [
              Row(children: [
                Expanded(child: card1),
                const SizedBox(width: 16),
                Expanded(child: card2)
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: card3),
                const SizedBox(width: 16),
                Expanded(child: card4)
              ]),
            ],
          )
        else
          Column(
            children: [
              card1,
              const SizedBox(height: 12),
              card2,
              const SizedBox(height: 12),
              card3,
              const SizedBox(height: 12),
              card4,
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. O'rta chap: To'lqinsimon Spline Grafiki (Stock Volume vs Consume)
  // ---------------------------------------------------------------------------

  String _productCategory(Product p) {
    final n = p.name.toLowerCase();
    if (n.contains('plita') ||
        n.contains('bruschatka') ||
        n.contains('bordyur') ||
        n.contains('yo‘lka') ||
        n.contains('zinapoya') ||
        n.contains('metalogranit')) {
      return 'Plitalar';
    }
    if (n.contains('sement') ||
        n.contains('qum') ||
        n.contains('kley') ||
        n.contains('elim') ||
        n.contains('kraska') ||
        n.contains('lak') ||
        n.contains('grunt')) {
      return 'Materiallar';
    }
    if (n.contains('sim') ||
        n.contains('disk') ||
        n.contains('pichoq') ||
        n.contains('asbob') ||
        (p.unit == 'dona' && !n.contains('kley'))) {
      return 'Aksessuarlar';
    }
    return 'Toshlar';
  }

  List<Product> _filterCategoryProducts(List<Product> allProducts, String cat) {
    if (cat == 'Barchasi') return allProducts;
    return allProducts.where((p) => _productCategory(p) == cat).toList();
  }

  static double _calculateNiceMax(double value) {
    if (value <= 0) return 10000000.0;
    final target = value * 1.15;
    final exponent = (math.log(target) / math.ln10).floor();
    final powerOfTen = math.pow(10, exponent).toDouble();
    final fraction = target / powerOfTen;

    double niceFraction;
    if (fraction <= 1.0) {
      niceFraction = 1.0;
    } else if (fraction <= 1.5) {
      niceFraction = 1.5;
    } else if (fraction <= 2.0) {
      niceFraction = 2.0;
    } else if (fraction <= 2.5) {
      niceFraction = 2.5;
    } else if (fraction <= 5.0) {
      niceFraction = 5.0;
    } else if (fraction <= 7.5) {
      niceFraction = 7.5;
    } else {
      niceFraction = 10.0;
    }
    return niceFraction * powerOfTen;
  }

  ({
    List<String> labels,
    List<String> fullLabels,
    List<double> stockPoints,
    List<double> salesPoints,
  }) _getRealChartPoints({
    required List<Product> catProducts,
    required List<Product> allProducts,
    required List<SaleResult> sales,
    required List<StockMovementRecord> movements,
    required String period,
    required String category,
  }) {
    final now = DateTime.now();
    final catProductIds = catProducts.map((p) => p.id).toSet();
    final currentCatStock = catProducts.fold<double>(
      0.0,
      (sum, p) =>
          sum +
          (p.stock *
              (p.price > 0 ? p.price : (p.costPrice > 0 ? p.costPrice : 0.0))),
    );
    final totalAllStock = allProducts.fold<double>(
      0.0,
      (sum, p) =>
          sum +
          (p.stock *
              (p.price > 0 ? p.price : (p.costPrice > 0 ? p.costPrice : 0.0))),
    );
    final catRatio =
        totalAllStock > 0 ? (currentCatStock / totalAllStock) : 0.25;

    // Har bir mahsulotning narxi
    final allProductPrices = {
      for (final p in allProducts)
        p.id: (p.price > 0 ? p.price : (p.costPrice > 0 ? p.costPrice : 0.0))
    };

    // Har bir savdodan tanlangan kategoriya summasini aniq ajratib olish
    double getSaleAmountForCategory(SaleResult s) {
      if (category == 'Barchasi') return s.total;
      if (s.items.isNotEmpty) {
        double itemSum = 0;
        bool hasMatched = false;
        for (final it in s.items) {
          if (catProductIds.contains(it.productId)) {
            itemSum += it.lineTotal;
            hasMatched = true;
          }
        }
        if (hasMatched) return itemSum;
        return 0.0;
      }
      return s.total * catRatio;
    }

    // O'tmishdagi ma'lum vaqt nuqtasidagi haqiqiy zaxira qiymatini hisoblash
    double getStockAtTime(DateTime timePoint) {
      if (!timePoint.isBefore(now)) return currentCatStock;

      double movementDelta = 0.0;
      bool hasMovement = false;
      for (final m in movements) {
        final mDate = m.createdAt.toLocal();
        if (mDate.isAfter(timePoint)) {
          final isCat =
              category == 'Barchasi' || catProductIds.contains(m.productId);
          if (isCat) {
            final pr = allProductPrices[m.productId] ?? 0.0;
            movementDelta += m.qtyDelta * pr;
            hasMovement = true;
          }
        }
      }

      if (hasMovement) {
        final calculated = currentCatStock - movementDelta;
        return calculated > 0 ? calculated : 0.0;
      }

      // Savdolar orqali zaxirani tiklash
      double salesAfter = 0.0;
      for (final s in sales) {
        final sDate = s.createdAt?.toLocal();
        if (sDate != null && sDate.isAfter(timePoint)) {
          salesAfter += getSaleAmountForCategory(s);
        }
      }
      return math.max(0.0, currentCatStock + salesAfter);
    }

    final dayShorts = ['Dush', 'Sesh', 'Chor', 'Pay', 'Jum', 'Shan', 'Yak'];
    final dayLongs = [
      'Dushanba',
      'Seshanba',
      'Chorshanba',
      'Payshanba',
      'Juma',
      'Shanba',
      'Yakshanba'
    ];
    final monthNames = [
      'yan',
      'fev',
      'mar',
      'apr',
      'may',
      'iyn',
      'iyl',
      'avg',
      'sen',
      'okt',
      'noy',
      'dek'
    ];

    List<String> labels;
    List<String> fullLabels;
    List<double> salesPoints;
    List<double> stockPoints;

    if (period == 'Haftalik') {
      labels = <String>[];
      fullLabels = <String>[];
      salesPoints = List.filled(7, 0.0);
      stockPoints = List.filled(7, currentCatStock);

      for (int i = 0; i < 7; i++) {
        final daysAgo = 6 - i;
        final dayStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: daysAgo));
        final dayEnd = dayStart.add(const Duration(days: 1));
        final wDay = dayStart.weekday;

        if (daysAgo == 0) {
          labels.add('Bugun');
          fullLabels.add('${dayLongs[wDay - 1]} (Bugun)');
        } else {
          labels.add(dayShorts[wDay - 1]);
          fullLabels.add(
              '${dayLongs[wDay - 1]}, ${dayStart.day}-${monthNames[dayStart.month - 1]}');
        }

        double daySales = 0.0;
        for (final s in sales) {
          final sDate = s.createdAt?.toLocal();
          if (sDate != null &&
              !sDate.isBefore(dayStart) &&
              sDate.isBefore(dayEnd)) {
            daySales += getSaleAmountForCategory(s);
          }
        }
        salesPoints[i] = daySales;
        stockPoints[i] =
            daysAgo == 0 ? currentCatStock : getStockAtTime(dayEnd);
      }
    } else if (period == 'Yillik') {
      labels = [
        'Yan-Fev',
        'Mar-Apr',
        'May-Iyn',
        'Iyl-Avg',
        'Sen-Okt',
        'Noy-Dek'
      ];
      fullLabels = [
        'Yanvar - Fevral',
        'Mart - Aprel',
        'May - Iyun',
        'Iyul - Avgust',
        'Sentabr - Oktabr',
        'Noyabr - Dekabr'
      ];
      salesPoints = List.filled(6, 0.0);
      stockPoints = List.filled(6, currentCatStock);

      for (int b = 0; b < 6; b++) {
        final m1 = b * 2 + 1;
        final m2 = b * 2 + 2;
        final periodStart = DateTime(now.year, m1, 1);
        final periodEnd = (m2 == 12)
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, m2 + 1, 1);

        double biMonthSales = 0.0;
        for (final s in sales) {
          final sDate = s.createdAt?.toLocal();
          if (sDate != null &&
              !sDate.isBefore(periodStart) &&
              sDate.isBefore(periodEnd)) {
            biMonthSales += getSaleAmountForCategory(s);
          }
        }
        salesPoints[b] = biMonthSales;

        if (periodEnd.isBefore(now)) {
          stockPoints[b] = getStockAtTime(periodEnd);
        } else {
          stockPoints[b] = currentCatStock;
        }
      }
    } else {
      // Oylik (Joriy oyning 4 ta haftalik davri)
      labels = ['1-hafta', '2-hafta', '3-hafta', '4-hafta'];
      fullLabels = <String>[];
      salesPoints = List.filled(4, 0.0);
      stockPoints = List.filled(4, currentCatStock);

      final monthStr = monthNames[now.month - 1];
      final weekIntervals = [
        (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month, 8),
          '1-7 $monthStr'
        ),
        (
          DateTime(now.year, now.month, 8),
          DateTime(now.year, now.month, 15),
          '8-14 $monthStr'
        ),
        (
          DateTime(now.year, now.month, 15),
          DateTime(now.year, now.month, 22),
          '15-21 $monthStr'
        ),
        (
          DateTime(now.year, now.month, 22),
          DateTime(now.year, now.month + 1, 1),
          '22-oy oxiri $monthStr'
        ),
      ];

      for (int i = 0; i < 4; i++) {
        final (wStart, wEnd, wLabel) = weekIntervals[i];
        fullLabels.add(wLabel);

        double intervalSales = 0.0;
        if (!wStart.isAfter(now)) {
          for (final s in sales) {
            final sDate = s.createdAt?.toLocal();
            if (sDate != null &&
                !sDate.isBefore(wStart) &&
                sDate.isBefore(wEnd)) {
              intervalSales += getSaleAmountForCategory(s);
            }
          }
        }
        salesPoints[i] = intervalSales;

        if (wEnd.isBefore(now)) {
          stockPoints[i] = getStockAtTime(wEnd);
        } else {
          stockPoints[i] = currentCatStock;
        }
      }
    }

    return (
      labels: labels,
      fullLabels: fullLabels,
      stockPoints: stockPoints,
      salesPoints: salesPoints,
    );
  }

  Widget _buildStockWaveChartCard(
    FinanceSummary f,
    List<Product> products,
    List<SaleResult> sales,
    List<StockMovementRecord> movements, {
    double? height,
  }) {
    final categories = [
      'Barchasi',
      'Toshlar',
      'Plitalar',
      'Materiallar',
      'Aksessuarlar'
    ];

    // Tanlangan kategoriya bo'yicha mahsulotlar va real qiymatlar
    final catProducts = products;
    final chartData = _getRealChartPoints(
      catProducts: catProducts,
      allProducts: products,
      sales: sales,
      movements: movements,
      period: _selectedPeriod,
      category: 'Barchasi',
    );

    final labels = chartData.labels;
    final fullLabels = chartData.fullLabels;
    final stockPoints = chartData.stockPoints;
    final salesPoints = chartData.salesPoints;

    final catStockVal = catProducts.fold<double>(
      0.0,
      (sum, p) =>
          sum +
          (p.stock *
              (p.price > 0 ? p.price : (p.costPrice > 0 ? p.costPrice : 0.0))),
    );
    final catSalesVal = salesPoints.fold<double>(0.0, (sum, v) => sum + v);

    // Kategoriya masshtabiga mos dinamik Y-o'qi balandliklari
    final peakStock =
        stockPoints.isNotEmpty ? stockPoints.reduce(math.max) : 0.0;
    final peakSale =
        salesPoints.isNotEmpty ? salesPoints.reduce(math.max) : 0.0;
    final scaleStockMax = _calculateNiceMax(peakStock);
    final scaleSaleMax = _calculateNiceMax(peakSale);

    final hoverIndex = _chartHoverIndex;
    final activeStockVal =
        hoverIndex != null ? stockPoints[hoverIndex] : catStockVal;
    final activeSaleVal =
        hoverIndex != null ? salesPoints[hoverIndex] : catSalesVal;
    final activeLabel = hoverIndex != null ? fullLabels[hoverIndex] : '';

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        final isCompact = cardConstraints.maxWidth < 950;

        final periodDropdown = PopupMenuButton<String>(
          initialValue: _selectedPeriod,
          tooltip: 'Davrni tanlash',
          onSelected: (v) => setState(() => _selectedPeriod = v),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'Haftalik', child: Text('Haftalik')),
            PopupMenuItem(value: 'Oylik', child: Text('Oylik')),
            PopupMenuItem(value: 'Yillik', child: Text('Yillik')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: context.pillColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedPeriod,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: context.inkColor),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 15, color: context.inkColor),
              ],
            ),
          ),
        );

        final legendDots = [
          _LegendDot(
            color: context.isDark ? const Color(0xFF10B981) : AppColors.green,
            label: _chartHoverIndex != null
                ? 'Sotuv: ${money(activeSaleVal)}'
                : 'Sotuv: ${money(catSalesVal)}',
          ),
        ];

        return Container(
          height: height,
          padding: EdgeInsets.all(isCompact ? 14 : 22),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: height != null
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            children: [
              // Sarlavha va boshqaruv elementlari
              if (isCompact) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Savdo Dinamikasi',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: context.inkColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Davr bo‘yicha savdo ko‘rsatkichi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: context.mutedColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    periodDropdown,
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: legendDots,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Savdo Dinamikasi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.inkColor),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Davr bo‘yicha tushum va savdo ko‘rsatkichi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    legendDots[0],
                    const SizedBox(width: 12),
                    periodDropdown,
                  ],
                ),

              const SizedBox(height: 18),

              // Interaktiv grafika maydoni
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = height != null
                      ? (height - (isCompact ? 120.0 : 110.0))
                      : (isCompact ? 220.0 : 250.0);
                  const padX = 14.0;
                  final usableW = math.max(10.0, w - (padX * 2));
                  final activeX = _chartHoverIndex == null
                      ? 0.0
                      : padX +
                          (labels.length > 1
                              ? (usableW *
                                  _chartHoverIndex! /
                                  (labels.length - 1))
                              : (usableW / 2));
                  final tooltipW = math.min(240.0, math.max(140.0, w - 24.0));
                  final maxTooltipX = math.max(4.0, w - tooltipW - 4.0);
                  final tooltipX =
                      (activeX - (tooltipW / 2)).clamp(4.0, maxTooltipX);

                  return MouseRegion(
                    onHover: (e) {
                      if (labels.isEmpty) return;
                      final relX =
                          (e.localPosition.dx - padX).clamp(0.0, usableW);
                      final newIdx = (labels.length > 1
                              ? ((relX / usableW) * (labels.length - 1)).round()
                              : 0)
                          .clamp(0, labels.length - 1);
                      if (_chartHoverIndex != newIdx) {
                        setState(() {
                          _chartHoverIndex = newIdx;
                        });
                      }
                    },
                    onExit: (_) {
                      if (_chartHoverIndex != null) {
                        setState(() {
                          _chartHoverIndex = null;
                        });
                      }
                    },
                    child: GestureDetector(
                      onPanDown: (d) {
                        if (labels.isEmpty) return;
                        final relX =
                            (d.localPosition.dx - padX).clamp(0.0, usableW);
                        final newIdx = (labels.length > 1
                                ? ((relX / usableW) * (labels.length - 1))
                                    .round()
                                : 0)
                            .clamp(0, labels.length - 1);
                        if (_chartHoverIndex != newIdx) {
                          setState(() {
                            _chartHoverIndex = newIdx;
                          });
                        }
                      },
                      onPanUpdate: (d) {
                        if (labels.isEmpty) return;
                        final relX =
                            (d.localPosition.dx - padX).clamp(0.0, usableW);
                        final newIdx = (labels.length > 1
                                ? ((relX / usableW) * (labels.length - 1))
                                    .round()
                                : 0)
                            .clamp(0, labels.length - 1);
                        if (_chartHoverIndex != newIdx) {
                          setState(() {
                            _chartHoverIndex = newIdx;
                          });
                        }
                      },
                      onPanEnd: (_) {
                        if (_chartHoverIndex != null) {
                          setState(() {
                            _chartHoverIndex = null;
                          });
                        }
                      },
                      child: SizedBox(
                        height: h,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _WaveSplineChartPainter(
                                  salesPoints: salesPoints,
                                  labels: labels,
                                  scaleSaleMax: scaleSaleMax,
                                  hoverIndex: _chartHoverIndex,
                                  isDark: context.isDark,
                                ),
                              ),
                            ),
                            // Tooltip faqat kursor nuqta ustiga kelganda barqaror chiqadi
                            if (_chartHoverIndex != null)
                              Positioned(
                                top: 8,
                                left: tooltipX,
                                child: Container(
                                  width: tooltipW,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: context.isDark
                                        ? const Color(0xFF1C2128)
                                        : const Color(0xFF1E232B),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: context.isDark
                                          ? const Color(0xFF384252)
                                          : const Color(0xFF2E3642),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                              Icons.calendar_today_rounded,
                                              size: 11,
                                              color: Color(0xFF9CA3AF)),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              activeLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Color(0xFFE5E7EB),
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Savdo',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Color(0xFF9CA3AF),
                                                    fontSize: 9.5,
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: const BoxDecoration(
                                              color: AppColors.greenBright,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Sotuv: ',
                                            style: TextStyle(
                                                color: Color(0xFF9CA3AF),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500),
                                          ),
                                          Expanded(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                money(activeSaleVal),
                                                style: const TextStyle(
                                                  color: AppColors.greenBright,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. O'rta o'ng: Mahsulotlar Qoldiq Jadvali (Custom Tags & Labels)
  // ---------------------------------------------------------------------------

  Widget _buildProductStockRow(BuildContext context, Product p) {
    final isOut = p.stock <= 0;
    final isLow = p.stock > 0 && p.stock < 15;

    Color stockBg;
    Color stockColor;
    String stockText;

    if (isOut) {
      stockBg =
          context.isDark ? const Color(0xFF3B1818) : const Color(0xFFFEE2E2);
      stockColor = AppColors.danger;
      stockText = 'Tugagan';
    } else if (isLow) {
      stockBg =
          context.isDark ? const Color(0xFF38250A) : const Color(0xFFFEF3C7);
      stockColor = const Color(0xFFD97706);
      stockText = 'Kam: ${qty(p.stock)} ${p.unit}';
    } else {
      stockBg = context.isDark ? const Color(0xFF10281E) : AppColors.greenSoft;
      stockColor =
          context.isDark ? AppColors.greenBright : const Color(0xFF047857);
      stockText = '${qty(p.stock)} ${p.unit}';
    }

    return InkWell(
      onTap: () => widget.onNavigate?.call(3),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => showProductImagePreview(
                context,
                imageUrl: p.imageUrl,
                name: p.name,
                subtitle:
                    "${money(p.price)} / ${p.unit} • Qoldiq: ${qty(p.stock)} ${p.unit}",
              ),
              child: ProductThumbnail(
                imageUrl: p.imageUrl,
                name: p.name,
                size: 40,
                borderRadius: 10,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: context.inkColor,
                          ),
                        ),
                      ),
                      if (p.hasSorts) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.neonLime.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            '1·1.5·2 sort',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.neonLime,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.sku.isNotEmpty
                        ? "${p.sku} · ${money(p.price)} / ${p.unit}"
                        : "${money(p.price)} / ${p.unit}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.mutedColor, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: stockBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: stockColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                stockText,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: stockColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsAndStockTableCard(List<Product> products, {double? height}) {
    final lowStock =
        products.where((p) => p.stock > 0 && p.stock <= p.minStock).toList();
    final outOfStock = products.where((p) => p.stock <= 0).toList();
    final inStock = products.where((p) => p.stock > p.minStock).toList();
    final sortProducts = products.where((p) => p.hasSorts).toList();

    final tags = ['Barchasi', 'Kam qolgan', 'Tugagan', 'Yetarli', 'Sortli'];

    if (!tags.contains(_selectedTag)) {
      _selectedTag = 'Barchasi';
    }

    var filtered = List<Product>.from(products);
    if (_selectedTag == 'Kam qolgan') {
      filtered = lowStock;
    } else if (_selectedTag == 'Tugagan') {
      filtered = outOfStock;
    } else if (_selectedTag == 'Yetarli') {
      filtered = inStock;
    } else if (_selectedTag == 'Sortli') {
      filtered = sortProducts;
    }

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        final isCompact = cardConstraints.maxWidth < 480;
        return Container(
          height: height,
          padding: EdgeInsets.all(isCompact ? 14 : 20),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sarlavha qatori
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.isDark
                                ? const Color(0xFF1E2822)
                                : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: context.isDark
                                  ? const Color(0xFF264233)
                                  : const Color(0xFFA7F3D0),
                            ),
                          ),
                          child: const Icon(
                            Icons.inventory_2_rounded,
                            size: 16,
                            color: AppColors.greenBright,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Ombor Holati va Mahsulotlar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isCompact ? 14 : 15.5,
                              fontWeight: FontWeight.w800,
                              color: context.inkColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => widget.onNavigate?.call(3),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Text(
                        'Barchasi →',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.isDark
                              ? AppColors.neonLime
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Teglar (Filterlar) qatori
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tag in tags) ...[
                      GestureDetector(
                        onTap: () => setState(() => _selectedTag = tag),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _selectedTag == tag
                                ? (context.isDark
                                    ? AppColors.neonLime
                                    : AppColors.darkCard)
                                : context.pillColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _selectedTag == tag
                                  ? (context.isDark
                                      ? AppColors.neonLime
                                      : AppColors.darkCard)
                                  : context.borderColor.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 11,
                              color: _selectedTag == tag
                                  ? (context.isDark
                                      ? AppColors.ink
                                      : Colors.white)
                                  : context.mutedColor,
                              fontWeight: _selectedTag == tag
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Mahsulotlar ro'yxati
              if (height != null)
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_rounded,
                                    size: 36,
                                    color: context.mutedColor
                                        .withValues(alpha: 0.5)),
                                const SizedBox(height: 8),
                                Text(
                                  "Bu toifada mahsulotlar yo'q",
                                  style: TextStyle(
                                      color: context.mutedColor, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: false,
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 8, color: context.borderColor),
                          itemBuilder: (_, i) =>
                              _buildProductStockRow(context, filtered[i]),
                        ),
                )
              else if (filtered.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "Bu toifada mahsulotlar yo'q",
                      style: TextStyle(color: context.mutedColor, fontSize: 13),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: math.min(filtered.length, 6),
                  separatorBuilder: (_, __) =>
                      Divider(height: 8, color: context.borderColor),
                  itemBuilder: (_, i) =>
                      _buildProductStockRow(context, filtered[i]),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Pastki chap: So'nggi Savdolar (Sales & Orders)
  // ---------------------------------------------------------------------------

  Widget _buildRecentOrdersCard(FinanceSummary f, List<SaleResult> sales,
      {double? height}) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Savdolar & Buyurtmalar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => widget.onNavigate?.call(1),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    sales.isNotEmpty
                        ? 'Barchasi (${sales.length}) →'
                        : 'Savdo qilish →',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.isDark
                            ? AppColors.neonLime
                            : AppColors.ink),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (height != null)
            Expanded(
              child: sales.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                                color: AppColors.greenSoft,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.shopping_bag_outlined,
                                color: AppColors.green, size: 22),
                          ),
                          const SizedBox(height: 10),
                          Text('Hozircha savdolar yo‘q',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: context.inkColor)),
                          const SizedBox(height: 4),
                          Text('Kassadan yangi savdo amalga oshiring',
                              style: TextStyle(
                                  color: context.mutedColor, fontSize: 11)),
                          const SizedBox(height: 10),
                          FilledButton.tonal(
                            onPressed: () => widget.onNavigate?.call(1),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.isDark
                                  ? AppColors.neonLime
                                  : AppColors.darkCard,
                              foregroundColor:
                                  context.isDark ? AppColors.ink : Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                            ),
                            child: const Text('Savdoga o‘tish',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: false,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: sales.length > 5 ? 5 : sales.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 8, color: context.borderColor),
                      itemBuilder: (_, i) => _buildSaleRowItem(sales[i]),
                    ),
            )
          else if (sales.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                          color: AppColors.greenSoft, shape: BoxShape.circle),
                      child: const Icon(Icons.shopping_bag_outlined,
                          color: AppColors.green, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text('Hozircha savdolar yo‘q',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: context.inkColor)),
                    const SizedBox(height: 4),
                    Text('Kassadan yangi savdo amalga oshiring',
                        style:
                            TextStyle(color: context.mutedColor, fontSize: 11)),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: () => widget.onNavigate?.call(1),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.isDark
                            ? AppColors.neonLime
                            : AppColors.darkCard,
                        foregroundColor:
                            context.isDark ? AppColors.ink : Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      child: const Text('Savdoga o‘tish',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final s in sales.take(5)) _buildSaleRowItem(s),
        ],
      ),
    );
  }

  Widget _buildSaleRowItem(SaleResult s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => _showSaleDetails(s),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: context.pillColor,
              child: Text(
                s.customerName != null && s.customerName!.isNotEmpty
                    ? s.customerName![0].toUpperCase()
                    : '#',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: context.inkColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.customerName?.isNotEmpty == true
                        ? s.customerName!
                        : 'Savdo #${s.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: context.inkColor),
                  ),
                  Text(
                    s.createdAt != null
                        ? '${s.createdAt!.day.toString().padLeft(2, '0')}.${s.createdAt!.month.toString().padLeft(2, '0')} ${s.createdAt!.hour.toString().padLeft(2, '0')}:${s.createdAt!.minute.toString().padLeft(2, '0')}  ·  #${s.id}'
                        : 'Savdo #${s.id}',
                    style: TextStyle(color: context.mutedColor, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  money(s.total),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: context.inkColor),
                ),
                const SizedBox(height: 4),
                _buildSaleStatusBadge(s),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleStatusBadge(SaleResult s) {
    String label;
    Color fg;
    Color bg;

    if (s.debt <= 0.01) {
      label = 'To‘langan';
      fg = AppColors.green;
      bg = context.isDark ? const Color(0xFF1E3A2B) : AppColors.greenSoft;
    } else if (s.paid <= 0.01) {
      label = 'Nasiya';
      fg = AppColors.danger;
      bg = context.isDark ? const Color(0xFF3B1E1E) : AppColors.dangerSoft;
    } else {
      label = 'Qisman';
      fg = const Color(0xFFF59E0B);
      bg = context.isDark ? const Color(0xFF382C17) : const Color(0xFFFFF1DC);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 10),
      ),
    );
  }

  void _showSaleDetails(SaleResult s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.receipt_rounded,
                color: context.isDark ? AppColors.neonLime : AppColors.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Savdo #${s.id}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: context.inkColor)),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _detailRow(
                  'Mijoz',
                  s.customerName?.isNotEmpty == true
                      ? s.customerName!
                      : 'Nomsiz'),
              if (s.customerPhone?.isNotEmpty == true)
                _detailRow('Telefon', s.customerPhone!),
              Divider(height: 16, color: context.borderColor),
              _detailRow('Jami summa', money(s.total), bold: true),
              _detailRow('To‘langan', money(s.paid), color: AppColors.green),
              if (s.debt > 0.01)
                _detailRow('Qoldiq qarz', money(s.debt),
                    color: AppColors.danger, bold: true),
              if (s.createdAt != null)
                _detailRow(
                  'Vaqti',
                  '${s.createdAt!.day.toString().padLeft(2, '0')}.${s.createdAt!.month.toString().padLeft(2, '0')}.${s.createdAt!.year} ${s.createdAt!.hour.toString().padLeft(2, '0')}:${s.createdAt!.minute.toString().padLeft(2, '0')}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Yopish')),
          if (s.debt > 0.01)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onNavigate?.call(2); // Nasiyalar sahifasiga o'tish
              },
              style: FilledButton.styleFrom(
                backgroundColor:
                    context.isDark ? AppColors.neonLime : AppColors.darkCard,
                foregroundColor: context.isDark ? AppColors.ink : Colors.white,
              ),
              child: const Text('Qarz undirish'),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: context.mutedColor, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
              color: color ?? context.inkColor,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Pastki o'rta: AI Zaxira Tavsiyasi (AI Restock Recommendation)
  // ---------------------------------------------------------------------------

  List<AiRestockItem> _calculateAiRecommendations(
      List<Product> products, List<SaleResult> sales) {
    final salesVolume = <int, double>{};
    for (final s in sales) {
      for (final it in s.items) {
        salesVolume[it.productId] =
            (salesVolume[it.productId] ?? 0) + it.quantity;
      }
    }

    final items = <AiRestockItem>[];
    for (final p in products) {
      final sold = salesVolume[p.id] ?? 0;
      final daily = sold > 0 ? (sold / 14).clamp(0.2, 50.0) : 0.5;
      final stock = p.stock;
      final daysLeft = stock <= 0 ? 0 : (stock / daily).round();

      String urgency;
      String reason;
      double recommended;

      if (stock <= 0) {
        urgency = 'critical';
        reason =
            'Omborda butunlay tugagan! Zudlik bilan xarid yoki ishlab chiqarish kerak.';
        recommended = (daily * 30).clamp(20.0, 300.0).roundToDouble();
      } else if (stock < 15 || daysLeft <= 5) {
        urgency = 'critical';
        reason =
            'Zaxira ~$daysLeft kunga yetadi (Kunlik sotuv: ~${daily.toStringAsFixed(1)} ${p.unit}).';
        recommended = ((daily * 30) - stock).clamp(10.0, 250.0).roundToDouble();
      } else if (stock < 35 || daysLeft <= 14) {
        urgency = 'warning';
        reason =
            'Xavfsiz zaxira miqdoridan past. Oldindan buyurtma berish tavsiya etiladi.';
        recommended = ((daily * 30) - stock).clamp(10.0, 200.0).roundToDouble();
      } else {
        urgency = 'optimal';
        reason = 'Zaxira yetarli (~$daysLeft kunga yetadi).';
        recommended = 0;
      }

      items.add(AiRestockItem(
        product: p,
        currentStock: stock,
        totalSold: sold,
        dailyBurn: daily,
        daysRemaining: daysLeft,
        recommendedQty: recommended,
        urgency: urgency,
        reason: reason,
      ));
    }

    items.sort((a, b) {
      const priority = {'critical': 0, 'warning': 1, 'optimal': 2};
      final pComp =
          (priority[a.urgency] ?? 2).compareTo(priority[b.urgency] ?? 2);
      if (pComp != 0) return pComp;
      return a.daysRemaining.compareTo(b.daysRemaining);
    });

    return items;
  }

  Future<void> _openQuickPurchase() async {
    final repos = context.read<AppRepositories>();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockPurchaseDialog(
        stockRepo: repos.stock,
        productRepo: repos.products,
      ),
    );
    if (ok == true && mounted) {
      _reload();
    }
  }

  Future<void> _openQuickProduction() async {
    final repos = context.read<AppRepositories>();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskCreateDialog(
        productRepo: repos.products,
        productionRepo: repos.production,
      ),
    );
    if (ok == true && mounted) {
      _reload();
    }
  }

  void _showAiRestockDetails(List<AiRestockItem> items) {
    final critical = items.where((x) => x.urgency == 'critical').toList();
    final warning = items.where((x) => x.urgency == 'warning').toList();
    final optimal = items.where((x) => x.urgency == 'optimal').toList();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        String filter = 'all'; // 'all', 'critical', 'warning', 'optimal'
        String search = '';

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filteredItems = items.where((it) {
              if (filter == 'critical' && it.urgency != 'critical')
                return false;
              if (filter == 'warning' && it.urgency != 'warning') return false;
              if (filter == 'optimal' && it.urgency != 'optimal') return false;
              if (search.trim().isNotEmpty) {
                final q = search.trim().toLowerCase();
                if (!it.product.name.toLowerCase().contains(q)) return false;
              }
              return true;
            }).toList();

            final isNarrow = MediaQuery.sizeOf(ctx).width < 500;
            return Dialog(
              backgroundColor: ctx.cardColor,
              insetPadding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 12 : 24, vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 720, maxHeight: 660),
                padding: EdgeInsets.all(isNarrow ? 14 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sarlavha
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: ctx.isDark
                                  ? [
                                      const Color(0xFF283618),
                                      const Color(0xFF1B2A15)
                                    ]
                                  : [
                                      AppColors.neonLimeSoft,
                                      const Color(0xFFDCFCE7)
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.neonLime.withValues(alpha: 0.5),
                              width: 1.2,
                            ),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 22,
                            color: AppColors.neonLime,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'AI Zaxira va Xarid Prognozi',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: isNarrow ? 15 : 18,
                                      color: ctx.inkColor,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.neonLime
                                          .withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'SMART ENGINE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.neonLime,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Kunlik sarf tezligi (burn rate) va joriy qoldiq asosida hisoblangan tavsiyalar',
                                style: TextStyle(
                                    fontSize: 12, color: ctx.mutedColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Mini KPI paneli
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: ctx.isDark
                            ? const Color(0xFF161F1A)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: ctx.borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setDialogState(() => filter =
                                  filter == 'critical' ? 'all' : 'critical'),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: filter == 'critical'
                                      ? AppColors.danger.withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.error_rounded,
                                            size: 12, color: AppColors.danger),
                                        SizedBox(width: 3),
                                        Flexible(
                                          child: Text('Kritik',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.muted)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text('${critical.length} ta',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: AppColors.danger)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                              width: 1, height: 28, color: ctx.borderColor),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setDialogState(() => filter =
                                  filter == 'warning' ? 'all' : 'warning'),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: filter == 'warning'
                                      ? const Color(0xFFD97706)
                                          .withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.warning_amber_rounded,
                                            size: 12, color: Color(0xFFD97706)),
                                        SizedBox(width: 3),
                                        Flexible(
                                          child: Text('Zaxira kam',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.muted)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text('${warning.length} ta',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: Color(0xFFD97706))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                              width: 1, height: 28, color: ctx.borderColor),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setDialogState(() => filter =
                                  filter == 'optimal' ? 'all' : 'optimal'),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: filter == 'optimal'
                                      ? AppColors.green.withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_rounded,
                                            size: 12, color: AppColors.green),
                                        SizedBox(width: 3),
                                        Flexible(
                                          child: Text('Yetarli',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.muted)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text('${optimal.length} ta',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: AppColors.green)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Filter va qidiruv paneli
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 38,
                          child: TextField(
                            onChanged: (val) =>
                                setDialogState(() => search = val),
                            style:
                                TextStyle(fontSize: 12.5, color: ctx.inkColor),
                            decoration: InputDecoration(
                              hintText: 'Tovar nomini qidirish...',
                              hintStyle: TextStyle(
                                  fontSize: 12, color: ctx.mutedColor),
                              prefixIcon:
                                  const Icon(Icons.search_rounded, size: 18),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 0),
                              filled: true,
                              fillColor: ctx.isDark
                                  ? const Color(0xFF1A222C)
                                  : const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: Text('Barchasi (${items.length})',
                                    style: const TextStyle(fontSize: 11)),
                                selected: filter == 'all',
                                onSelected: (_) =>
                                    setDialogState(() => filter = 'all'),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: Text('Kritik (${critical.length})',
                                    style: const TextStyle(fontSize: 11)),
                                selected: filter == 'critical',
                                onSelected: (_) =>
                                    setDialogState(() => filter = 'critical'),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: Text('Kam (${warning.length})',
                                    style: const TextStyle(fontSize: 11)),
                                selected: filter == 'warning',
                                onSelected: (_) =>
                                    setDialogState(() => filter = 'warning'),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: Text('Yetarli (${optimal.length})',
                                    style: const TextStyle(fontSize: 11)),
                                selected: filter == 'optimal',
                                onSelected: (_) =>
                                    setDialogState(() => filter = 'optimal'),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Tovarlar ro'yxati
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                              child: Text(
                                "Tanlangan parametr bo'yicha tovarlar topilmadi.",
                                style: TextStyle(
                                    color: ctx.mutedColor, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final item = filteredItems[i];
                                final isCrit = item.urgency == 'critical';
                                final isWarn = item.urgency == 'warning';
                                final isOut = item.currentStock <= 0;

                                Color statusColor = AppColors.green;
                                String statusText =
                                    'Yetarli (~${item.daysRemaining}k)';
                                if (isCrit) {
                                  statusColor = AppColors.danger;
                                  statusText = isOut
                                      ? 'Tugagan'
                                      : 'Kritik (~${item.daysRemaining}k)';
                                } else if (isWarn) {
                                  statusColor = const Color(0xFFD97706);
                                  statusText = 'Kam (~${item.daysRemaining}k)';
                                }

                                final totalTarget =
                                    item.currentStock + item.recommendedQty;
                                final progress = totalTarget > 0
                                    ? (item.currentStock / totalTarget)
                                        .clamp(0.0, 1.0)
                                    : 1.0;

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: ctx.cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isCrit
                                          ? AppColors.danger
                                              .withValues(alpha: 0.35)
                                          : (isWarn
                                              ? const Color(0xFFD97706)
                                                  .withValues(alpha: 0.3)
                                              : ctx.borderColor),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ProductThumbnail(
                                            imageUrl: item.product.imageUrl,
                                            name: item.product.name,
                                            size: 46,
                                            borderRadius: 12,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        item.product.name,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 14.5,
                                                          color: ctx.inkColor,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2.5),
                                                      decoration: BoxDecoration(
                                                        color: statusColor
                                                            .withValues(
                                                                alpha: 0.12),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                        border: Border.all(
                                                          color: statusColor
                                                              .withValues(
                                                                  alpha: 0.3),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        statusText,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: statusColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  item.reason,
                                                  style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: ctx.mutedColor),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // Zaxira ko'rsatkichi progress bar
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          minHeight: 5,
                                          backgroundColor: ctx.isDark
                                              ? const Color(0xFF28323E)
                                              : const Color(0xFFE2E8F0),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  statusColor),
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      // Tafsilotlar paneli va Harakat tugmalari
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: ctx.isDark
                                                      ? const Color(0xFF1E2833)
                                                      : const Color(0xFFF1F5F9),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Qoldiq: ${qty(item.currentStock)} ${item.product.unit}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: ctx.inkColor),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: ctx.isDark
                                                      ? const Color(0xFF1E2833)
                                                      : const Color(0xFFF1F5F9),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Kunlik: ~${item.dailyBurn.toStringAsFixed(1)} ${item.product.unit}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: ctx.mutedColor),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (item.recommendedQty > 0)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: ctx.isDark
                                                        ? AppColors.neonLime
                                                            .withValues(
                                                                alpha: 0.18)
                                                        : AppColors.greenSoft,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    'AI: +${qty(item.recommendedQty)} ${item.product.unit}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: ctx.isDark
                                                          ? AppColors.neonLime
                                                          : const Color(
                                                              0xFF065F46),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                FilledButton(
                                                  onPressed: () {
                                                    Navigator.pop(ctx);
                                                    _openQuickPurchase();
                                                  },
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: isCrit
                                                        ? AppColors.danger
                                                        : (ctx.isDark
                                                            ? AppColors.neonLime
                                                            : AppColors
                                                                .darkCard),
                                                    foregroundColor: isCrit
                                                        ? Colors.white
                                                        : (ctx.isDark
                                                            ? AppColors.ink
                                                            : Colors.white),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 14,
                                                        vertical: 8),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10)),
                                                  ),
                                                  child: const Text('Kirim',
                                                      style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w800)),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 14),

                    // Pastki umumiy harakat tugmalari
                    if (isNarrow)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openQuickPurchase();
                            },
                            icon: const Icon(Icons.shopping_bag_rounded,
                                size: 16),
                            label: const Text('+ Xarid Kirim Qilish',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.neonLime,
                              foregroundColor: AppColors.ink,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openQuickProduction();
                            },
                            icon: const Icon(
                                Icons.precision_manufacturing_rounded,
                                size: 16),
                            label: const Text('Sexga topshiriq ochish',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ctx.inkColor,
                              side: BorderSide(color: ctx.borderColor),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openQuickProduction();
                              },
                              icon: const Icon(
                                  Icons.precision_manufacturing_rounded,
                                  size: 16),
                              label: const Text('Sexga topshiriq ochish',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ctx.inkColor,
                                side: BorderSide(color: ctx.borderColor),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openQuickPurchase();
                              },
                              icon: const Icon(Icons.shopping_bag_rounded,
                                  size: 16),
                              label: const Text('+ Xarid Kirim Qilish',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.neonLime,
                                foregroundColor: AppColors.ink,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRestockAiCard(List<Product> products, List<SaleResult> sales,
      {double? height}) {
    final items = _calculateAiRecommendations(products, sales);
    final critical = items.where((x) => x.urgency == 'critical').toList();
    final warning = items.where((x) => x.urgency == 'warning').toList();
    final urgentList = [...critical, ...warning];

    return Container(
      height: height,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: critical.isNotEmpty
              ? AppColors.danger.withValues(alpha: 0.35)
              : (warning.isNotEmpty
                  ? const Color(0xFFD97706).withValues(alpha: 0.3)
                  : context.borderColor),
          width: critical.isNotEmpty ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: critical.isNotEmpty
                ? AppColors.danger.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Sarlavha va Urgency Chip
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: context.isDark
                        ? [const Color(0xFF283618), const Color(0xFF1B2A15)]
                        : [AppColors.neonLimeSoft, const Color(0xFFDCFCE7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.neonLime.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: AppColors.neonLime,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            MediaQuery.sizeOf(context).width < 500
                                ? 'AI Zaxira'
                                : 'AI Zaxira Tavsiyasi',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: context.inkColor,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.neonLime.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PROGNOZ',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: AppColors.neonLime,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sotuv surati & qoldiq tahlili',
                      style: TextStyle(fontSize: 11, color: context.mutedColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: critical.isNotEmpty
                      ? (context.isDark
                          ? const Color(0xFF3B1818)
                          : const Color(0xFFFEE2E2))
                      : (warning.isNotEmpty
                          ? (context.isDark
                              ? const Color(0xFF38250A)
                              : const Color(0xFFFEF3C7))
                          : (context.isDark
                              ? const Color(0xFF10281E)
                              : AppColors.greenSoft)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: critical.isNotEmpty
                        ? AppColors.danger.withValues(alpha: 0.5)
                        : (warning.isNotEmpty
                            ? const Color(0xFFD97706).withValues(alpha: 0.5)
                            : AppColors.green.withValues(alpha: 0.4)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      critical.isNotEmpty
                          ? Icons.error_rounded
                          : (warning.isNotEmpty
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_rounded),
                      size: 13,
                      color: critical.isNotEmpty
                          ? AppColors.danger
                          : (warning.isNotEmpty
                              ? const Color(0xFFD97706)
                              : AppColors.green),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      critical.isNotEmpty
                          ? '${critical.length} ta kritik'
                          : (warning.isNotEmpty
                              ? '${warning.length} ta kam'
                              : 'Optimal'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: critical.isNotEmpty
                            ? AppColors.danger
                            : (warning.isNotEmpty
                                ? const Color(0xFFD97706)
                                : AppColors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. AI Aqlli Xulosa Banneri (Oldingi dummy sparkline o'rniga haqiqiy tahlil!)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: context.isDark
                    ? [const Color(0xFF131D19), const Color(0xFF18221D)]
                    : [const Color(0xFFF0FDF4), const Color(0xFFF7FEE7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: context.isDark
                    ? const Color(0xFF264233)
                    : const Color(0xFFBBF7D0),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.psychology_rounded,
                  size: 18,
                  color: AppColors.greenBright,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.inkColor,
                        height: 1.35,
                      ),
                      children: critical.isNotEmpty
                          ? [
                              const TextSpan(
                                text: 'Diqqat: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.danger),
                              ),
                              TextSpan(
                                text: '${critical.first.product.name} ',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: critical.length > 1
                                    ? "va yana ${critical.length - 1} ta tovar tez orada tugaydi. Zudlik bilan to'ldirish tavsiya etiladi."
                                    : 'zaxirasi kritik darajada. Xarid kirimi qilish tavsiya etiladi.',
                                style: TextStyle(color: context.subtextColor),
                              ),
                            ]
                          : warning.isNotEmpty
                              ? [
                                  const TextSpan(
                                    text: 'Ogohlantirish: ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFD97706)),
                                  ),
                                  TextSpan(
                                    text:
                                        '${warning.length} ta tovar xavfsiz zaxira chegarasidan past. Oldindan buyurtma bering.',
                                    style:
                                        TextStyle(color: context.subtextColor),
                                  ),
                                ]
                              : [
                                  const TextSpan(
                                    text: 'Holat barqaror: ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.green),
                                  ),
                                  TextSpan(
                                    text:
                                        "Barcha asosiy tovarlar yetarli. Keyingi 14 kunlik zaxira ta'minlangan.",
                                    style:
                                        TextStyle(color: context.subtextColor),
                                  ),
                                ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Tavsiya etilgan tovarlar ro'yxati
          Builder(
            builder: (context) {
              final itemsListView = urgentList.isNotEmpty
                  ? ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: urgentList.take(2).length,
                      shrinkWrap: height == null,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, __) => const SizedBox(height: 7),
                      itemBuilder: (_, i) {
                        final it = urgentList[i];
                        final isCrit = it.urgency == 'critical';
                        final isOut = it.currentStock <= 0;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: context.isDark
                                ? const Color(0xFF1A222C)
                                : const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isCrit
                                  ? AppColors.danger.withValues(alpha: 0.3)
                                  : context.borderColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              ProductThumbnail(
                                imageUrl: it.product.imageUrl,
                                name: it.product.name,
                                size: 34,
                                borderRadius: 10,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      it.product.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: context.inkColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: isOut
                                                ? AppColors.danger
                                                    .withValues(alpha: 0.15)
                                                : (isCrit
                                                    ? const Color(0xFFF59E0B)
                                                        .withValues(alpha: 0.15)
                                                    : context.borderColor
                                                        .withValues(
                                                            alpha: 0.3)),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isOut
                                                ? '🔥 Tugagan'
                                                : (it.daysRemaining <= 5
                                                    ? '⏳ ~${it.daysRemaining} kun'
                                                    : 'Qoldiq: ${qty(it.currentStock)}'),
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: isOut
                                                  ? AppColors.danger
                                                  : (isCrit
                                                      ? const Color(0xFFD97706)
                                                      : context.mutedColor),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '~${it.dailyBurn.toStringAsFixed(1)} ${it.product.unit}/k',
                                          style: TextStyle(
                                              fontSize: 9.5,
                                              color: context.mutedColor),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: isCrit
                                          ? AppColors.danger
                                              .withValues(alpha: 0.12)
                                          : (context.isDark
                                              ? AppColors.neonLime
                                                  .withValues(alpha: 0.18)
                                              : AppColors.greenSoft),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isCrit
                                            ? AppColors.danger
                                                .withValues(alpha: 0.4)
                                            : (context.isDark
                                                ? AppColors.neonLime
                                                    .withValues(alpha: 0.5)
                                                : AppColors.green
                                                    .withValues(alpha: 0.3)),
                                      ),
                                    ),
                                    child: Text(
                                      '+${qty(it.recommendedQty)} ${it.product.unit}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        color: isCrit
                                            ? AppColors.danger
                                            : (context.isDark
                                                ? AppColors.neonLime
                                                : const Color(0xFF065F46)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tavsiya',
                                    style: TextStyle(
                                        fontSize: 8.5,
                                        color: context.mutedColor),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? const Color(0xFF142018)
                              : const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.verified_rounded,
                                color: AppColors.green, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                "Barcha tovarlar zaxirasi me'yorda!",
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: context.inkColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );

              return height != null
                  ? Expanded(child: itemsListView)
                  : itemsListView;
            },
          ),
          const SizedBox(height: 10),

          // 4. Pastki harakat tugmalari
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showAiRestockDetails(items),
                  icon: const Icon(Icons.analytics_outlined, size: 15),
                  label: Text(
                    'Batafsil (${items.length})',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.inkColor,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openQuickPurchase,
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 15),
                  label: const Text(
                    'Tezkor Kirim',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.neonLime,
                    foregroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Pastki o'ng: Ishlab Chiqarish Topshiriqlari (Still Not Arrived / Production)
  // ---------------------------------------------------------------------------

  Widget _buildTasksQueueCard(List<ProductionTask> tasks, {double? height}) {
    final openTasks = tasks.where((t) => t.status != 'done').toList();

    return Container(
      height: height,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: height != null
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Topshiriqlar Nazorati',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? const Color(0xFF2B3310)
                      : AppColors.neonLimeSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${openTasks.length} ta faol',
                  style: TextStyle(
                      color: context.isDark
                          ? AppColors.neonLime
                          : AppColors.neonLimeDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (openTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text('Kechikkan topshiriqlar yo‘q',
                      style: TextStyle(color: context.mutedColor))),
            )
          else
            for (final t in openTasks.take(3)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: context.isDark
                          ? const Color(0xFF1E2838)
                          : const Color(0xFFE0E7FF),
                      child: Text(
                        t.workerName.isNotEmpty ? t.workerName[0] : 'W',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: context.isDark
                                ? const Color(0xFF818CF8)
                                : const Color(0xFF3730A3)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.productName,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: context.inkColor)),
                          Text('Ishchi: ${t.workerName}',
                              style: TextStyle(
                                  color: context.mutedColor, fontSize: 10)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.pillColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${qty(t.produced)}/${qty(t.planned)}',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: context.inkColor)),
                    ),
                  ],
                ),
              ),
            ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => widget.onNavigate?.call(5),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.inkColor,
                side: BorderSide(color: context.borderColor),
              ),
              child: const Text('Barcha topshiriqlar'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat Kartalari (Vault qora va oq kartalari)
// ---------------------------------------------------------------------------

class _TopDarkStatCard extends StatelessWidget {
  const _TopDarkStatCard({
    required this.title,
    required this.value,
    required this.badgeText,
    required this.icon,
    this.onTap,
    this.height,
  });

  final String title;
  final String value;
  final String badgeText;
  final IconData icon;
  final VoidCallback? onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          height: height,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: height != null
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.neonLime,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: AppColors.ink, size: 20),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22262B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_outward_rounded,
                        color: Colors.white, size: 16),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8E959E),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A2B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.greenBright,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopLightStatCard extends StatelessWidget {
  const _TopLightStatCard({
    required this.title,
    required this.value,
    required this.badgeText,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.onTap,
    this.height,
  });

  final String title;
  final String value;
  final String badgeText;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback? onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          height: height,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: height != null
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? iconColor.withValues(alpha: 0.18)
                          : iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: context.pillColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_outward_rounded,
                        color: context.inkColor, size: 16),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.mutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: TextStyle(
                        color: context.inkColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? const Color(0xFF1E3A2B)
                      : AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.isDark
                        ? AppColors.greenBright
                        : const Color(0xFF065F46),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopGaugeStatCard extends StatelessWidget {
  const _TopGaugeStatCard({
    required this.title,
    required this.value,
    required this.subText,
    required this.icon,
    required this.ringColor,
    this.onTap,
    this.height,
  });

  final String title;
  final String value;
  final String subText;
  final IconData icon;
  final Color ringColor;
  final VoidCallback? onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          height: height,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: height != null
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? const Color(0xFF2B3310)
                          : AppColors.neonLimeSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        color:
                            context.isDark ? AppColors.neonLime : AppColors.ink,
                        size: 20),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: context.pillColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_outward_rounded,
                        color: context.inkColor, size: 16),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.mutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: TextStyle(
                        color: context.inkColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? const Color(0xFF332512)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  subText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ringColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopSpeedGaugeCard extends StatelessWidget {
  const _TopSpeedGaugeCard({
    required this.title,
    required this.value,
    required this.badgeText,
    required this.isPositive,
    required this.icon,
    this.onTap,
    this.height,
  });

  final String title;
  final String value;
  final String badgeText;
  final bool isPositive;
  final IconData icon;
  final VoidCallback? onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          height: height,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: height != null
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? (isPositive
                              ? const Color(0xFF132A1E)
                              : const Color(0xFF331515))
                          : (isPositive
                              ? AppColors.greenSoft
                              : AppColors.dangerSoft),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        color: isPositive ? AppColors.green : AppColors.danger,
                        size: 20),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: context.pillColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_outward_rounded,
                        color: context.inkColor, size: 16),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.mutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: TextStyle(
                        color: context.inkColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? (isPositive
                          ? const Color(0xFF1E3A2B)
                          : const Color(0xFF3B1E1E))
                      : (isPositive
                          ? AppColors.greenSoft
                          : AppColors.dangerSoft),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPositive
                        ? (context.isDark
                            ? AppColors.greenBright
                            : const Color(0xFF065F46))
                        : AppColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  color: context.mutedColor,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveSplineChartPainter extends CustomPainter {
  final List<double> salesPoints;
  final List<String> labels;
  final double scaleSaleMax;
  final int? hoverIndex;
  final bool isDark;

  _WaveSplineChartPainter({
    required this.salesPoints,
    required this.labels,
    required this.scaleSaleMax,
    this.hoverIndex,
    this.isDark = false,
  });

  String _formatShortMoney(double v) {
    if (v >= 1000000000) {
      final val = v / 1000000000;
      return '${val.toStringAsFixed(val.truncateToDouble() == val ? 0 : 1)} mlrd';
    }
    if (v >= 1000000) {
      final val = v / 1000000;
      return '${val.toStringAsFixed(val.truncateToDouble() == val ? 0 : 1)} mln';
    }
    if (v >= 1000) {
      final val = v / 1000;
      return '${val.toStringAsFixed(val.truncateToDouble() == val ? 0 : 1)} ming';
    }
    return v.toStringAsFixed(0);
  }

  Path _buildSpline(List<Offset> points, double baselineY,
      {double tension = 0.35}) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path;

    if (points.length == 2) {
      final p0 = points[0];
      final p1 = points[1];
      final cx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
      return path;
    }

    final n = points.length;
    for (int i = 0; i < n - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i < n - 2 ? points[i + 2] : points[i + 1];

      final d1x = (p2.dx - p0.dx) * tension;
      final d1y = (p2.dy - p0.dy) * tension;
      final d2x = (p3.dx - p1.dx) * tension;
      final d2y = (p3.dy - p1.dy) * tension;

      double c1y = p1.dy + d1y;
      double c2y = p2.dy - d2y;
      if (c1y > baselineY) c1y = baselineY;
      if (c2y > baselineY) c2y = baselineY;

      final c1 = Offset(p1.dx + d1x, c1y);
      final c2 = Offset(p2.dx - d2x, c2y);

      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const topPad = 14.0;
    const bottomPad = 26.0;
    const padX = 14.0;
    final usableW = w - (padX * 2);
    final baselineY = h - bottomPad;
    final drawH = baselineY - topPad;

    final safeSaleMax = scaleSaleMax > 0 ? scaleSaleMax : 1.0;

    // Y o'qi gorizontal chiziqlari (3 ta qator)
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF212836) : const Color(0xFFEFF2F6)
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 1; i <= 3; i++) {
      final y = topPad + (drawH * (i / 4));
      canvas.drawLine(Offset(padX, y), Offset(w - padX, y), gridPaint);
    }

    // Yuqori chiziqda: Sotuv shkalasi
    if (scaleSaleMax > 0) {
      textPainter.text = TextSpan(
        text: 'Maksimal: ${_formatShortMoney(scaleSaleMax)}',
        style: TextStyle(
          fontSize: 9,
          color: (isDark ? const Color(0xFF10B981) : AppColors.green)
              .withValues(alpha: 0.95),
          fontWeight: FontWeight.w700,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, const Offset(padX + 2, topPad - 2));
    }

    if (salesPoints.isEmpty) return;

    final n = salesPoints.length;

    // Nuqtalarni hisoblash - savdo to'liq dinamik balandlikda (0% - 85%)
    final saleCoords = <Offset>[];

    for (int i = 0; i < n; i++) {
      final x = padX + (n > 1 ? (usableW * i / (n - 1)) : (usableW / 2));
      final oRatio = (safeSaleMax > 0 ? (salesPoints[i] / safeSaleMax) : 0.0)
          .clamp(0.0, 1.0);

      final ySale = baselineY - (oRatio * drawH * 0.85);
      saleCoords.add(Offset(x, ySale));
    }

    // 1. Sotuv Spline yo'li
    final salePath = _buildSpline(saleCoords, baselineY);

    // Gradient ostki to'ldirish (Sotuv)
    final fillPathSale = Path.from(salePath)
      ..lineTo(saleCoords.last.dx, baselineY)
      ..lineTo(saleCoords.first.dx, baselineY)
      ..close();

    final fill2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (isDark ? const Color(0xFF10B981) : AppColors.green)
              .withValues(alpha: isDark ? 0.25 : 0.18),
          (isDark ? const Color(0xFF10B981) : AppColors.green)
              .withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, topPad, w, drawH));
    canvas.drawPath(fillPathSale, fill2);

    // Chiziqni chizish
    final stroke2 = Paint()
      ..color = isDark ? const Color(0xFF10B981) : AppColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(salePath, stroke2);

    // Marker nuqtalar
    final saleDotPaint = Paint()
      ..color = isDark ? const Color(0xFF10B981) : AppColors.green;
    final saleDotBorder = Paint()
      ..color = isDark ? const Color(0xFF161B22) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final pt in saleCoords) {
      canvas.drawCircle(pt, 3.5, saleDotPaint);
      canvas.drawCircle(pt, 3.5, saleDotBorder);
    }

    // Aktiv hover ko'rsatkichi
    if (hoverIndex != null &&
        hoverIndex! >= 0 &&
        hoverIndex! < saleCoords.length) {
      final activeSaleCoord = saleCoords[hoverIndex!];

      // Vertikal yo'naltiruvchi chiziq
      final guidePaint = Paint()
        ..color =
            (isDark ? Colors.white : AppColors.ink).withValues(alpha: 0.18)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(activeSaleCoord.dx, topPad),
        Offset(activeSaleCoord.dx, baselineY),
        guidePaint,
      );

      // Aktiv Sotuv beacon halqasi
      canvas.drawCircle(
        activeSaleCoord,
        8.0,
        Paint()
          ..color = (isDark ? const Color(0xFF10B981) : AppColors.green)
              .withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        activeSaleCoord,
        5.0,
        Paint()..color = isDark ? const Color(0xFF161B22) : Colors.white,
      );
      canvas.drawCircle(
        activeSaleCoord,
        3.5,
        Paint()..color = isDark ? const Color(0xFF10B981) : AppColors.green,
      );
    }

    // X-o'qi etiketkalari (Labels)
    final bool isTight = (w < 420 && labels.length > 6);
    for (int i = 0; i < labels.length && i < n; i++) {
      if (isTight && i % 2 != 0 && i != labels.length - 1 && i != hoverIndex) {
        continue;
      }
      final x = saleCoords[i].dx;
      final isHovered = (hoverIndex != null && i == hoverIndex);

      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          fontSize: isTight ? 9 : 10,
          color: isHovered
              ? (isDark ? Colors.white : AppColors.ink)
              : (isDark ? const Color(0xFF8B949E) : AppColors.muted),
          fontWeight: isHovered ? FontWeight.w800 : FontWeight.w600,
        ),
      );
      textPainter.layout();
      final maxClampedX = math.max(2.0, w - textPainter.width - 2);
      final clampedX = (x - (textPainter.width / 2)).clamp(2.0, maxClampedX);
      textPainter.paint(canvas, Offset(clampedX, baselineY + 8));
    }
  }

  @override
  bool shouldRepaint(covariant _WaveSplineChartPainter old) => true;
}

class _VaultCircleRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  _VaultCircleRingPainter(
      {required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
        rect, -math.pi / 2, 2 * math.pi * progress, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _VaultCircleRingPainter old) =>
      old.progress != progress || old.color != color;
}

class _MiniSparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, h * 0.8)
      ..lineTo(w * 0.3, h * 0.6)
      ..lineTo(w * 0.6, h * 0.7)
      ..lineTo(w * 0.85, h * 0.2)
      ..lineTo(w, h * 0.35);

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AiRestockItem {
  final Product product;
  final double currentStock;
  final double totalSold;
  final double dailyBurn;
  final int daysRemaining;
  final double recommendedQty;
  final String urgency; // 'critical', 'warning', 'optimal'
  final String reason;

  const AiRestockItem({
    required this.product,
    required this.currentStock,
    required this.totalSold,
    required this.dailyBurn,
    required this.daysRemaining,
    required this.recommendedQty,
    required this.urgency,
    required this.reason,
  });
}
