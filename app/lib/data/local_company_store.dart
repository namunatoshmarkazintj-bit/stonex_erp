import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Korxona rekvizitlari va aloqa telefonlarini lokal xotirada saqlash
class LocalCompanyStore {
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
    return File('${dir.path}/company_settings.json');
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

  static String? getName() {
    final d = _readData();
    return d['name'] as String?;
  }

  static String? getAddress() {
    final d = _readData();
    return d['address'] as String?;
  }

  static List<String>? getPhones() {
    final d = _readData();
    final p = d['phones'];
    if (p is List) {
      final res = p.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      if (res.isNotEmpty) return res;
    }
    return null;
  }

  static void save({
    required String name,
    required String address,
    required List<String> phones,
  }) {
    _writeData({
      'name': name.trim(),
      'address': address.trim(),
      'phones': phones.map((p) => p.trim()).where((p) => p.isNotEmpty).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static void resetToDefault() {
    _memoryCache.clear();
    if (kIsWeb) return;
    try {
      final f = _getFile();
      if (f != null && f.existsSync()) {
        f.deleteSync();
      }
    } catch (_) {}
  }
}
