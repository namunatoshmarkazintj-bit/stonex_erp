import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/local_image_store.dart';

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: error ? AppColors.danger : AppColors.darkCard,
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: error ? Colors.white : AppColors.neonLime,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.darkCard,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
}

/// Mahsulot rasmi yoki rasmi yo'q bo'lsa zamonaviy default mahsulot belgisi
class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 42,
    this.width,
    this.height,
    this.borderRadius = 12,
    this.borderRadiusGeometry,
    this.fit = BoxFit.cover,
  });

  final String? imageUrl;
  final String name;
  final double size;
  final double? width;
  final double? height;
  final double borderRadius;
  final BorderRadiusGeometry? borderRadiusGeometry;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final r = borderRadiusGeometry ?? BorderRadius.circular(borderRadius);

    Widget fallbackAvatar() => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1E2822) : AppColors.neonLimeSoft,
            borderRadius: r,
            border: Border.all(
              color: context.borderColor,
              width: 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.inventory_2_outlined,
            color: context.isDark ? AppColors.neonLime : AppColors.ink,
            size: (w < h ? w : h) * 0.45,
          ),
        );

    final raw = imageUrl?.trim() ?? '';
    if (raw.isEmpty) {
      return fallbackAvatar();
    }

    Widget imageWidget;
    try {
      if (raw.startsWith('data:image/') || raw.contains(';base64,')) {
        // Base64 Data URI
        final comma = raw.indexOf(',');
        final b64 = comma != -1 ? raw.substring(comma + 1).trim() : raw;
        final bytes = base64Decode(b64);
        imageWidget = Image.memory(
          Uint8List.fromList(bytes),
          width: w,
          height: h,
          fit: fit,
          errorBuilder: (_, __, ___) => fallbackAvatar(),
        );
      } else if (!raw.startsWith('http://') &&
          !raw.startsWith('https://') &&
          !raw.startsWith('/') &&
          File(raw).existsSync()) {
        // Mahalliy kompyuter / telefon fayl yo'li
        imageWidget = Image.file(
          File(raw),
          width: w,
          height: h,
          fit: fit,
          errorBuilder: (_, __, ___) => fallbackAvatar(),
        );
      } else {
        // Server URL yoki keshdagi rasm
        final resolvedUrl = ApiClient.resolveUrl(raw);
        final cached = LocalImageStore.getCachedFile(resolvedUrl);
        if (cached != null) {
          // Keshdan bir zumda ochish (offline va 0ms kechikish)
          imageWidget = Image.file(
            cached,
            width: w,
            height: h,
            fit: fit,
            errorBuilder: (_, __, ___) => fallbackAvatar(),
          );
        } else {
          // Internetdan yuklab, fonda lokal keshga yozib qo'yish
          LocalImageStore.downloadAndCache(resolvedUrl);
          imageWidget = Image.network(
            resolvedUrl,
            width: w,
            height: h,
            fit: fit,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (_, __, ___) => fallbackAvatar(),
          );
        }
      }
    } catch (_) {
      return fallbackAvatar();
    }

    return ClipRRect(
      borderRadius: r,
      child: Container(
        width: w,
        height: h,
        color: context.isDark ? const Color(0xFF1E2822) : const Color(0xFFF1F5F9),
        child: imageWidget,
      ),
    );
  }
}

/// Mahsulot rasmini to'liq va katta hajmda ko'rish oynasi
void showProductImagePreview(
  BuildContext context, {
  required String? imageUrl,
  required String name,
  String? subtitle,
}) {
  if (imageUrl == null || imageUrl.trim().isEmpty) return;
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: ctx.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 28, offset: Offset(0, 10)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                ProductThumbnail(
                  imageUrl: imageUrl,
                  name: name,
                  width: double.infinity,
                  height: 320,
                  fit: BoxFit.contain,
                  borderRadiusGeometry: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      tooltip: 'Yopish',
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ctx.inkColor,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class NotImplementedView extends StatelessWidget {
  const NotImplementedView({super.key, required this.title, required this.note});
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: context.isDark ? AppColors.neonLime.withValues(alpha: 0.15) : AppColors.darkCard.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.videocam_outlined, size: 36, color: context.isDark ? AppColors.neonLime : AppColors.ink),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: context.inkColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Bu modul keyingi bosqichda ulanadi.\n$note',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
}

Color getStoneColor(String? colorName) {
  if (colorName == null) return Colors.grey;
  final c = colorName.trim().toLowerCase();
  if (c.contains('qora') || c.contains('black') || c.contains('dark')) return const Color(0xFF1E293B);
  if (c.contains('oq') || c.contains('white')) return const Color(0xFFF1F5F9);
  if (c.contains('ko‘k') || c.contains("ko'k") || c.contains('kok') || c.contains('blue')) return const Color(0xFF2563EB);
  if (c.contains('kulrang') || c.contains('grey') || c.contains('gray')) return const Color(0xFF64748B);
  if (c.contains('bej') || c.contains('beige') || c.contains('krem')) return const Color(0xFFD4B996);
  if (c.contains('yashil') || c.contains('green')) return const Color(0xFF10B981);
  if (c.contains('qizil') || c.contains('red')) return const Color(0xFFEF4444);
  if (c.contains('jigarrang') || c.contains('brown')) return const Color(0xFF854D0E);
  if (c.contains('sariq') || c.contains('yellow')) return const Color(0xFFF59E0B);
  return const Color(0xFF64748B);
}

class StoneColorBadge extends StatelessWidget {
  const StoneColorBadge({super.key, required this.colorName, this.fontSize = 10});
  final String colorName;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final dotColor = getStoneColor(colorName);
    final isWhite = dotColor.value == const Color(0xFFF1F5F9).value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isWhite ? Colors.grey : dotColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            colorName,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: context.inkColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stonex ERP Maxsus Zamonaviy Sana Tanlash Dialogi (StonexDatePickerDialog)
// ---------------------------------------------------------------------------

class StonexDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const StonexDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  static Future<DateTime?> show({
    required BuildContext context,
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    return showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      builder: (_) => StonexDatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate ?? DateTime(2020),
        lastDate: lastDate ?? DateTime(2030),
      ),
    );
  }

  @override
  State<StonexDatePickerDialog> createState() => _StonexDatePickerDialogState();
}

class _StonexDatePickerDialogState extends State<StonexDatePickerDialog> {
  late DateTime _selected;
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _viewMonth = DateTime(_selected.year, _selected.month, 1);
  }

  void _prevMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _monthNameUz(int m) {
    const months = [
      'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun',
      'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'
    ];
    return months[m - 1];
  }

  String _formatFullDate(DateTime dt) {
    const weekdays = [
      'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'
    ];
    final wName = weekdays[dt.weekday - 1];
    final mName = _monthNameUz(dt.month).toLowerCase();
    final now = DateTime.now();
    final isToday = _isSameDay(dt, now);
    final isYesterday = _isSameDay(dt, now.subtract(const Duration(days: 1)));
    final suffix = isToday ? ' · Bugun' : (isYesterday ? ' · Kecha' : '');
    return '${dt.day}-$mName, ${dt.year} ($wName)$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final now = DateTime.now();
    final daysInMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final startOffset = _viewMonth.weekday - 1; // 0 for Mon .. 6 for Sun
    final totalCells = startOffset + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    return Dialog(
      backgroundColor: context.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Sarlavha va yopish tugmasi
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.neonLime.withValues(alpha: 0.15) : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sana tanlash',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: context.inkColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 18,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Tanlangan sana ko'rsatgichi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161E28) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? AppColors.neonLime.withValues(alpha: 0.3)
                      : const Color(0xFF22C55E).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tanlangan sana:',
                    style: TextStyle(fontSize: 10.5, color: context.mutedColor, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatFullDate(_selected),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.neonLime : const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. Tezkor tugmalar (Presets)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _presetButton('Bugun', now),
                  const SizedBox(width: 6),
                  _presetButton('Kecha', now.subtract(const Duration(days: 1))),
                  const SizedBox(width: 6),
                  _presetButton('2 kun oldin', now.subtract(const Duration(days: 2))),
                  const SizedBox(width: 6),
                  _presetButton('Hafta boshi (Du)', now.subtract(Duration(days: now.weekday - 1))),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 4. Oy va Yil almashtirish navigatori
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: context.pillColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 22),
                    onPressed: _prevMonth,
                    tooltip: 'Oldingi oy',
                    splashRadius: 18,
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    '${_monthNameUz(_viewMonth.month)} ${_viewMonth.year}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 22),
                    onPressed: _nextMonth,
                    tooltip: 'Keyingi oy',
                    splashRadius: 18,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 5. Hafta kunlari sarlavhasi
            Row(
              children: const ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'].map((d) {
                final isWeekend = d == 'Sh' || d == 'Ya';
                return Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isWeekend ? AppColors.danger : context.mutedColor,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),

            // 6. Kalendar kunlari panjarasi (Grid)
            Column(
              children: [
                for (var r = 0; r < rowCount; r++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      children: [
                        for (var c = 0; c < 7; c++) ...[
                          Expanded(
                            child: _buildDayCell(r * 7 + c, startOffset, daysInMonth, now),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 7. Amallar: Bekor qilish va Tanlash
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    ),
                    child: Text('Bekor qilish', style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Tanlash', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
                      foregroundColor: isDark ? AppColors.ink : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(int cellIndex, int startOffset, int daysInMonth, DateTime now) {
    final dayNum = cellIndex - startOffset + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 34);
    }

    final cellDate = DateTime(_viewMonth.year, _viewMonth.month, dayNum);
    final isSel = _isSameDay(cellDate, _selected);
    final isToday = _isSameDay(cellDate, now);
    final isWeekend = cellDate.weekday == DateTime.saturday || cellDate.weekday == DateTime.sunday;
    final isDark = context.isDark;

    return Center(
      child: InkWell(
        onTap: () {
          setState(() {
            _selected = cellDate;
          });
        },
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSel
                ? (isDark ? AppColors.neonLime : AppColors.darkCard)
                : (isToday
                    ? (isDark ? AppColors.neonLime.withValues(alpha: 0.15) : const Color(0xFFDCFCE7))
                    : Colors.transparent),
            border: isToday && !isSel
                ? Border.all(
                    color: isDark ? AppColors.neonLime : const Color(0xFF22C55E),
                    width: 1.4,
                  )
                : null,
            boxShadow: isSel
                ? [
                    BoxShadow(
                      color: (isDark ? AppColors.neonLime : Colors.black).withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              '$dayNum',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: (isSel || isToday) ? FontWeight.w900 : FontWeight.w600,
                color: isSel
                    ? (isDark ? AppColors.ink : Colors.white)
                    : (isToday
                        ? (isDark ? AppColors.neonLime : const Color(0xFF15803D))
                        : (isWeekend ? AppColors.danger.withValues(alpha: 0.8) : context.inkColor)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _presetButton(String label, DateTime targetDate) {
    final isSel = _isSameDay(_selected, targetDate);
    final isDark = context.isDark;
    return InkWell(
      onTap: () {
        setState(() {
          _selected = targetDate;
          _viewMonth = DateTime(targetDate.year, targetDate.month, 1);
        });
      },
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          color: isSel
              ? (isDark ? AppColors.neonLime : AppColors.darkCard)
              : context.pillColor,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSel
                ? (isDark ? AppColors.neonLime : AppColors.darkCard)
                : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
            color: isSel
                ? (isDark ? AppColors.ink : Colors.white)
                : context.mutedColor,
          ),
        ),
      ),
    );
  }
}
