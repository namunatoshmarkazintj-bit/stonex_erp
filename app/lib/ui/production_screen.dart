import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import '../state/auth_controller.dart';
import 'common.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});

  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  late Future<List<ProductionTask>> _future;
  late Future<List<SaleResult>> _ordersFuture;
  late Future<List<dynamic>> _combinedFuture;
  String _selectedFilter = 'Barchasi';
  String _activeTab = 'tasks'; // 'tasks' (Sex topshiriqlari) yoki 'orders' (Buyurtmalardan kesish)
  final _searchCtrl = TextEditingController();

  ProductionRepository get _repo => context.read<AppRepositories>().production;

  @override
  void initState() {
    super.initState();
    _future = _repo.list();
    _ordersFuture = context.read<AppRepositories>().sales.listSales(limit: 60).catchError((_) => <SaleResult>[]);
    _combinedFuture = Future.wait([_future, _ordersFuture]);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _repo.list();
      _ordersFuture = context.read<AppRepositories>().sales.listSales(limit: 60).catchError((_) => <SaleResult>[]);
      _combinedFuture = Future.wait([_future, _ordersFuture]);
    });
  }

  bool _isCuttingItem(SaleItemRecord item) {
    final name = item.productName.toLowerCase();
    return item.isCut ||
        name.contains('kesish') ||
        name.contains('silliqlash') ||
        name.contains('faska') ||
        name.contains('chizish') ||
        name.contains('ishlov') ||
        item.productName.contains('[');
  }


  String _cuttingFilter = 'pending'; // 'pending' | 'assigned' | 'all'

  bool _isOrderAssigned(SaleResult o, List<ProductionTask> tasks) {
    final needle1 = 'Buyurtma #${o.id}';
    final needle2 = '[Order #${o.id}]';
    return tasks.any((t) =>
        t.status != 'rejected' &&
        t.status != 'cancelled' &&
        ((t.note?.contains(needle1) ?? false) || (t.note?.contains(needle2) ?? false)));
  }

  bool _isOrderRejected(SaleResult o, List<ProductionTask> tasks) {
    if (_isOrderAssigned(o, tasks)) return false;
    final needle1 = 'Buyurtma #${o.id}';
    final needle2 = '[Order #${o.id}]';
    return tasks.any((t) =>
        t.status == 'rejected' &&
        ((t.note?.contains(needle1) ?? false) || (t.note?.contains(needle2) ?? false)));
  }

  ProductionTask? _getOrderTask(SaleResult o, List<ProductionTask> tasks) {
    final needle1 = 'Buyurtma #${o.id}';
    final needle2 = '[Order #${o.id}]';
    return tasks.where((t) =>
        ((t.note?.contains(needle1) ?? false) || (t.note?.contains(needle2) ?? false))).firstOrNull;
  }

  Future<void> _reject(ProductionTask t) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 10),
            Text('Topshiriqni qaytarish', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ushbu topshiriqni (${t.productName}) bajara olmasligingiz sababli ish boshqaruvchiga qaytarmoqchimisiz?',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Qaytarish sababi (ixtiyoriy)',
                hintText: 'Masalan: Stanok band / Boshqa shoshilinch ish chiqdi',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Qaytarish', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        await _repo.reject(t.id, reason: reasonCtrl.text.trim());
        if (mounted) {
          showMessage(context, 'Topshiriq ish boshqaruvchiga qaytarildi');
          _reload();
        }
      } catch (e) {
        if (mounted) showMessage(context, 'Xatolik: $e', error: true);
      }
    }
  }

  ({String? cutSpec, int? pieces, String? cleanStoneName}) _parseCuttingItemDetails(String text) {
    final dimMatch = RegExp(r'(\d+(?:\.\d+)?\s*(?:sm|m)?\s*[×xX*]\s*\d+(?:\.\d+)?\s*(?:sm|m)?)').firstMatch(text);
    final piecesMatch = RegExp(r'(\d+)\s*dona').firstMatch(text);
    final stoneMatch = RegExp(r'\[([^\]]+)\]').firstMatch(text);

    return (
      cutSpec: dimMatch?.group(1),
      pieces: piecesMatch != null ? int.tryParse(piecesMatch.group(1)!) : null,
      cleanStoneName: stoneMatch?.group(1),
    );
  }

  Widget _buildTaskSpecsBox(ProductionTask t, BuildContext context) {
    final note = t.note ?? '';
    final hasOrderId = t.orderId != null;
    final hasCutSpec = (t.cutSpec != null && t.cutSpec!.trim().isNotEmpty);
    final hasPieces = t.cutPieces != null && t.cutPieces! > 0;

    String? dimStr;
    if (hasCutSpec) {
      dimStr = t.cutSpec;
    } else if (t.cutLength != null && t.cutWidth != null) {
      dimStr = '${t.cutLength}m × ${t.cutWidth}m';
    } else {
      dimStr = RegExp(r'(\\d+(?:\\.\\d+)?\\s*(?:sm|m)?\\s*[×xX*]\\s*\\d+(?:\\.\\d+)?\\s*(?:sm|m)?)').firstMatch(note)?.group(1);
    }

    final piecesStr = hasPieces ? '${t.cutPieces} dona' : RegExp(r'(\\d+\\s*dona)').firstMatch(note)?.group(1);
    final hasPolish = note.toLowerCase().contains('silliqlash') || t.productName.toLowerCase().contains('silliqlash');
    final hasChamfer = note.toLowerCase().contains('faska') || t.productName.toLowerCase().contains('faska');
    final hasGroove = note.toLowerCase().contains('chizish') || t.productName.toLowerCase().contains('chizish');

    // Clean note for display
    var cleanNote = note;
    if (cleanNote.contains('Buyurtma #')) {
      cleanNote = cleanNote.replaceFirst(RegExp(r'Buyurtma #\\d+[^:]*:\\s*'), '');
    }
    if (dimStr != null) {
      cleanNote = cleanNote.replaceAll(dimStr, '');
    }
    cleanNote = cleanNote.replaceAll(RegExp(r'\\[[^\\]]*\\]'), '').replaceAll('—', '').replaceAll('|', '').trim();

    final isDark = context.isDark;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13222F) : const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF0284C7).withValues(alpha: 0.4) : const Color(0xFFBAE6FD),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.architecture_rounded, size: 16, color: Color(0xFF0284C7)),
              const SizedBox(width: 6),
              const Text(
                '📐 Kesish & Ishlov tafsilotlari:',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Color(0xFF0284C7),
                ),
              ),
              const Spacer(),
              if (hasOrderId)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Buyurtma #${t.orderId}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF0284C7))),
                ),
              if (t.isRejected) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Qaytarilgan', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              if (dimStr != null && dimStr.isNotEmpty)
                _buildSpecTag('📏 O‘lchami: $dimStr', const Color(0xFF0284C7), isDark),
              if (piecesStr != null && piecesStr.isNotEmpty)
                _buildSpecTag('📦 Soni: $piecesStr', const Color(0xFF7C3AED), isDark),
              if (hasPolish)
                _buildSpecTag('✨ Silliqlash', const Color(0xFF059669), isDark),
              if (hasChamfer)
                _buildSpecTag('📐 Faska', const Color(0xFFD97706), isDark),
              if (hasGroove)
                _buildSpecTag('〰️ Chizish', const Color(0xFFD97706), isDark),
              if (dimStr == null && piecesStr == null)
                _buildSpecTag('📦 Reja: ${qty(t.planned)} ${t.unit}', const Color(0xFF475569), isDark),
            ],
          ),
          if (cleanNote.isNotEmpty && cleanNote != 'null') ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_rounded, size: 14, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    cleanNote,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecTag(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isDark ? color.withValues(alpha: 0.95) : color,
        ),
      ),
    );
  }

  Future<void> _showTaskDetails(ProductionTask t) async {
    final isDark = context.isDark;
    final note = t.note ?? '';
    final hasCutSpec = (t.cutSpec != null && t.cutSpec!.trim().isNotEmpty);
    String? dimStr;
    if (hasCutSpec) {
      dimStr = t.cutSpec;
    } else if (t.cutLength != null && t.cutWidth != null) {
      dimStr = '${t.cutLength}m × ${t.cutWidth}m';
    } else {
      dimStr = RegExp(r'(\\d+(?:\\.\\d+)?\\s*(?:sm|m)?\\s*[×xX*]\\s*\\d+(?:\\.\\d+)?\\s*(?:sm|m)?)').firstMatch(note)?.group(1);
    }
    final piecesStr = (t.cutPieces != null && t.cutPieces! > 0)
        ? '${t.cutPieces} dona'
        : RegExp(r'(\\d+\\s*dona)').firstMatch(note)?.group(1);
    final hasPolish = note.toLowerCase().contains('silliqlash') || t.productName.toLowerCase().contains('silliqlash');
    final hasChamfer = note.toLowerCase().contains('faska') || t.productName.toLowerCase().contains('faska');
    final hasGroove = note.toLowerCase().contains('chizish') || t.productName.toLowerCase().contains('chizish');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: context.dialogBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.architecture_rounded, color: Color(0xFF0284C7), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.productName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Topshiriq #${t.id}' + (t.orderId != null ? ' (Buyurtma #${t.orderId})' : ''),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF13222F) : const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📐 KESISH VA O‘LCHAMLAR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Kesish o‘lchami (Eni × Bo‘yi):', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              dimStr ?? 'Umumiy hajm',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF0284C7)),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Soni / Dona:', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              piecesStr ?? '${qty(t.planned)} ${t.unit}',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF7C3AED)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Jami rejalashtirilgan hajm:', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
                      Text('${qty(t.planned)} ${t.unit}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tayyorlangan hajm:', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
                      Text('${qty(t.produced)} ${t.unit}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.green)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Biriktirilgan usta:', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
                      Text(t.workerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasPolish)
                  _buildSpecTag('✨ Silliqlash talab etiladi', const Color(0xFF059669), isDark),
                if (hasChamfer)
                  _buildSpecTag('📐 Faska ochish talab etiladi', const Color(0xFFD97706), isDark),
                if (hasGroove)
                  _buildSpecTag('〰️ Chizish talab etiladi', const Color(0xFFD97706), isDark),
              ],
            ),
            if (t.note != null && t.note!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Topshiriq izohi / Mijoz talabi:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 6),
                    Text(t.note!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Yopish', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                if (t.status != 'done' && !t.isPendingApproval && !t.isRejected) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _report(t);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                        foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Hisobot kiritish', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _report(ProductionTask t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ProductionReportDialog(task: t, repo: _repo),
    );

    if (ok == true && mounted) {
      showMessage(context, 'Bajarilgan ish omborga kirim qilindi');
      _reload();
    }
  }

  Future<void> _approve(ProductionTask t) async {
    try {
      await _repo.approve(t.id);
      if (mounted) {
        showMessage(context, '🟢 OTK tasdiqlandi: Mahsulot omborga kirdi va xomashyo sarfi hisoblandi');
        _reload();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Xatolik: $e', error: true);
    }
  }

  Future<void> _create({
    int? prefillProductId,
    double? prefillQty,
    String? prefillNote,
    int? prefillWorkerId,
    int? prefillOrderId,
    String? prefillCutSpec,
    int? prefillCutPieces,
    String? prefillCustomerInfo,
    List<SaleResult>? availableOrders,
  }) async {
    final repos = context.read<AppRepositories>();
    final orders = availableOrders ?? (await _ordersFuture.catchError((_) => <SaleResult>[]));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => TaskCreateDialog(
        productionRepo: repos.production,
        productRepo: repos.products,
        initialProductId: prefillProductId,
        initialPlanned: prefillQty,
        initialNote: prefillNote,
        initialWorkerId: prefillWorkerId,
        initialOrderId: prefillOrderId,
        initialCutSpec: prefillCutSpec,
        initialCutPieces: prefillCutPieces,
        initialCustomerInfo: prefillCustomerInfo,
        availableOrders: orders.where((o) => o.status == 'order').toList(),
      ),
    );
    if (ok == true && mounted) {
      showMessage(context, 'Topshiriq ishchiga muvaffaqiyatli biriktirildi');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final curUser = context.watch<AuthController>().user;
    final isManager = curUser?.role == Role.admin || curUser?.role == Role.ishBoshqaruvchi;
    final filters = ['Barchasi', 'Kutilmoqda (OTK)', 'Jarayonda', 'Yakunlangan', 'Qaytarilgan'];

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => _create(),
              icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.neonLime),
              label: const Text('Yangi topshiriq'),
            )
          : null,
      body: FutureBuilder<List<dynamic>>(
        future: _combinedFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorView(message: snap.error.toString(), onRetry: _reload);
          }

          final allTasks = (snap.data?[0] as List<ProductionTask>?) ?? [];
          final allOrders = (snap.data?[1] as List<SaleResult>?) ?? [];

          // Kesish va toshga ishlov berish talab qilingan barcha buyurtmalar
          final allCuttingOrders = allOrders.where((o) =>
              o.status == 'order' && o.items.any((it) => _isCuttingItem(it))
          ).toList();

          final pendingCuttingOrders = allCuttingOrders.where((o) => !_isOrderAssigned(o, allTasks)).toList();
          final assignedCuttingOrders = allCuttingOrders.where((o) => _isOrderAssigned(o, allTasks)).toList();

          List<SaleResult> displayedCuttingOrders;
          if (_cuttingFilter == 'assigned') {
            displayedCuttingOrders = assignedCuttingOrders;
          } else if (_cuttingFilter == 'all') {
            displayedCuttingOrders = allCuttingOrders;
          } else {
            displayedCuttingOrders = pendingCuttingOrders;
          }
          final cuttingOrders = displayedCuttingOrders;

          var displayTasks = List<ProductionTask>.from(allTasks);

          if (_selectedFilter == 'Kutilmoqda (OTK)') {
            displayTasks = displayTasks.where((t) => t.isPendingApproval).toList();
          } else if (_selectedFilter == 'Jarayonda') {
            displayTasks = displayTasks.where((t) => t.status != 'done' && !t.isPendingApproval && !t.isRejected).toList();
          } else if (_selectedFilter == 'Yakunlangan') {
            displayTasks = displayTasks.where((t) => t.status == 'done').toList();
          } else if (_selectedFilter == 'Qaytarilgan') {
            displayTasks = displayTasks.where((t) => t.isRejected).toList();
          }

          final q = _searchCtrl.text.trim().toLowerCase();
          if (q.isNotEmpty) {
            displayTasks = displayTasks.where((t) {
              return t.productName.toLowerCase().contains(q) ||
                  t.workerName.toLowerCase().contains(q) ||
                  t.id.toString().contains(q) ||
                  (t.note ?? '').toLowerCase().contains(q);
            }).toList();
          }

          final total = allTasks.length;
          final inProgress = allTasks.where((t) => t.status != 'done' && !t.isPendingApproval).length;
          final pendingOtk = allTasks.where((t) => t.isPendingApproval).length;
          final done = allTasks.where((t) => t.status == 'done').length;
          final completionRate = total > 0 ? (done / total * 100) : 0.0;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900;

                return ListView(
                  padding: EdgeInsets.fromLTRB(isDesktop ? 28.0 : 12.0, 12, isDesktop ? 28.0 : 12.0, 80),
                  children: [
                    // Ish boshqaruvchi va Admin uchun Bo'lim Tanlagich (Topshiriqlar vs Buyurtmalardan kesish)
                    if (isManager) ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTabPill(
                                label: 'Sex topshiriqlari ($total)',
                                icon: Icons.precision_manufacturing_rounded,
                                active: _activeTab == 'tasks',
                                onTap: () => setState(() => _activeTab = 'tasks'),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _buildTabPill(
                                label: 'Buyurtmalardan kesish (${pendingCuttingOrders.length})',
                                icon: Icons.content_cut_rounded,
                                active: _activeTab == 'orders',
                                onTap: () => setState(() => _activeTab = 'orders'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_activeTab == 'orders' && isManager) ...[
                      // Buyurtmalardan kesish topshiriqlari ko'rinishi
                      if (cuttingOrders.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(48),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.green),
                                SizedBox(height: 12),
                                Text(
                                  _cuttingFilter == 'pending' ? 'Kutilayotgan biriktirilmagan buyurtmalar yo‘q' : (_cuttingFilter == 'assigned' ? 'Biriktirilgan buyurtmalar hozircha yo‘q' : 'Kesish talab qilingan buyurtmalar yo‘q'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Kassadan yangi tosh kesish xizmati bilan buyurtma olinganda bu yerda avtomatik ko‘rinadi',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Buyurtmalar:',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            ChoiceChip(
                              label: Text('Kutilayotganlar (${pendingCuttingOrders.length})'),
                              selected: _cuttingFilter == 'pending',
                              onSelected: (_) => setState(() => _cuttingFilter = 'pending'),
                            ),
                            ChoiceChip(
                              label: Text('Biriktirilganlar (${assignedCuttingOrders.length})'),
                              selected: _cuttingFilter == 'assigned',
                              onSelected: (_) => setState(() => _cuttingFilter = 'assigned'),
                            ),
                            ChoiceChip(
                              label: Text('Barchasi (${allCuttingOrders.length})'),
                              selected: _cuttingFilter == 'all',
                              onSelected: (_) => setState(() => _cuttingFilter = 'all'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cuttingOrders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _buildOrderCuttingCard(context, cuttingOrders[i], allCuttingOrders, allTasks),
                        ),
                      ],
                    ] else ...[
                      // Sex topshiriqlari ko'rinishi
                      if (isManager && cuttingOrders.isNotEmpty) ...[
                        InkWell(
                          onTap: () => setState(() => _activeTab = 'orders'),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.content_cut_rounded, color: Color(0xFFF59E0B), size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${cuttingOrders.length} ta buyurtmada tosh kesish kutilmoqda. Ishchilarga biriktirish uchun bosing →',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFF59E0B)),
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFF59E0B)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Yuqori statistika paneli
                      if (isDesktop)
                        Row(
                          children: [
                            Expanded(child: _buildStat(context, 'Jami Topshiriqlar', '$total ta', Icons.precision_manufacturing_rounded, AppColors.neonLime, true)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Kutilmoqda (OTK)', '$pendingOtk ta', Icons.verified_rounded, const Color(0xFFF59E0B), false)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Jarayondagi Ishlar', '$inProgress ta', Icons.pending_actions_rounded, const Color(0xFF3B82F6), false)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildStat(context, 'Bajarilgan Ishlar', '$done ta', Icons.check_circle_rounded, AppColors.green, false)),
                          ],
                        )
                      else ...[
                        _buildStat(context, 'Jami Topshiriqlar', '$total ta', Icons.precision_manufacturing_rounded, AppColors.neonLime, true),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildStat(context, 'OTK kutilmoqda', '$pendingOtk ta', Icons.verified_rounded, const Color(0xFFF59E0B), false)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildStat(context, 'Jarayonda', '$inProgress ta', Icons.pending_actions_rounded, const Color(0xFF3B82F6), false)),
                          ],
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Qidiruv paneli
                      SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _searchCtrl,
                          style: TextStyle(fontSize: 13, color: context.inkColor, fontWeight: FontWeight.w500),
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: context.cardColor,
                            isDense: true,
                            hintText: 'Mahsulot nomi, izoh yoki ishchi ismi bo‘yicha qidirish...',
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.normal),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                            suffixIcon: _searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {});
                                    },
                                    splashRadius: 18,
                                    padding: EdgeInsets.zero,
                                  ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(color: context.borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(color: context.borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(color: context.isDark ? AppColors.neonLime : AppColors.ink, width: 1.5),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Filtrlar va Boshqaruv
                      Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final f in filters) ...[
                                    GestureDetector(
                                      onTap: () => setState(() => _selectedFilter = f),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: _selectedFilter == f
                                              ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                                              : context.cardColor,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: _selectedFilter == f
                                                ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
                                                : context.borderColor,
                                          ),
                                        ),
                                        child: Text(
                                          f,
                                          style: TextStyle(
                                            color: _selectedFilter == f
                                                ? (context.isDark ? AppColors.ink : Colors.white)
                                                : context.inkColor,
                                            fontSize: 12,
                                            fontWeight: _selectedFilter == f ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (isManager && isDesktop) ...[
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: () => _create(),
                              style: FilledButton.styleFrom(
                                backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                                foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              ),
                              icon: Icon(Icons.add, size: 18, color: context.isDark ? AppColors.ink : AppColors.neonLime),
                              label: const Text('Topshiriq', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Topshiriqlar ro'yxati
                      if (displayTasks.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(48),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.assignment_turned_in_outlined, size: 48, color: AppColors.muted),
                                SizedBox(height: 12),
                                Text('Topshiriqlar mavjud emas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayTasks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final t = displayTasks[i];
                            final isDone = t.status == 'done';
                            final progress = (t.planned > 0 ? (t.produced / t.planned) : 0.0).clamp(0.0, 1.0);
                            final percent = (progress * 100).toStringAsFixed(0);

                            if (isDesktop) {
                              return Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: context.cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: t.isRejected
                                        ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                        : context.borderColor,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: isDone
                                                ? AppColors.green.withValues(alpha: 0.12)
                                                : (t.isPendingApproval
                                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                                                    : (t.isRejected
                                                        ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                                                        : AppColors.neonLime.withValues(alpha: 0.14))),
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Icon(
                                            isDone
                                                ? Icons.check_circle_rounded
                                                : (t.isPendingApproval
                                                    ? Icons.verified_rounded
                                                    : (t.isRejected
                                                        ? Icons.undo_rounded
                                                        : Icons.precision_manufacturing_rounded)),
                                            color: isDone
                                                ? AppColors.green
                                                : (t.isPendingApproval
                                                    ? const Color(0xFFF59E0B)
                                                    : (t.isRejected
                                                        ? const Color(0xFFEF4444)
                                                        : (context.isDark ? AppColors.neonLime : AppColors.ink))),
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // Mahsulot va Ishchi
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      t.productName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                                    ),
                                                  ),
                                                  if (t.orderId != null) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                                                      ),
                                                      child: Text(
                                                        'Buyurtma #${t.orderId}',
                                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF0284C7)),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.muted),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      t.workerName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Progress bari va miqdor
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      '${qty(t.produced)} / ${qty(t.planned)} ${t.unit}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '$percent%',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 12,
                                                      color: isDone ? AppColors.green : context.inkColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(6),
                                                child: LinearProgressIndicator(
                                                  value: progress,
                                                  minHeight: 7,
                                                  backgroundColor: context.pillColor,
                                                  color: isDone ? AppColors.green : AppColors.neonLime,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(width: 16),

                                        // Tugmalar
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: () => _showTaskDetails(t),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                side: BorderSide(color: context.borderColor),
                                              ),
                                              icon: const Icon(Icons.info_outline_rounded, size: 16),
                                              label: const Text('Batafsil', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isDone)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: context.isDark ? const Color(0xFF132D21) : AppColors.greenSoft,
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text('Yakunlandi',
                                                    style: TextStyle(
                                                      color: context.isDark ? AppColors.greenBright : const Color(0xFF065F46),
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 12,
                                                    )),
                                              )
                                            else if (t.isRejected)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                                                ),
                                                child: const Text('Qaytarilgan',
                                                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700, fontSize: 12)),
                                              )
                                            else if (t.isPendingApproval && isManager)
                                              FilledButton.icon(
                                                onPressed: () => _approve(t),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: AppColors.green,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                ),
                                                icon: const Icon(Icons.verified_rounded, size: 16),
                                                label: const Text('OTK Tasdiqlash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                              )
                                            else if (t.isPendingApproval)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFD97706).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.4)),
                                                ),
                                                child: const Text('OTK tekshiruvida',
                                                    style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w700, fontSize: 12)),
                                              )
                                            else ...[
                                              if (!isManager) ...[
                                                OutlinedButton.icon(
                                                  onPressed: () => _reject(t),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: const Color(0xFFEF4444),
                                                    side: const BorderSide(color: Color(0xFFEF4444), width: 1),
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  ),
                                                  icon: const Icon(Icons.undo_rounded, size: 16),
                                                  label: const Text('Qaytarish', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              FilledButton(
                                                onPressed: () => _report(t),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                                                  foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                ),
                                                child: const Text('Hisobot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                    // Tafsilotlar & Kesish ko'rsatmasi bloki (Ishchi va usta uchun)
                                    _buildTaskSpecsBox(t, context),
                                  ],
                                ),
                              );
                            }

                            // Mobile ko'rinishi
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: t.isRejected
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                      : context.borderColor,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: isDone
                                              ? AppColors.green.withValues(alpha: 0.12)
                                              : (t.isPendingApproval
                                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                                                  : (t.isRejected
                                                      ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                                                      : AppColors.neonLime.withValues(alpha: 0.14))),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          isDone
                                              ? Icons.check_circle_rounded
                                              : (t.isPendingApproval
                                                  ? Icons.verified_rounded
                                                  : (t.isRejected
                                                      ? Icons.undo_rounded
                                                      : Icons.precision_manufacturing_rounded)),
                                          color: isDone
                                              ? AppColors.green
                                              : (t.isPendingApproval
                                                  ? const Color(0xFFF59E0B)
                                                  : (t.isRejected
                                                      ? const Color(0xFFEF4444)
                                                      : (context.isDark ? AppColors.neonLime : AppColors.ink))),
                                          size: 20,
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
                                                    t.productName,
                                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                                  ),
                                                ),
                                                if (t.orderId != null) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      '#${t.orderId}',
                                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, color: Color(0xFF0284C7)),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              t.workerName,
                                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isDone)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: context.isDark ? const Color(0xFF132D21) : AppColors.greenSoft,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text('Yakunlandi',
                                              style: TextStyle(
                                                color: context.isDark ? AppColors.greenBright : const Color(0xFF065F46),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11,
                                              )),
                                        )
                                      else if (t.isRejected)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Text('Qaytarilgan',
                                              style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700, fontSize: 11)),
                                        ),
                                    ],
                                  ),
                                  // Tafsilotlar & Kesish ko'rsatmasi bloki
                                  _buildTaskSpecsBox(t, context),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('${qty(t.produced)} / ${qty(t.planned)} ${t.unit}',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                      Text('$percent%',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 12, color: isDone ? AppColors.green : context.inkColor)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 6,
                                      backgroundColor: context.pillColor,
                                      color: isDone ? AppColors.green : AppColors.neonLime,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // Tugmalar qatori
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _showTaskDetails(t),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            side: BorderSide(color: context.borderColor),
                                          ),
                                          icon: const Icon(Icons.info_outline_rounded, size: 16),
                                          label: const Text('Batafsil', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                        ),
                                      ),
                                      if (!isDone) ...[
                                        const SizedBox(width: 8),
                                        if (t.isPendingApproval && isManager)
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: () => _approve(t),
                                              style: FilledButton.styleFrom(backgroundColor: AppColors.green, padding: const EdgeInsets.symmetric(vertical: 10)),
                                              icon: const Icon(Icons.verified_rounded, size: 16),
                                              label: const Text('OTK Tasdiqlash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                            ),
                                          )
                                        else if (t.isPendingApproval)
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFD97706).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.4)),
                                              ),
                                              child: const Text('OTK tekshiruvida',
                                                  style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w700, fontSize: 12)),
                                            ),
                                          )
                                        else ...[
                                          if (!isManager) ...[
                                            OutlinedButton(
                                              onPressed: () => _reject(t),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(0xFFEF4444),
                                                side: const BorderSide(color: Color(0xFFEF4444)),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                              ),
                                              child: const Icon(Icons.undo_rounded, size: 18),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          Expanded(
                                            child: FilledButton(
                                              onPressed: () => _report(t),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                                                foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 10),
                                              ),
                                              child: const Text('Hisobot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },                        ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabPill({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: active
              ? (context.isDark ? AppColors.neonLime : AppColors.darkCard)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: active
                  ? (context.isDark ? AppColors.ink : Colors.white)
                  : context.mutedColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active
                      ? (context.isDark ? AppColors.ink : Colors.white)
                      : context.mutedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCuttingCard(BuildContext context, SaleResult order, List<SaleResult> allCuttingOrders, List<ProductionTask> allTasks) {
    final isAssigned = _isOrderAssigned(order, allTasks);
    final isRejected = _isOrderRejected(order, allTasks);
    final assignedTask = _getOrderTask(order, allTasks);
    final cutItems = order.items.where(_isCuttingItem).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFF59E0B), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Buyurtma #${order.id}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isAssigned
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : (isRejected ? const Color(0xFFEF4444).withValues(alpha: 0.15) : const Color(0xFFF59E0B).withValues(alpha: 0.14)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isAssigned
                                ? '✅ Biriktirilgan (${assignedTask?.workerName ?? "Usta"})'
                                : (isRejected ? '⚠️ Ishchi qaytargan' : 'Kesish kutilmoqda'),
                            style: TextStyle(
                              color: isAssigned
                                  ? const Color(0xFF059669)
                                  : (isRejected ? const Color(0xFFEF4444) : const Color(0xFFF59E0B)),
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Mijoz: ${order.customerName ?? 'Noma’lum'} ${order.customerPhone != null && order.customerPhone!.isNotEmpty ? '· ${order.customerPhone}' : ''}',
                      style: TextStyle(color: context.mutedColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (order.note != null && order.note!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1B2228) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Izoh: ${order.note!}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 12),
          Text(
            'Kesilishi va ishlov berilishi kerak bo‘lgan toshlar:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor),
          ),
          const SizedBox(height: 8),
          for (final item in cutItems) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF1B2228) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.content_cut_rounded, size: 18, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Miqdor: ${qty(item.quantity)}',
                          style: TextStyle(color: context.mutedColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () {
                      final details = _parseCuttingItemDetails(item.productName);
                      _create(
                        prefillProductId: item.productId > 0 ? item.productId : null,
                        prefillQty: item.quantity > 0 ? item.quantity : null,
                        prefillOrderId: order.id,
                        prefillCutSpec: details.cutSpec,
                        prefillCutPieces: details.pieces,
                        prefillCustomerInfo: '\${order.customerName ?? "Mijoz"}\${order.customerPhone != null && order.customerPhone!.isNotEmpty ? " (\${order.customerPhone})" : ""}',
                        prefillNote: order.note, // Faqat mijoz izohi, eni-bo'yi tafsilotlarda alohida saqlanadi
                        availableOrders: allCuttingOrders,
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                      foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(Icons.person_add_alt_1_rounded, size: 15, color: context.isDark ? AppColors.ink : AppColors.neonLime),
                    label: Text(isAssigned ? 'Qayta biriktirish' : (isRejected ? 'Boshqa ustaga biriktirish' : 'Ishchiga biriktirish'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStat(BuildContext context, String title, String value, IconData icon, Color color, bool isHeroCard) {
    final isDarkTheme = context.isDark;
    final isHero = isHeroCard && !isDarkTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHero ? AppColors.darkCard : context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isHero ? AppColors.darkCard : context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isHero ? const Color(0xFF22262B) : color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(color: isHero ? const Color(0xFF8E959E) : context.mutedColor, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: isHero ? Colors.white : context.inkColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
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

// ---------------------------------------------------------------------------
// Yangi topshiriq biriktirish dialogi (Buyurtmaga bog'lash imkoniyati bilan)
// ---------------------------------------------------------------------------

class TaskCreateDialog extends StatefulWidget {
  const TaskCreateDialog({
    super.key,
    required this.productionRepo,
    required this.productRepo,
    this.initialProductId,
    this.initialPlanned,
    this.initialNote,
    this.initialWorkerId,
    this.initialOrderId,
    this.initialCutSpec,
    this.initialCutPieces,
    this.initialCustomerInfo,
    this.availableOrders = const [],
  });
  final ProductionRepository productionRepo;
  final ProductRepository productRepo;
  final int? initialProductId;
  final double? initialPlanned;
  final String? initialNote;
  final int? initialWorkerId;
  final int? initialOrderId;
  final String? initialCutSpec;
  final int? initialCutPieces;
  final String? initialCustomerInfo;
  final List<SaleResult> availableOrders;

  @override
  State<TaskCreateDialog> createState() => _TaskCreateDialogState();
}

class _TaskCreateDialogState extends State<TaskCreateDialog> {
  late Future<({List<Product> products, List<AppUser> workers})> _loadFuture;
  int? _selectedProductId;
  int? _selectedWorkerId;
  int? _orderId;
  String? _cutSpec;
  int? _cutPieces;
  String? _customerInfo;
  final _planCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  ({String? cutSpec, int? pieces, String? cleanStoneName}) _parseCuttingItemDetails(String text) {
    final dimMatch = RegExp(r'(\d+(?:\.\d+)?\s*(?:sm|m)?\s*[×xX*]\s*\d+(?:\.\d+)?\s*(?:sm|m)?)').firstMatch(text);
    final piecesMatch = RegExp(r'(\d+)\s*dona').firstMatch(text);
    final stoneMatch = RegExp(r'\[([^\]]+)\]').firstMatch(text);

    return (
      cutSpec: dimMatch?.group(1),
      pieces: piecesMatch != null ? int.tryParse(piecesMatch.group(1)!) : null,
      cleanStoneName: stoneMatch?.group(1),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialProductId != null) _selectedProductId = widget.initialProductId;
    if (widget.initialWorkerId != null) _selectedWorkerId = widget.initialWorkerId;
    if (widget.initialPlanned != null) _planCtrl.text = qty(widget.initialPlanned!);
    if (widget.initialNote != null) _noteCtrl.text = widget.initialNote!;
    _orderId = widget.initialOrderId;
    _cutSpec = widget.initialCutSpec;
    _cutPieces = widget.initialCutPieces;
    _customerInfo = widget.initialCustomerInfo;
    _loadFuture = _loadData();
  }

  Future<({List<Product> products, List<AppUser> workers})> _loadData() async {
    final p = await widget.productRepo.list();
    var w = await widget.productionRepo.workers();
    if (w.isEmpty && mounted) {
      final all = await context.read<AppRepositories>().users.list();
      w = all.where((u) => u.isActive && u.role == Role.ishchi).toList();
      if (w.isEmpty) w = all.where((u) => u.isActive).toList();
    }
    if (_selectedProductId == null && p.isNotEmpty) _selectedProductId = p.first.id;
    if (_selectedWorkerId == null && w.isNotEmpty) _selectedWorkerId = w.first.id;
    return (products: p, workers: w);
  }

  @override
  void dispose() {
    _planCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedProductId == null || _selectedWorkerId == null) {
      setState(() {
        _error = 'Mahsulot va ishchini tanlang';
      });
      return;
    }
    final planned = parseInput(_planCtrl.text);
    if (planned == null || planned <= 0) {
      setState(() {
        _error = 'Reja miqdorini to‘g‘ri kiriting';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.productionRepo.create(
        productId: _selectedProductId!,
        workerId: _selectedWorkerId!,
        plannedQty: planned,
        note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
        orderId: _orderId,
        cutLength: null,
        cutWidth: null,
        cutPieces: _cutPieces,
        cutSpec: _cutSpec,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<Product> products, List<AppUser> workers})>(
      future: _loadFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const AlertDialog(
            content: SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final products = snap.data!.products;
        final workers = snap.data!.workers;

        if (products.isEmpty) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Mahsulotlar mavjud emas'),
            content: const Text('Topshiriq berish uchun avval "Mahsulotlar" bo‘limidan mahsulot qo‘shing.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
            ],
          );
        }

        if (workers.isEmpty) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Xodimlar mavjud emas'),
            content: const Text('Topshiriq biriktirish uchun "Xodimlar" bo‘limidan ishchi qo‘shing.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
            ],
          );
        }

        _selectedProductId ??= products.first.id;
        _selectedWorkerId ??= workers.first.id;

        final selProd = products.where((p) => p.id == _selectedProductId).firstOrNull ?? products.first;

        return AlertDialog(
          backgroundColor: context.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.assignment_add, color: AppColors.neonLime, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Yangi Ishlab Chiqarish Topshirig‘i',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: MediaQuery.sizeOf(context).width < 450 ? 15.5 : 18,
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
                  // Buyurtmadan to'ldirish (agar mavjud bo'lsa)
                  if (widget.availableOrders.isNotEmpty) ...[
                    DropdownButtonFormField<SaleResult?>(
                      decoration: InputDecoration(
                        labelText: '📥 Buyurtmadan avtomatik to‘ldirish',
                        filled: true,
                        fillColor: context.isDark ? const Color(0xFF1B2228) : const Color(0xFFF1F5F9),
                        prefixIcon: const Icon(Icons.receipt_long_rounded, color: Color(0xFFF59E0B), size: 18),
                      ),
                      items: [
                        const DropdownMenuItem<SaleResult?>(
                          value: null,
                          child: Text('Maxsus / mustaqil topshiriq', style: TextStyle(fontSize: 12.5)),
                        ),
                        for (final ord in widget.availableOrders)
                          DropdownMenuItem<SaleResult?>(
                            value: ord,
                            child: Text(
                              'Buyurtma #${ord.id} · ${ord.customerName ?? 'Mijoz'}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                      onChanged: (ord) {
                        if (ord == null) {
                          setState(() {
                            _orderId = null;
                            _cutSpec = null;
                            _cutPieces = null;
                            _customerInfo = null;
                            _noteCtrl.clear();
                          });
                          return;
                        }
                        final cutItem = ord.items.firstWhere(
                          (it) => it.isCut || it.productName.toLowerCase().contains('kesish') || it.productName.toLowerCase().contains('ishlov'),
                          orElse: () => ord.items.first,
                        );
                        final matching = products.where((p) => p.id == cutItem.productId || p.name.toLowerCase() == cutItem.productName.toLowerCase()).firstOrNull;
                        final details = _parseCuttingItemDetails(cutItem.productName);

                        setState(() {
                          if (matching != null) {
                            _selectedProductId = matching.id;
                          }
                          _planCtrl.text = qty(cutItem.quantity);
                          _orderId = ord.id;
                          _cutSpec = details.cutSpec;
                          _cutPieces = details.pieces;
                          _customerInfo = '\${ord.customerName ?? "Mijoz"}\${ord.customerPhone != null ? " (\${ord.customerPhone})" : ""}';
                          // Eni-bo'yi izohga yozilmaydi! Faqat mijozning haqiqiy izohi yoziladi:
                          _noteCtrl.text = (ord.note != null && ord.note!.isNotEmpty) ? ord.note! : '';
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Tafsilotlar bloki (Eni, bo'yi, buyurtma ma'lumotlari)
                  if (_orderId != null || _cutSpec != null || _customerInfo != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.isDark ? const Color(0xFF13222F) : const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: context.isDark ? const Color(0xFF0284C7).withValues(alpha: 0.4) : const Color(0xFFBAE6FD),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF0284C7)),
                              const SizedBox(width: 6),
                              const Text('Topshiriq tafsilotlari:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF0284C7))),
                              const Spacer(),
                              if (_orderId != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Buyurtma #\$_orderId', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0284C7))),
                                ),
                            ],
                          ),
                          if (_customerInfo != null && _customerInfo!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('👤 Mijoz: \$_customerInfo', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                          if (_cutSpec != null && _cutSpec!.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Text('📐 O‘lchami (Eni × Bo‘yi): ', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                Text(_cutSpec!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0284C7))),
                              ],
                            ),
                          ],
                          if (_cutPieces != null && _cutPieces! > 0) ...[
                            const SizedBox(height: 3),
                            Text('📦 Soni: \$_cutPieces dona', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Ishchi tanlash
                  DropdownButtonFormField<int>(
                    value: _selectedWorkerId,
                    decoration: const InputDecoration(
                      labelText: 'Biriktirilgan ishchi (usta)',
                      prefixIcon: Icon(Icons.engineering_rounded, size: 20),
                    ),
                    items: [for (final w in workers) DropdownMenuItem(value: w.id, child: Text(w.fullName))],
                    onChanged: (v) {
                      setState(() {
                        _selectedWorkerId = v;
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Mahsulot tanlash
                  DropdownButtonFormField<int>(
                    value: _selectedProductId,
                    decoration: const InputDecoration(
                      labelText: 'Ishlov beriladigan tosh / mahsulot',
                      prefixIcon: Icon(Icons.layers_rounded, size: 20),
                    ),
                    items: [for (final p in products) DropdownMenuItem(value: p.id, child: Text(p.name))],
                    onChanged: (v) {
                      setState(() {
                        _selectedProductId = v;
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Miqdor
                  TextField(
                    controller: _planCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Rejadagi miqdor (${selProd.unit})',
                      hintText: 'masalan: 120',
                      prefixIcon: const Icon(Icons.straighten_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Qo'shimcha izoh (faqat usta uchun eslatma, eni-bo'yi tafsilotlarda ko'rsatiladi)
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Qo‘shimcha izoh (ixtiyoriy)',
                      hintText: 'Usta uchun maxsus qo‘shimcha eslatma (masalan: 3-etaj pillapoyaga)',
                      prefixIcon: Icon(Icons.edit_note_rounded, size: 20),
                    ),
                  ),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Topshiriq berish', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }
}

class _ProductionReportDialog extends StatefulWidget {
  const _ProductionReportDialog({required this.task, required this.repo});
  final ProductionTask task;
  final ProductionRepository repo;

  @override
  State<_ProductionReportDialog> createState() => _ProductionReportDialogState();
}

class _ProductionReportDialogState extends State<_ProductionReportDialog> {
  late final double _remaining;
  late final TextEditingController _ctrl;
  late final TextEditingController _wasteCtrl;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _remaining = (widget.task.planned - widget.task.produced).clamp(0, double.infinity).toDouble();
    _ctrl = TextEditingController(text: qty(_remaining > 0 ? _remaining : 1));
    _wasteCtrl = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _wasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final v = parseInput(_ctrl.text);
    if (v == null || v <= 0) {
      setState(() => _error = 'Miqdorni to‘g‘ri kiriting');
      return;
    }
    final waste = parseInput(_wasteCtrl.text) ?? 0;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.report(widget.task.id, v, wasteQty: waste);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    return AlertDialog(
      backgroundColor: context.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        '${t.productName}: Ish hisoboti',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
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
                color: context.pillColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.muted, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Reja: ${qty(t.planned)} ${t.unit}  ·  Bajarilgan: ${qty(t.produced)} ${t.unit}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Yangi ishlab chiqarilgan miqdor (${t.unit})',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wasteCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Chiqindi / Brak miqdori (${t.unit})',
                helperText: 'Yaroqsiz yoki arralashda yo‘qolgan tosh',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (_remaining > 0)
                  ActionChip(
                    label: Text('Qoldiqni yakunlash (${qty(_remaining)})'),
                    onPressed: () {
                      setState(() => _ctrl.text = qty(_remaining));
                    },
                  ),
                ActionChip(
                  label: const Text('+1 dona/m²'),
                  onPressed: () {
                    final cur = parseInput(_ctrl.text) ?? 0;
                    setState(() => _ctrl.text = qty(cur + 1));
                  },
                ),
                ActionChip(
                  label: const Text('+5'),
                  onPressed: () {
                    final cur = parseInput(_ctrl.text) ?? 0;
                    setState(() => _ctrl.text = qty(cur + 5));
                  },
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Bekor'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
            foregroundColor: context.isDark ? AppColors.ink : Colors.white,
          ),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Yuborish'),
        ),
      ],
    );
  }
}

