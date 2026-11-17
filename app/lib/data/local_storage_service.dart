import 'package:shared_preferences/shared_preferences.dart';

/// Stonex ERP Universal Lokal Xotira Xizmati.
/// Android (SharedPreferences), Windows Desktop (AppData), Web (localStorage) va iOS
/// platformalarida ma'lumotlar doimiy va xavfsiz saqlanishini ta'minlaydi.
class LocalStorageService {
  static SharedPreferences? _prefs;

  /// Ilova ishga tushganda bir marta chaqiriladi
  static Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {}
  }

  static SharedPreferences? get instance => _prefs;

  static String? getString(String key) {
    try {
      return _prefs?.getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setString(String key, String value) async {
    try {
      if (_prefs == null) await init();
      return await _prefs?.setString(key, value) ?? false;
    } catch (_) {
      return false;
    }
  }

  static bool? getBool(String key) {
    try {
      return _prefs?.getBool(key);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setBool(String key, bool value) async {
    try {
      if (_prefs == null) await init();
      return await _prefs?.setBool(key, value) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> remove(String key) async {
    try {
      if (_prefs == null) await init();
      return await _prefs?.remove(key) ?? false;
    } catch (_) {
      return false;
    }
  }
}
