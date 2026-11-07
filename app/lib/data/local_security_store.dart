import 'dart:convert';
import 'dart:io';

/// Xodimlar ilova qulfi (PIN-kod) ma'lumotlarini lokal xotirada saqlash
class LocalSecurityStore {
  static Directory _getBaseDir() {
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
  }

  static File _getFile() {
    return File('${_getBaseDir().path}/app_security.json');
  }

  static Map<String, dynamic> _readData() {
    try {
      final f = _getFile();
      if (!f.existsSync()) return {};
      final text = f.readAsStringSync();
      if (text.trim().isEmpty) return {};
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static void _writeData(Map<String, dynamic> data) {
    try {
      final f = _getFile();
      f.writeAsStringSync(jsonEncode(data));
    } catch (_) {}
  }

  /// Foydalanuvchi PIN kodi mavjudligini tekshirish
  static bool hasPin(int userId) {
    final data = _readData();
    final pins = data['pins'] as Map<String, dynamic>?;
    if (pins == null) return false;
    final userMap = pins['$userId'] as Map<String, dynamic>?;
    if (userMap == null) return false;
    final pin = userMap['pin'] as String?;
    return pin != null && pin.trim().length >= 4;
  }

  /// Foydalanuvchi PIN kodini olish
  static String? getPin(int userId) {
    final data = _readData();
    final pins = data['pins'] as Map<String, dynamic>?;
    if (pins == null) return null;
    final userMap = pins['$userId'] as Map<String, dynamic>?;
    if (userMap == null) return null;
    return userMap['pin'] as String?;
  }

  /// Ilova qulfi faolligini tekshirish (foydalanuvchi yoqganmi)
  static bool isLockEnabled(int userId) {
    final data = _readData();
    final pins = data['pins'] as Map<String, dynamic>?;
    if (pins == null) return false;
    final userMap = pins['$userId'] as Map<String, dynamic>?;
    if (userMap == null) return false;
    final enabled = userMap['enabled'] as bool?;
    final pin = userMap['pin'] as String?;
    return (enabled ?? true) && pin != null && pin.trim().length >= 4;
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
    final userMap = pins['$userId'] as Map<String, dynamic>?;
    if (userMap != null) {
      userMap['enabled'] = enabled;
      userMap['updated_at'] = DateTime.now().toIso8601String();
      pins['$userId'] = userMap;
      data['pins'] = pins;
      _writeData(data);
    }
  }

  /// PIN kodni o'chirish
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
