import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';

class ArchivedUsersScreen extends StatefulWidget {
  const ArchivedUsersScreen({super.key});

  @override
  State<ArchivedUsersScreen> createState() => _ArchivedUsersScreenState();
}

class _ArchivedUsersScreenState extends State<ArchivedUsersScreen> {
  final _searchCtrl = TextEditingController();
  late Future<List<AppUser>> _future;
  bool _anyRestored = false;

  UserRepository get _repo => context.read<AppRepositories>().users;

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
      _future = _repo.listArchived();
    });
  }

  Future<void> _restoreUser(AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.replay_rounded, color: AppColors.neonLime, size: 24),
            SizedBox(width: 10),
            Text('Xodimni qayta tiklash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        content: Text(
          '"${u.fullName}" faol xodimlar ro‘yxatiga qaytarilsinmi?\nUning dasturga kirish huquqi tiklanadi.',
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
            label: const Text('Tiklash', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _repo.restore(u.id);
      _anyRestored = true;
      if (mounted) {
        showMessage(context, '${u.fullName} muvaffaqiyatli tiklandi!');
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
          title: const Text('Arxivdagi xodimlar', style: TextStyle(fontWeight: FontWeight.w800)),
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context, _anyRestored),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reload,
              tooltip: 'Yangilash',
            ),
          ],
        ),
        body: FutureBuilder<List<AppUser>>(
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
            final filtered = list.where((u) {
              if (q.isEmpty) return true;
              return u.fullName.toLowerCase().contains(q) ||
                  u.username.toLowerCase().contains(q) ||
                  u.role.label.toLowerCase().contains(q) ||
                  (u.archivedByName != null && u.archivedByName!.toLowerCase().contains(q));
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
                        hintText: 'Qidirish (Ism, login, rol yoki kim arxivlagani)...',
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
                            const Icon(Icons.archive_outlined, size: 14, color: AppColors.danger),
                            const SizedBox(width: 6),
                            Text(
                              'Arxivlangan xodimlar: ${list.length} ta',
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
                            Icons.people_outline_rounded,
                            size: 64,
                            color: AppColors.muted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            list.isEmpty ? 'Arxivlangan xodimlar yo‘q' : 'Qidiruv bo‘yicha xodim topilmadi',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            list.isEmpty
                                ? 'Barcha xodimlar faol ro‘yxatda saqlanmoqda'
                                : 'Boshqa so‘z bilan qidirib ko‘ring',
                            style: const TextStyle(fontSize: 13, color: AppColors.muted),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filtered.map((u) => _buildArchivedCard(u)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildArchivedCard(AppUser u) {
    final archivedAtStr = u.archivedAt != null ? formatDateTime(u.archivedAt!) : 'Noma‘lum';
    final archivedByStr = u.archivedByName != null && u.archivedByName!.isNotEmpty
        ? u.archivedByName!
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
                // Avatar icon
                CircleAvatar(
                  radius: 24,
                  backgroundColor: context.isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  child: Text(
                    u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : 'X',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                // Xodim ma'lumotlari
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              u.role.label,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '@${u.username}',
                            style: const TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Dasturga kirish: Taqiqlangan',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
                // Qayta tiklash tugmasi
                FilledButton.icon(
                  onPressed: () => _restoreUser(u),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
                    foregroundColor: context.isDark ? AppColors.ink : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Tiklash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
                            'Arxivladi: $archivedByStr',
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
                        archivedAtStr,
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
