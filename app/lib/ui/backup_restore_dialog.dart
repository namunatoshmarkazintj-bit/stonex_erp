import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/repository_factory.dart';
import 'common.dart';

/// Xo'jayin (Admin / Master) uchun ma'lumotlar bazasini to'liq zaxiralash (SQL & Excel)
/// va server o'chib ketgan taqdirda 1 ta tugma bilan qayta tiklash (Disaster Recovery) dialogi.
class BackupRestoreDialog extends StatefulWidget {
  const BackupRestoreDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => const BackupRestoreDialog(),
    );
  }

  @override
  State<BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<BackupRestoreDialog> {
  bool _isLoading = false;
  String? _statusText;

  Future<void> _downloadSqlBackup() async {
    setState(() {
      _isLoading = true;
      _statusText = 'SQL zaxira nusxasi serverdan olinmoqda...';
    });

    try {
      final url = '${AppConfig.apiBaseUrl}/backup/sql';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 40));

      if (res.statusCode != 200) {
        throw Exception('Server xatosi (${res.statusCode}): ${res.body}');
      }

      final now = DateTime.now();
      final defaultName =
          'stonex_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.sql';

      final bytes = res.bodyBytes;

      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'SQL Zaxira faylini saqlash joyini tanlang',
        fileName: defaultName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['sql'],
      );

      if (savedUri == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (!kIsWeb) {
        try {
          final savedPath = savedUri.scheme == 'file' ? savedUri.toFilePath() : savedUri.path;
          final f = File(savedPath);
          await f.writeAsBytes(bytes, flush: true);
        } catch (_) {}
      }

      if (mounted) {
        showMessage(context, '✓ SQL Zaxira fayli muvaffaqiyatli yuklab olindi!');
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Zaxira yuklab olishda xatolik: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = null;
        });
      }
    }
  }

  Future<void> _downloadExcelBackup() async {
    setState(() {
      _isLoading = true;
      _statusText = 'Excel / CSV arxivi tayyorlanmoqda...';
    });

    try {
      final url = '${AppConfig.apiBaseUrl}/backup/excel';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 40));

      if (res.statusCode != 200) {
        throw Exception('Server xatosi (${res.statusCode}): ${res.body}');
      }

      final now = DateTime.now();
      final defaultName =
          'stonex_excel_data_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.zip';

      final bytes = res.bodyBytes;

      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Excel ma’lumotlar arxivini saqlash joyini tanlang',
        fileName: defaultName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (savedUri == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (!kIsWeb) {
        try {
          final savedPath = savedUri.scheme == 'file' ? savedUri.toFilePath() : savedUri.path;
          final f = File(savedPath);
          await f.writeAsBytes(bytes, flush: true);
        } catch (_) {}
      }

      if (mounted) {
        showMessage(context, '✓ Excel ma’lumotlar arxivi muvaffaqiyatli saqlandi!');
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Excel yuklab olishda xatolik: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = null;
        });
      }
    }
  }

  Future<void> _restoreFromSql() async {
    // 1. Faylni tanlash
    final file = await FilePicker.pickFile(
      dialogTitle: 'Qayta tiklash uchun .sql zaxira faylini tanlang',
      type: FileType.custom,
      allowedExtensions: ['sql'],
    );

    if (file == null) return;

    final bytes = await file.xFile.readAsBytes();

    if (bytes.isEmpty) {
      if (mounted) showMessage(context, 'Fayl bo‘sh yoki o‘qib bo‘lmadi.', error: true);
      return;
    }

    if (!mounted) return;

    // 2. Tasdiqlash dialogi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('Bazani tiklashni tasdiqlaysizmi?')),
          ],
        ),
        content: Text(
          'Tanlangan fayl: "${file.name}"\n\n'
          '⚠️ DIQQAT! Ushbu amal serverdagi jadvallarni tozalab, SQL faylidagi ma’lumotlarni qayta tiklaydi. '
          'Server o‘chib ketgan yoki nosozlik bo‘lganda ushbu funksiyadan foydalaniladi.\n\n'
          'Haqiqatan ham davom etishni xohlaysizmi?',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ha, qayta tiklansin'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 3. Yuklash va tiklash
    setState(() {
      _isLoading = true;
      _statusText = 'Baza qayta tiklanmoqda, iltimos kuting...';
    });

    try {
      final res = await appApiClient.uploadFile(
        '/backup/restore',
        bytes,
        file.name,
      );

      final msg = res is Map ? (res['message'] ?? 'Baza tiklandi') : 'Baza tiklandi';

      if (mounted) {
        showMessage(context, '✓ $msg');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Tiklashda xatolik: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.dialogBg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: context.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 36,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sarlavha
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.neonLime,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.cloud_sync_rounded, color: AppColors.ink, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ma’lumotlar Bazasi va Zaxira',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: context.inkColor,
                          ),
                        ),
                        Text(
                          'Disaster Recovery: Server yo‘qolsa ham 100% tiklash',
                          style: TextStyle(fontSize: 11.5, color: context.mutedColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: context.inkColor, size: 20),
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              if (_isLoading) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: AppColors.neonLime),
                      const SizedBox(height: 14),
                      Text(
                        _statusText ?? 'Amal bajarilmoqda...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // 1. SQL Zaxira yuklash tugmasi
                _ActionCard(
                  icon: Icons.storage_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: 'SQL Zaxira nusxasini yuklab olish (.sql)',
                  subtitle:
                      'Barcha jadvallar, qoldiqlar, mijozlar va savdolar SQL dump fayli sifatida kompyuteringizga saqlanadi.',
                  btnLabel: 'SQL Yuklab Olish',
                  btnColor: const Color(0xFF3B82F6),
                  onTap: _downloadSqlBackup,
                ),
                const SizedBox(height: 12),

                // 2. Excel hisoboti yuklash tugmasi
                _ActionCard(
                  icon: Icons.table_chart_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Excel / CSV ma’lumotlarini yuklab olish (.zip)',
                  subtitle:
                      'Mahsulotlar, mijozlar, savdolar va ombor jadvallarini Excel dasturida ko‘rish uchun qulay arxiv.',
                  btnLabel: 'Excel Yuklab Olish',
                  btnColor: const Color(0xFF10B981),
                  onTap: _downloadExcelBackup,
                ),
                const SizedBox(height: 12),

                // 3. Qayta tiklash tugmasi (Qizil hoshiyali xavfsizlik kartochkasi)
                _ActionCard(
                  icon: Icons.restore_page_rounded,
                  iconColor: const Color(0xFFEF4444),
                  title: 'Zaxiradan qayta tiklash (.sql fayl orqali)',
                  subtitle:
                      'Server tozalangan yoki yangi server ochilgan taqdirda, avval saqlangan .sql faylini yuklab butun bazani bir zumda tiklash.',
                  btnLabel: 'Faylni tanlash va tiklash',
                  btnColor: const Color(0xFFEF4444),
                  onTap: _restoreFromSql,
                  isDestructive: true,
                ),
              ],

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Yopish'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.btnLabel,
    required this.btnColor,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String btnLabel;
  final Color btnColor;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDestructive ? const Color(0xFFEF4444).withValues(alpha: 0.3) : context.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: context.inkColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: context.mutedColor, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(btnLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: btnColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
