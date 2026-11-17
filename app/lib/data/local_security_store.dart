import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'local_storage_service.dart';

/// Xodimlar ilova qulfi (PIN-kod) ma'lumotlarini lokal xotirada saqlash.
/// Android, Windows va Vebda doimiy va ishonchli saqlanadi.
class LocalSecurityStore {
  static const String _prefKey = 'stonex_erp_security_v3';

  static File? _getDesktopFile() {
    if (kIsWeb) return null;
    try {
      final appData = Platform.environment['APPDATA'] ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path;
      final dir = Directory('$appData/stonex_erp');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/app_security.json');
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _readData() {
    try {
      String? text = LocalStorageService.getString(_prefKey);
      if (text == null || text.trim().isEmpty) {
        final f = _getDesktopFile();
        if (f != null && f.existsSync()) {
          text = f.readAsStringSync();
          if (text.trim().isNotEmpty) {
            LocalStorageService.setString(_prefKey, text);
          }
        }
      }
      if (text == null || text.trim().isEmpty) return {};
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static void _writeData(Map<String, dynamic> data) {
    try {
      final jsonStr = jsonEncode(data);
      LocalStorageService.setString(_prefKey, jsonStr);
      final f = _getDesktopFile();
      if (f != null) {
        f.writeAsStringSync(jsonStr);
      }
    } catch (_) {}
  }

  /// Foydalanuvchi maxsus PIN kod o'rnatganligini tekshirish
  static bool hasCustomPin(int userId) {
    final data = _readData();
    final pins = data['pins'] as Map<String, dynamic>?;
    if (pins == null) return false;
    final userMap = pins['$userId'] as Map<String, dynamic>?;
    if (userMap == null) return false;
    final pin = userMap['pin'] as String?;
    return pin != null && pin.trim().length >= 4;
  }

  /// Foydalanuvchi PIN kodi mavjudmi (har doim kamida standart 1234 mavjud)
  static bool hasPin(int userId) => true;

  /// Foydalanuvchi PIN kodini olish (o'rnatilmagan bo'lsa standart '1234')
  static String getPin(int userId) {
    final data = _readData();
    final pins = data['pins'] as Map<String, dynamic>?;
    if (pins != null) {
      final userMap = pins['$userId'] as Map<String, dynamic>?;
      if (userMap != null) {
        final pin = userMap['pin'] as String?;
        if (pin != null && pin.trim().length >= 4) {
          return pin.trim();
        }
      }
    }
    return '1234'; // Standart PIN kod
  }

  /// Ilova qulfi faolligini tekshirish (har doim faol)
  static bool isLockEnabled(int userId) {
    final data = _readData();
    final pins = data['pins'] as Map<String, dynamic>?;
    if (pins != null) {
      final userMap = pins['$userId'] as Map<String, dynamic>?;
      if (userMap != null) {
        final enabled = userMap['enabled'] as bool?;
        if (enabled != null) return enabled;
      }
    }
    return true; // Standart: 4 talik PIN kod bilan himoyalangan
  }

  /// Yangi PIN kodni saqlash
  static void savePin({required int userId, required String pin, bool enabled = true}) {
    final data = _readData();
    final pins = (data['pins'] as Map<String, dynamic>?) ?? {};
    pins['$userId'] = {
      'pin': pin.trim(),
      'enabled': enabled,
      'updated_at': DateTime.now().toIso8601String(),
    };
    data['pins'] = pins;
    _writeData(data);
  }

  /// Qulfni vaqtincha yoqish yoki o'chirish
  static void setLockEnabled({required int userId, required bool enabled}) {
    final data = _readData();
    final pins = (data['pins'] as Map<String, dynamic>?) ?? {};
    final userMap = pins['$userId'] as Map<String, dynamic>? ?? {};
    userMap['enabled'] = enabled;
    userMap['updated_at'] = DateTime.now().toIso8601String();
    pins['$userId'] = userMap;
    data['pins'] = pins;
    _writeData(data);
  }

  /// PIN kodni o'chirish (standart 1234 ga qaytarish)
  static void removePin(int userId) {
    final data = _readData();
    final pins = data['pins'] as Map<String, dynamic>?;
    if (pins != null && pins.containsKey('$userId')) {
      pins.remove('$userId');
      data['pins'] = pins;
      _writeData(data);
    }
  }
}
