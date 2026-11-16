import 'dart:async';

import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'offline_cache_store.dart';

/// Stonex ERP Oflayn Sinxronizatsiya Dvigateli.
/// Barcha rollar uchun internet uzilganda to'xtovsiz ishlashni va
/// internet paydo bo'lganda avtomatik yangilanishni ta'minlaydi.
class OfflineSyncEngine extends ChangeNotifier {
  OfflineSyncEngine._();
  static final OfflineSyncEngine instance = OfflineSyncEngine._();

  bool _isOnline = true;
  bool _isSyncing = false;
  int _pendingCount = 0;
  DateTime? _lastSyncTime;
  Timer? _timer;
  ApiClient? _api;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Tizim ishga tushganda avtomatik tekshiruvlarni boshlash
  void init(ApiClient api) {
    _api = api;
    _pendingCount = OfflineCacheStore.loadPendingSales().length;
    _timer?.cancel();
    // Har 15 soniyada tarmoqni tekshirish va kutilayotgan savdolarni yuborish
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      checkAndSync();
    });
    // Boshlanishida darhol tekshirish
    checkAndSync();
  }

  /// Foydalanuvchi tizimga kirganida (login) orqa fonda barcha ma'lumotlarni
  /// kassir yoki boshqa xodimning ishlashiga halaqit bermasdan (non-blocking) yuklab qo'yish
  void preloadDataAsync(ApiClient api) {
    _api = api;
    unawaited(_doPreload(api));
  }

  Future<void> _doPreload(ApiClient api) async {
    try {
      debugPrint('[OfflineSyncEngine] Orqa fonda ma\'lumotlar keshlanmoqda...');
      // 1. Mahsulotlarni olish va keshga saqlash
      final prods = await api.get('/products') as List?;
      if (prods != null) {
        final list = prods.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        OfflineCacheStore.saveProducts(list);
        debugPrint('[OfflineSyncEngine] ${list.length} ta mahsulot keshlandi.');
      }

      // 2. Mijozlarni olish va keshga saqlash
      final custs = await api.get('/customers') as List?;
      if (custs != null) {
        final list = custs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        OfflineCacheStore.saveCustomers(list);
        debugPrint('[OfflineSyncEngine] ${list.length} ta mijoz keshlandi.');
      }

      // 3. Valyuta kursini keshga saqlash
      try {
        final f = await api.get('/finance/summary');
        if (f != null && f is Map && f['currency_rate'] != null) {
          final rate = (f['currency_rate'] as num).toDouble();
          OfflineCacheStore.saveCurrencyRate(rate);
        }
      } catch (_) {}

      _isOnline = true;
      _lastSyncTime = DateTime.now();
      _pendingCount = OfflineCacheStore.loadPendingSales().length;
      notifyListeners();
    } catch (e) {
      debugPrint('[OfflineSyncEngine] Preload xabari (oflayn bo\'lishi mumkin): $e');
      _isOnline = false;
      notifyListeners();
    }
  }

  /// Aloqani tekshirish va navbatdagi oflayn ma'lumotlarni sinxronlash
  Future<void> checkAndSync() async {
    if (_api == null) return;
    final api = _api!;

    final wasOnline = _isOnline;
    bool onlineNow = false;

    try {
      // Tezkor ping tekshiruvi (4 soniyalik timeout bilan)
      final res = await api.get('/ping').timeout(const Duration(seconds: 4));
      onlineNow = res != null;
    } catch (_) {
      onlineNow = false;
    }

    _isOnline = onlineNow;
    _pendingCount = OfflineCacheStore.loadPendingSales().length;

    // Agar internet qayta ulangan bo'lsa yoki navbatda ma'lumotlar bo'lsa
    if (_isOnline && _pendingCount > 0 && !_isSyncing) {
      await syncPendingSales();
    } else if (_isOnline && !wasOnline) {
      // Aloqa tiklandi, eng so'nggi tovar qoldiqlarini yangilab olamiz
      unawaited(_doPreload(api));
    }

    notifyListeners();
  }

  /// Oflayn savdoni navbatga qo'shish
  void queueOfflineSale(Map<String, dynamic> salePayload, {required List<Map<String, dynamic>> items}) {
    final offlineId = 'OFF-${DateTime.now().millisecondsSinceEpoch}';
    salePayload['offline_id'] = offlineId;
    salePayload['created_at'] = DateTime.now().toIso8601String();

    // 1. Navbatga saqlash
    OfflineCacheStore.addPendingSale(salePayload);

    // 2. Tovar qoldiqlarini lokal keshda darhol kamaytirish
    for (final it in items) {
      final pid = it['product_id'] as int?;
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
      if (pid != null && qty > 0) {
        OfflineCacheStore.decrementProductStock(pid, qty);
      }
    }

    _pendingCount = OfflineCacheStore.loadPendingSales().length;
    notifyListeners();

    // Agar internet bor bo'lsa darhol uzatishga urinib ko'rish
    if (_isOnline && !_isSyncing) {
      unawaited(syncPendingSales());
    }
  }

  /// Kutilayotgan barcha oflayn savdolarni serverga avtomatik yuborish
  Future<void> syncPendingSales() async {
    if (_api == null || _isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final pending = OfflineCacheStore.loadPendingSales();
      for (final salePayload in pending) {
        final offlineId = salePayload['offline_id'] as String?;
        try {
          final sendData = Map<String, dynamic>.from(salePayload);

          await _api!.post('/sales', body: sendData);

          // Muvaffaqiyatli saqlandi — navbatdan o'chirish
          if (offlineId != null) {
            OfflineCacheStore.removePendingSale(offlineId);
          }
        } catch (e) {
          debugPrint('[OfflineSyncEngine] Oflayn savdoni yuborishda xatolik: $e');
          // Agar server xatolik bersa (masalan internet uzilsa), keyingi ciklga qoldiramiz
          break;
        }
      }

      // Sinxronizatsiyadan keyin yangi server balanslarini yangilab olish
      await _doPreload(_api!);
    } finally {
      _isSyncing = false;
      _pendingCount = OfflineCacheStore.loadPendingSales().length;
      _lastSyncTime = DateTime.now();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
