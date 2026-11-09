import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';

class DeletedProductsScreen extends StatefulWidget {
  const DeletedProductsScreen({super.key});

  @override
  State<DeletedProductsScreen> createState() => _DeletedProductsScreenState();
}

class _DeletedProductsScreenState extends State<DeletedProductsScreen> {
  final _searchCtrl = TextEditingController();
  late Future<List<Product>> _future;
  bool _anyRestored = false;

  ProductRepository get _repo => context.read<AppRepositories>().products;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _repo.listDeleted();
    });
  }

  Future<void> _restoreProduct(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.replay_rounded, color: AppColors.neonLime, size: 24),
            SizedBox(width: 10),
            Text('Mahsulotni qaytarish', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        content: Text(
          '"${p.name}" mahsuloti faol tovarlar katalogiga qayta tiklansinmi?',
          style: const TextStyle(height: 1.4, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
              foregroundColor: context.isDark ? AppColors.ink : Colors.white,
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Qaytarish', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _repo.restore(p.id);
      _anyRestored = true;
      if (mounted) {
        showMessage(context, '${p.name} muvaffaqiyatli qaytarildi!');
        _reload();
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  Future<void> _purgeProduct(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 24),
            SizedBox(width: 10),
            Text('Butunlay o‘chirish', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        content: Text(
          '"${p.name}" mahsulotini bazadan butunlay o‘chirib tashlamoqchimisiz? Uni keyin qayta tiklab bo‘lmaydi!',
          style: const TextStyle(height: 1.4, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Ha, tozalash', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _repo.purge(p.id);
      if (mounted) {
        showMessage(context, '${p.name} bazadan butunlay tozalandi!');
        _reload();
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  Future<void> _purgeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: AppColors.danger, size: 24),
            SizedBox(width: 10),
            Text('Savatni tozalash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        content: const Text(
          'Barcha arxivlangan va o‘chirilgan mahsulotlarni butunlay tozalashni xohlaysizmi? Bu amalni ortga qaytarib bo‘lmaydi!',
          style: TextStyle(height: 1.4, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('Barchasini tozalash', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _repo.purgeAll();
      if (mounted) {
        showMessage(context, 'Barcha o‘chirilgan mahsulotlar butunlay tozalandi!');
        _reload();
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        backgroundColor: context.scaffoldBg,
        appBar: AppBar(
          title: const Text('O‘chirilgan mahsulotlar', style: TextStyle(fontWeight: FontWeight.w800)),
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context, _anyRestored),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.danger),
              tooltip: 'Savatni butunlay tozalash',
              onPressed: _purgeAll,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reload,
              tooltip: 'Yangilash',
            ),
          ],
        ),
        body: FutureBuilder<List<Product>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ErrorView(message: snap.error.toString(), onRetry: _reload);
            }

            final list = snap.data ?? [];
            final q = _searchCtrl.text.trim().toLowerCase();
            final filtered = list.where((p) {
              if (q.isEmpty) return true;
              return p.name.toLowerCase().contains(q) ||
                  p.sku.toLowerCase().contains(q) ||
                  p.qrCode.toLowerCase().contains(q) ||
                  (p.deletedByName != null && p.deletedByName!.toLowerCase().contains(q));
            }).toList();

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  // Qidiruv
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
                        hintText: 'Qidirish (Nomi, SKU yoki kim o‘chirgani)...',
                        hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                          borderSide: BorderSide(
                            color: context.isDark ? AppColors.neonLime : AppColors.ink,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Statistika qatori
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.danger),
                            const SizedBox(width: 6),
                            Text(
                              'Jami o‘chirilgan: ${list.length} ta',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delete_sweep_outlined,
                            size: 64,
                            color: AppColors.muted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            list.isEmpty ? 'O‘chirilgan mahsulotlar yo‘q' : 'Qidiruv bo‘yicha tovar topilmadi',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            list.isEmpty
                                ? 'Katalogdagi barcha tovarlar faol holatda saqlanmoqda'
                                : 'Boshqa so‘z bilan qidirib ko‘ring',
                            style: const TextStyle(fontSize: 13, color: AppColors.muted),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filtered.map((p) => _buildDeletedCard(p)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDeletedCard(Product p) {
    final deletedAtStr = p.deletedAt != null ? formatDateTime(p.deletedAt!) : 'Noma‘lum';
    final deletedByStr = p.deletedByName != null && p.deletedByName!.isNotEmpty
        ? p.deletedByName!
        : 'Admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rasm yoki belgi
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: context.isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    child: (p.imageUrl != null && p.imageUrl!.isNotEmpty)
                        ? Image.network(
                            p.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2_outlined, color: AppColors.muted),
                          )
                        : const Icon(Icons.inventory_2_outlined, color: AppColors.muted),
                  ),
                ),
                const SizedBox(width: 12),
                // Nomi va kategoriyasi
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (p.category != null && p.category!.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                p.category!,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            'SKU: ${p.sku.isNotEmpty ? p.sku : '-'}',
                            style: const TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${money(p.price)} / ${p.unit}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 22),
                      tooltip: 'Butunlay o‘chirish',
                      onPressed: () => _purgeProduct(p),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: () => _restoreProduct(p),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                        foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: const Text('Qaytarish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Kim o'chirgani va qachon o'chirilgani ma'lumot qutisi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.person_remove_outlined, size: 15, color: AppColors.danger),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'O‘chirdi: $deletedByStr',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 14, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Text(
                        deletedAtStr,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w500),
                      ),
                    ],
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
