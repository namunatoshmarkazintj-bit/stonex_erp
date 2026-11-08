import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Standart chek printeri (USB yoki Bluetooth) sozlamalarini saqlash
class LocalPrinterStore {
  static final Map<String, dynamic> _memoryCache = {};

  static Directory? _getBaseDir() {
    if (kIsWeb) return null;
    try {
      final appData = Platform.environment['APPDATA'] ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path;
      final dir = Directory('$appData/stonex_erp');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  static File? _getFile() {
    final dir = _getBaseDir();
    if (dir == null) return null;
    return File('${dir.path}/printer_settings.json');
  }

  static Map<String, dynamic> _readData() {
    if (kIsWeb) return _memoryCache;
    try {
      final f = _getFile();
      if (f == null || !f.existsSync()) return _memoryCache;
      final text = f.readAsStringSync();
      if (text.trim().isEmpty) return _memoryCache;
      final data = jsonDecode(text) as Map<String, dynamic>;
      _memoryCache.addAll(data);
      return data;
    } catch (_) {
      return _memoryCache;
    }
  }

  static void _writeData(Map<String, dynamic> data) {
    _memoryCache.clear();
    _memoryCache.addAll(data);
    if (kIsWeb) return;
    try {
      final f = _getFile();
      if (f != null) {
        f.writeAsStringSync(jsonEncode(data));
      }
    } catch (_) {}
  }

  /// Eslab qolingan printer URL (identifikatori)
  static String? getSavedPrinterUrl() {
    final data = _readData();
    return data['url'] as String?;
  }

  /// Eslab qolingan printer nomi (masalan, "Xprinter XP-80")
  static String? getSavedPrinterName() {
    final data = _readData();
    return data['name'] as String?;
  }

  /// Printerni doimiy qilib saqlash
  static void savePrinter(String url, String name) {
    _writeData({
      'url': url,
      'name': name,
      'saved_at': DateTime.now().toIso8601String(),
    });
  }

  /// Eslab qolingan printerni tozalash (har safar so'rash uchun)
  static void clearPrinter() {
    _writeData({});
  }
}
