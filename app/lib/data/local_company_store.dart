import 'dart:convert';
import 'dart:io';

/// Korxona rekvizitlari va aloqa telefonlarini lokal xotirada saqlash
class LocalCompanyStore {
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
    return File('${_getBaseDir().path}/company_settings.json');
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
    try {
      final f = _getFile();
      if (f.existsSync()) {
        f.deleteSync();
      }
    } catch (_) {}
  }
}
