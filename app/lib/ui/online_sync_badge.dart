import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/offline_cache_store.dart';
import '../data/offline_sync_engine.dart';

/// Barcha rollar uchun internet holati va avtomatik sinxronizatsiya indikatori
class OnlineSyncBadge extends StatelessWidget {
  const OnlineSyncBadge({super.key, this.isCompact = false, required this.api});
  final bool isCompact;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OfflineSyncEngine.instance,
      builder: (context, _) {
        final engine = OfflineSyncEngine.instance;
        final isOnline = engine.isOnline;
        final isSyncing = engine.isSyncing;
        final pending = engine.pendingCount;

        final Color bg;
        final Color textCol;
        final IconData icon;
        final String label;

        if (isSyncing) {
          bg = const Color(0xFF3B82F6).withValues(alpha: 0.15);
          textCol = const Color(0xFF2563EB);
          icon = Icons.sync_rounded;
          label = isCompact ? 'Sinxron...' : 'Sinxronlanmoqda...';
        } else if (!isOnline) {
          bg = const Color(0xFFF59E0B).withValues(alpha: 0.18);
          textCol = const Color(0xFFD97706);
          icon = Icons.wifi_off_rounded;
          label = pending > 0
              ? (isCompact ? 'Oflayn ($pending)' : 'Oflayn ($pending navbatda)')
              : (isCompact ? 'Oflayn' : 'Oflayn rejim');
        } else {
          bg = const Color(0xFF10B981).withValues(alpha: 0.15);
          textCol = const Color(0xFF059669);
          icon = Icons.wifi_rounded;
          label = isCompact ? 'Onlayn' : 'Onlayn';
        }

        return Tooltip(
          message: isOnline
              ? 'Tizim serverga ulangan (Onlayn). Barcha ma\'lumotlar yangilangan.'
              : 'Internet yo\'q. Kassa va qidiruv oflayn rejimda ishlamoqda. Aloqa tiklanishi bilan avtomatik sinxronlanadi.',
          child: InkWell(
            onTap: () => _showSyncDetailsModal(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: textCol.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: textCol),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: textCol,
                    ),
                  ),
                  if (pending > 0 && isOnline) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pending',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSyncDetailsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListenableBuilder(
        listenable: OfflineSyncEngine.instance,
        builder: (ctx, _) {
          final engine = OfflineSyncEngine.instance;
          final stats = OfflineCacheStore.getStats();
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Center(
            child: Container(
              margin: const EdgeInsets.all(16),
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).dividerColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: engine.isOnline
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          engine.isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          color: engine.isOnline ? const Color(0xFF059669) : const Color(0xFFD97706),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              engine.isOnline ? 'Serverga ulangan (Onlayn)' : 'Oflayn Rejim Faol',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              engine.isOnline
                                  ? 'Internet aloqasi barqaror'
                                  : 'Internet yo‘q bo‘lsa ham kassa va qidiruv to‘xtovsiz ishlaydi',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  _rowInfo(
                    'Keshdagi mahsulotlar:',
                    '${stats['cached_products_count']} ta (narxlar va qoldiqlar)',
                    Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 8),
                  _rowInfo(
                    'Keshdagi mijozlar:',
                    '${stats['cached_customers_count']} ta',
                    Icons.people_outline_rounded,
                  ),
                  const SizedBox(height: 8),
                  _rowInfo(
                    'Navbatdagi oflayn savdolar:',
                    '${stats['pending_sales_count']} ta kutilmoqda',
                    Icons.outbox_rounded,
                    valueColor: (stats['pending_sales_count'] as int) > 0 ? const Color(0xFFF59E0B) : null,
                  ),
                  const SizedBox(height: 8),
                  _rowInfo(
                    'So‘nggi sinxronizatsiya:',
                    engine.lastSyncTime != null
                        ? '${engine.lastSyncTime!.hour.toString().padLeft(2, '0')}:${engine.lastSyncTime!.minute.toString().padLeft(2, '0')}:${engine.lastSyncTime!.second.toString().padLeft(2, '0')}'
                        : 'Hozircha yo‘q',
                    Icons.access_time_rounded,
                  ),

                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: engine.isSyncing
                        ? null
                        : () async {
                            await engine.checkAndSync();
                          },
                    icon: engine.isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: Text(
                      engine.isSyncing ? 'Sinxronlanmoqda...' : 'Qayta tekshirish va sinxronlash',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.neonLime,
                      foregroundColor: AppColors.ink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _rowInfo(String title, String value, IconData icon, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 12.5)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
