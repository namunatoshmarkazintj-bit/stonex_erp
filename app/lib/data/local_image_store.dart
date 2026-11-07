import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// Mahsulot va mijoz rasmlarini lokal xotirada keshda saqlash va sinxronlash.
///
/// Rasmlar qurilmaning lokal `img_cache` papkasiga yuklab saqlanadi.
/// Keyingi safar internetga murojaat qilmasdan to'g'ridan-to'g'ri lokal xotiradan
/// bir zumda (chaqmoqdek tez) ochiladi va internet trafigini tejaydi.
class LocalImageStore {
  static final Map<String, String> _cache = {};
  static bool _loaded = false;
  static bool _saveScheduled = false;
  static final Set<String> _inFlight = {};

  static Directory _getBaseDir() {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = Directory('${Directory.systemTemp.path}/stonex_erp');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return dir.existsSync() ? dir : Directory.systemTemp;
    }
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

  static Directory _getCacheDir() {
    final base = _getBaseDir();
    final cacheDir = Directory('${base.path}/img_cache');
    if (!cacheDir.existsSync()) {
      try {
        cacheDir.createSync(recursive: true);
      } catch (_) {}
    }
    return cacheDir;
  }

  static File _getFile() {
    return File('${_getBaseDir().path}/product_images.json');
  }

  static void _schedulePersist() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    Future.delayed(const Duration(milliseconds: 300), () {
      _saveScheduled = false;
      try {
        final f = _getFile();
        f.writeAsStringSync(jsonEncode(_cache));
      } catch (_) {}
    });
  }

  static void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = _getFile();
      if (f.existsSync()) {
        final text = f.readAsStringSync();
        if (text.isNotEmpty) {
          final data = jsonDecode(text) as Map<String, dynamic>;
          for (final e in data.entries) {
            _cache[e.key] = e.value.toString();
          }
        }
      }
    } catch (_) {}
  }

  /// URL yoki fayl nomidan xavfsiz fayl nomini hosil qilish
  static String _urlToFilename(String url) {
    var clean = url.trim();
    if (clean.contains('?')) clean = clean.split('?').first;
    final lastSlash = clean.lastIndexOf('/');
    final segment = lastSlash != -1 ? clean.substring(lastSlash + 1) : clean;
    final safe = segment.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (safe.isNotEmpty && (safe.endsWith('.jpg') || safe.endsWith('.jpeg') || safe.endsWith('.png') || safe.endsWith('.webp'))) {
      return safe;
    }
    final hash = url.hashCode.toRadixString(16);
    return 'img_$hash.jpg';
  }

  /// Lokal keshda rasm fayli bormi-yo'qligini tekshirish
  static File? getCachedFile(String rawUrl) {
    if (rawUrl.isEmpty || rawUrl.startsWith('data:image/')) return null;
    try {
      final resolved = ApiClient.resolveUrl(rawUrl);
      final filename = _urlToFilename(resolved);
      final file = File('${_getCacheDir().path}/$filename');
      if (file.existsSync() && file.lengthSync() > 100) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Rasmni fonda yuklab olib, lokal papkaga saqlash
  static Future<File?> downloadAndCache(String rawUrl) async {
    if (rawUrl.isEmpty || rawUrl.startsWith('data:image/')) return null;
    final resolved = ApiClient.resolveUrl(rawUrl);
    if (!resolved.startsWith('http://') && !resolved.startsWith('https://')) return null;

    final existing = getCachedFile(resolved);
    if (existing != null) return existing;

    if (_inFlight.contains(resolved)) return null;
    _inFlight.add(resolved);

    try {
      final client = http.Client();
      final res = await client.get(Uri.parse(resolved)).timeout(const Duration(seconds: 15));
      client.close();
      if (res.statusCode == 200 && res.bodyBytes.length > 50) {
        final filename = _urlToFilename(resolved);
        final file = File('${_getCacheDir().path}/$filename');
        await file.writeAsBytes(res.bodyBytes);
        return file;
      }
    } catch (_) {
    } finally {
      _inFlight.remove(resolved);
    }
    return null;
  }

  /// Barcha rasmlarni dastur ochilganda orqa fonda yuklab keshga joylash
  static void prefetchAll(List<String?> urls) {
    Future.microtask(() async {
      for (final u in urls) {
        if (u != null && u.trim().isNotEmpty) {
          await downloadAndCache(u);
          // Tarmoqni ortiqcha yuklamaslik uchun kichik tanaffus
          await Future.delayed(const Duration(milliseconds: 30));
        }
      }
    });
  }

  /// Base64 rasm kelsa, uni darhol diskdagi `.jpg` faylga aylantirib saqlaydi
  static String? _normalizeImage(String? raw, String prefix) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    if (trimmed.startsWith('data:image/') || trimmed.length > 500) {
      try {
        final comma = trimmed.indexOf(',');
        final b64 = comma != -1 ? trimmed.substring(comma + 1).trim() : trimmed;
        final bytes = base64Decode(b64);
        final file = File('${_getCacheDir().path}/${prefix}.jpg');
        file.writeAsBytesSync(bytes);
        return file.path;
      } catch (_) {
        return null;
      }
    }
    return trimmed;
  }

  static String? getImage(int productId, [String? name]) {
    _ensureLoaded();
    if (_cache.containsKey(productId.toString())) {
      return _cache[productId.toString()];
    }
    if (name != null) {
      final nameKey = 'name_${name.trim().toLowerCase()}';
      if (_cache.containsKey(nameKey)) {
        return _cache[nameKey];
      }
    }
    return null;
  }

  static void saveImage(int productId, String? imageUrl, [String? name]) {
    _ensureLoaded();
    final key = productId.toString();
    final nameKey = name != null ? 'name_${name.trim().toLowerCase()}' : null;

    final norm = _normalizeImage(imageUrl, 'prod_$productId');
    if (norm == null) {
      _cache.remove(key);
      if (nameKey != null) _cache.remove(nameKey);
    } else {
      _cache[key] = norm;
      if (nameKey != null) _cache[nameKey] = norm;
    }

    _schedulePersist();
  }

  static String? getCustomerImage(int? customerId, [String? phone, String? name]) {
    _ensureLoaded();
    if (customerId != null && _cache.containsKey('cust_$customerId')) {
      return _cache['cust_$customerId'];
    }
    if (phone != null && phone.trim().isNotEmpty) {
      final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
      if (phoneDigits.isNotEmpty && _cache.containsKey('cust_phone_$phoneDigits')) {
        return _cache['cust_phone_$phoneDigits'];
      }
    }
    if (name != null && name.trim().isNotEmpty) {
      final nameKey = 'cust_name_${name.trim().toLowerCase()}';
      if (_cache.containsKey(nameKey)) {
        return _cache[nameKey];
      }
    }
    return null;
  }

  static void saveCustomerImage(int? customerId, String? photoUrl, [String? phone, String? name]) {
    _ensureLoaded();
    final key = customerId != null ? 'cust_$customerId' : null;
    final phoneDigits = phone != null ? phone.replaceAll(RegExp(r'\D'), '') : '';
    final phoneKey = phoneDigits.isNotEmpty ? 'cust_phone_$phoneDigits' : null;
    final nameKey = name != null && name.trim().isNotEmpty ? 'cust_name_${name.trim().toLowerCase()}' : null;

    final norm = _normalizeImage(photoUrl, 'cust_${customerId ?? phoneDigits}');
    if (norm == null) {
      if (key != null) _cache.remove(key);
      if (phoneKey != null) _cache.remove(phoneKey);
      if (nameKey != null) _cache.remove(nameKey);
    } else {
      if (key != null) _cache[key] = norm;
      if (phoneKey != null) _cache[phoneKey] = norm;
      if (nameKey != null) _cache[nameKey] = norm;
    }

    _schedulePersist();
  }
}
