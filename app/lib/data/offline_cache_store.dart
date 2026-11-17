import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'local_storage_service.dart';

/// Stonex ERP Oflayn Kesh va Ma'lumotlar ombori.
/// Android, Windows va Vebda ma'lumotlar xotirada doimiy saqlanadi.
class OfflineCacheStore {
  static Directory? _getCacheDir() {
    if (kIsWeb) return null;
    try {
      final appData = Platform.environment['APPDATA'] ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path;
      final dir = Directory('$appData/stonex_erp/offline_cache');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  static File? _getFile(String filename) {
    final dir = _getCacheDir();
    if (dir == null) return null;
    return File('${dir.path}/$filename');
  }

  static String? _readString(String filename) {
    try {
      final key = 'stonex_cache_$filename';
      final val = LocalStorageService.getString(key);
      if (val != null && val.trim().isNotEmpty) return val;
      final f = _getFile(filename);
      if (f != null && f.existsSync()) {
        final text = f.readAsStringSync();
        if (text.trim().isNotEmpty) {
          LocalStorageService.setString(key, text);
          return text;
        }
      }
    } catch (_) {}
    return null;
  }

  static void _writeString(String filename, String content) {
    try {
      final key = 'stonex_cache_$filename';
      LocalStorageService.setString(key, content);
      final f = _getFile(filename);
      if (f != null) {
        f.writeAsStringSync(content);
      }
    } catch (_) {}
  }

  // ==================== MAHSULOTLAR KESHI ====================

  static void saveProducts(List<Map<String, dynamic>> productsJson) {
    try {
      final data = {
        'saved_at': DateTime.now().toIso8601String(),
        'items': productsJson,
      };
      _writeString('products_cache.json', jsonEncode(data));
    } catch (_) {}
  }

  static List<Map<String, dynamic>> loadProducts() {
    try {
      final text = _readString('products_cache.json');
      if (text == null) return [];
      final data = jsonDecode(text) as Map<String, dynamic>;
      final list = data['items'] as List?;
      if (list != null) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Oflayn savdoda tovar qoldig'ini lokal keshda darhol kamaytirish
  static void decrementProductStock(int productId, double quantity) {
    try {
      final products = loadProducts();
      bool changed = false;
      for (final p in products) {
        if (p['id'] == productId) {
          final curStock = (p['stock'] as num?)?.toDouble() ?? 0.0;
          p['stock'] = (curStock - quantity).clamp(0.0, 9999999.0);
          changed = true;
          break;
        }
      }
      if (changed) {
        saveProducts(products);
      }
    } catch (_) {}
  }

  // ==================== MIJOZLAR KESHI ====================

  static void saveCustomers(List<Map<String, dynamic>> customersJson) {
    try {
      final data = {
        'saved_at': DateTime.now().toIso8601String(),
        'items': customersJson,
      };
      _writeString('customers_cache.json', jsonEncode(data));
    } catch (_) {}
  }

  static List<Map<String, dynamic>> loadCustomers() {
    try {
      final text = _readString('customers_cache.json');
      if (text == null) return [];
      final data = jsonDecode(text) as Map<String, dynamic>;
      final list = data['items'] as List?;
      if (list != null) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ==================== VALYUTA KURSI KESHI ====================

  static void saveCurrencyRate(double rate) {
    try {
      final data = {
        'saved_at': DateTime.now().toIso8601String(),
        'rate': rate,
      };
      _writeString('currency_rate_cache.json', jsonEncode(data));
    } catch (_) {}
  }

  static double? loadCurrencyRate() {
    try {
      final text = _readString('currency_rate_cache.json');
      if (text == null) return null;
      final data = jsonDecode(text) as Map<String, dynamic>;
      return (data['rate'] as num?)?.toDouble();
    } catch (_) {}
    return null;
  }

  // ==================== OFLAYN SAVDOLAR NAVBATI (OUTBOX) ====================

  static List<Map<String, dynamic>> loadPendingSales() {
    try {
      final text = _readString('offline_sales_queue.json');
      if (text == null) return [];
      final list = jsonDecode(text) as List?;
      if (list != null) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  static void addPendingSale(Map<String, dynamic> salePayload) {
    try {
      final list = loadPendingSales();
      list.add(salePayload);
      _writeString('offline_sales_queue.json', jsonEncode(list));
    } catch (_) {}
  }

  static void removePendingSale(String offlineId) {
    try {
      final list = loadPendingSales();
      list.removeWhere((item) => item['offline_id'] == offlineId);
      _writeString('offline_sales_queue.json', jsonEncode(list));
    } catch (_) {}
  }

  static void clearPendingSales() {
    try {
      _writeString('offline_sales_queue.json', '[]');
    } catch (_) {}
  }

  // ==================== STATISTIKA ====================

  static Map<String, dynamic> getStats() {
    final p = loadProducts();
    final c = loadCustomers();
    final q = loadPendingSales();
    final rate = loadCurrencyRate();
    return {
      'cached_products_count': p.length,
      'cached_customers_count': c.length,
      'pending_sales_count': q.length,
      'currency_rate': rate,
    };
  }
}
