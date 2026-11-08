import 'dart:convert';
import 'dart:io';

/// Standart chek printeri (USB yoki Bluetooth) sozlamalarini saqlash
class LocalPrinterStore {
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
    return File('${_getBaseDir().path}/printer_settings.json');
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
