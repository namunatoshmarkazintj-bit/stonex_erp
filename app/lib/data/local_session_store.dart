import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../domain/models.dart';
import 'local_storage_service.dart';

/// Foydalanuvchi sessiyasini lokal xotirada saqlash.
/// Android, Windows va Vebda bir marta kirilgach qaytib login so'ramaydi.
class LocalSessionStore {
  static const String _prefKey = 'stonex_erp_session_v3';

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
      return File('${dir.path}/session.json');
    } catch (_) {
      return null;
    }
  }

  static void saveSession({required String token, required AppUser user}) {
    try {
      final data = {
        'token': token,
        'user': user.toJson(),
        'saved_at': DateTime.now().toIso8601String(),
      };
      final jsonStr = jsonEncode(data);

      // 1. SharedPreferences orqali doimiy saqlash (Android, Web, Windows)
      LocalStorageService.setString(_prefKey, jsonStr);

      // 2. Desktop (Windows) uchun faylga zaxira nusxa saqlash
      final f = _getDesktopFile();
      if (f != null) {
        f.writeAsStringSync(jsonStr);
      }
    } catch (_) {}
  }

  static ({String token, AppUser user})? loadSession() {
    try {
      // 1. Avval SharedPreferences'dan o'qish
      String? text = LocalStorageService.getString(_prefKey);

      // 2. Agar bo'lmasa, desktop fayldan tekshirish
      if (text == null || text.trim().isEmpty) {
        final f = _getDesktopFile();
        if (f != null && f.existsSync()) {
          text = f.readAsStringSync();
          if (text.trim().isNotEmpty) {
            LocalStorageService.setString(_prefKey, text);
          }
        }
      }

      if (text == null || text.trim().isEmpty) return null;
      final data = jsonDecode(text) as Map<String, dynamic>;
      final token = data['token'] as String?;
      final userMap = data['user'] as Map<String, dynamic>?;
      if (token != null && token.isNotEmpty && userMap != null) {
        return (token: token, user: AppUser.fromJson(userMap));
      }
    } catch (_) {}
    return null;
  }

  static void clearSession() {
    try {
      LocalStorageService.remove(_prefKey);
      final f = _getDesktopFile();
      if (f != null && f.existsSync()) {
        f.deleteSync();
      }
    } catch (_) {}
  }
}
