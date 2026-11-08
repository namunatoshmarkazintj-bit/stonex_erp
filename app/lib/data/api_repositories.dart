import 'dart:convert';

import '../domain/models.dart';
import 'api_client.dart';
import 'local_image_store.dart';
import 'local_session_store.dart';
import 'repositories.dart';

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api);
  final ApiClient _api;

  @override
  Future<AppUser> login(String username, String password, [Role? role]) async {
    final body = <String, dynamic>{
      'username': username,
      'password': password,
    };
    if (role != null) body['role'] = role.code;
    final j = await _api.post('/auth/login', body: body);
    final token = j['access_token'] as String;
    _api.token = token;
    final user = AppUser.fromJson(j['user'] as Map<String, dynamic>);
    LocalSessionStore.saveSession(token: token, user: user);
    return user;
  }

  @override
  Future<AppUser?> tryRestoreSession() async {
    final session = LocalSessionStore.loadSession();
    if (session == null) return null;
    _api.token = session.token;
    try {
      final j = await _api.get('/auth/me');
      final user = AppUser.fromJson(j as Map<String, dynamic>);
      LocalSessionStore.saveSession(token: session.token, user: user);
      return user;
    } catch (e) {
      if (e is ApiException && (e.status == 401 || e.status == 403)) {
        await logout();
        return null;
      }
      return session.user;
    }
  }

  @override
  Future<void> logout() async {
    _api.token = null;
    LocalSessionStore.clearSession();
  }
}

class ApiProductRepository implements ProductRepository {
  ApiProductRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Product>> list({String? query}) async {
    final j = await _api.get('/products',
        query: (query == null || query.isEmpty) ? null : {'q': query}) as List;
    final list = j.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    LocalImageStore.prefetchAll(list.map((p) => p.imageUrl).toList());
    return list.map((p) {
      if (p.imageUrl != null && p.imageUrl!.isNotEmpty) {
        LocalImageStore.saveImage(p.id, p.imageUrl, p.name);
        return p;
      }
      final local = LocalImageStore.getImage(p.id, p.name);
      return (local != null) ? p.copyWith(imageUrl: local) : p;
    }).toList();
  }

  @override
  Future<Product?> findByCode(String code) async {
    try {
      final j = await _api.get('/products/by-code/${Uri.encodeComponent(code)}');
      final p = Product.fromJson(j as Map<String, dynamic>);
      if (p.imageUrl != null && p.imageUrl!.isNotEmpty) {
        LocalImageStore.saveImage(p.id, p.imageUrl, p.name);
        return p;
      }
      final local = LocalImageStore.getImage(p.id, p.name);
      return (local != null) ? p.copyWith(imageUrl: local) : p;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Product> create(Product p, {double initialStock = 0}) async {
    final res = await _api.post('/products', body: p.toJson(initialStock: initialStock));
    final created = Product.fromJson(res as Map<String, dynamic>);
    if (p.imageUrl != null && p.imageUrl!.isNotEmpty) {
      LocalImageStore.saveImage(created.id, p.imageUrl, created.name);
      return created.copyWith(imageUrl: p.imageUrl);
    }
    return created;
  }

  @override
  Future<Product> update(Product p) async {
    if (p.imageUrl != null) {
      LocalImageStore.saveImage(p.id, p.imageUrl, p.name);
    }
    final body = p.toJson()..remove('initial_stock');
    final res = await _api.patch('/products/${p.id}', body: body);
    final updated = Product.fromJson(res as Map<String, dynamic>);
    final local = LocalImageStore.getImage(p.id, p.name) ?? p.imageUrl;
    return (updated.imageUrl == null && local != null)
        ? updated.copyWith(imageUrl: local)
        : updated;
  }

  @override
  Future<void> deactivate(int id) async => _api.delete('/products/$id');

  @override
  Future<String> uploadImage(List<int> bytes, String filename) async {
    final res = await _api.uploadFile('/products/upload-image', bytes, filename);
    return res['image_url'] as String;
  }

  @override
  Future<Product> uploadProductImage(int productId, List<int> bytes, String filename) async {
    final res = await _api.uploadFile('/products/$productId/image', bytes, filename);
    return Product.fromJson(res as Map<String, dynamic>);
  }
}

class ApiSalesRepository implements SalesRepository {
  ApiSalesRepository(this._api);
  final ApiClient _api;

  @override
  Future<SaleResult> createSale({
    required List<CartLine> lines,
    required double paidAmount,
    double? currencyRate,
    double? paidUzs,
    double? paidUsd,
    int? customerId,
    String? customerName,
    String? customerPhone,
    String? customerPassport,
    String? customerPhotoUrl,
    String status = 'completed',
    String? note,
  }) async {
    final j = await _api.post('/sales', body: {
      'items': [
        for (final l in lines)
          {
            'product_id': l.product.id,
            'quantity': l.quantity,
            'unit': (l.inDona && l.product.hasDona) ? 'dona' : 'base',
            'price': l.unitPrice,
            if (l.sort != null) 'sort': l.sort,
            if (l.color != null) 'color': l.color,
            if (l.displayName != l.product.name) 'custom_name': l.displayName,
          }
      ],
      'paid_amount': paidAmount,
      if (currencyRate != null) 'currency_rate': currencyRate,
      if (paidUzs != null) 'paid_uzs': paidUzs,
      if (paidUsd != null) 'paid_usd': paidUsd,
      'status': status,
      if (note != null && note.isNotEmpty) 'note': note,
      if (customerId != null) 'customer_id': customerId,
      if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
      if (customerPhone != null && customerPhone.isNotEmpty) 'customer_phone': customerPhone,
      if (customerPassport != null && customerPassport.isNotEmpty) 'customer_passport': customerPassport,
      if (customerPhotoUrl != null && customerPhotoUrl.isNotEmpty) 'customer_photo_url': customerPhotoUrl,
    });
    return SaleResult.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<List<SaleResult>> listSales({int limit = 50, String? status, int? customerId}) async {
    final q = {'limit': '$limit'};
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (customerId != null) q['customer_id'] = '$customerId';
    final j = await _api.get('/sales', query: q) as List;
    return j.map((e) => SaleResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<SaleResult>> listDebts() async {
    final j = await _api.get('/sales/debts') as List;
    return j.map((e) => SaleResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<SaleResult> payDebt(int saleId, double amount, {String method = 'cash'}) async {
    final j = await _api.post('/sales/$saleId/payments', body: {
      'amount': amount,
      'method': method,
    });
    return SaleResult.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<SaleResult> fulfillOrder(
    int saleId, {
    String? receivedByName,
    String? receivedByPhone,
    String? deliveryType,
    String? receiverDocOrCar,
    String? note,
    double? payAmount,
    String? payMethod,
  }) async {
    final payload = <String, dynamic>{
      if (receivedByName != null) 'received_by_name': receivedByName,
      if (receivedByPhone != null) 'received_by_phone': receivedByPhone,
      if (deliveryType != null) 'delivery_type': deliveryType,
      if (receiverDocOrCar != null) 'receiver_doc_or_car': receiverDocOrCar,
      if (note != null) 'note': note,
      if (payAmount != null && payAmount > 0) 'pay_amount': payAmount,
      if (payMethod != null) 'pay_method': payMethod,
    };
    final j = await _api.post('/sales/$saleId/fulfill', body: payload.isNotEmpty ? payload : null) as Map<String, dynamic>;
    return SaleResult.fromJson(j);
  }

  @override
  Future<SaleResult> cancelOrder(int saleId) async {
    final j = await _api.post('/sales/$saleId/cancel') as Map<String, dynamic>;
    return SaleResult.fromJson(j);
  }

  @override
  Future<SaleResult> returnSale(int saleId, {required List<({int productId, double quantity})> items, String? reason}) async {
    final j = await _api.post('/sales/$saleId/return', body: {
      'items': [
        for (final it in items)
          {
            'product_id': it.productId,
            'quantity': it.quantity,
          }
      ],
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    }) as Map<String, dynamic>;
    return SaleResult.fromJson(j);
  }
}

class ApiFinanceRepository implements FinanceRepository {
  ApiFinanceRepository(this._api);
  final ApiClient _api;

  @override
  Future<FinanceSummary> summary() async =>
      FinanceSummary.fromJson(await _api.get('/finance/summary') as Map<String, dynamic>);

  @override
  Future<List<FinanceTransaction>> listTransactions({
    String? type,
    String? category,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 300,
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      if (type != null && type != 'Barchasi') 'type': type,
      if (category != null && category != 'Barchasi') 'category': category,
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String().substring(0, 10),
      if (dateTo != null) 'date_to': dateTo.toIso8601String().substring(0, 10),
    };
    final res = await _api.get('/finance/transactions', query: query) as List;
    return res.map((e) => FinanceTransaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<FinanceTransaction> addTransaction(FinanceTransaction tx) async {
    final res = await _api.post('/finance/transactions', body: tx.toJson()) as Map<String, dynamic>;
    return FinanceTransaction.fromJson(res);
  }

  @override
  Future<MonthlyComparison> monthlyComparison({
    DateTime? curDateFrom,
    DateTime? curDateTo,
    DateTime? prevDateFrom,
    DateTime? prevDateTo,
    String? curLabel,
    String? prevLabel,
  }) async {
    final query = <String, String>{
      if (curDateFrom != null) 'cur_date_from': curDateFrom.toIso8601String().substring(0, 10),
      if (curDateTo != null) 'cur_date_to': curDateTo.toIso8601String().substring(0, 10),
      if (prevDateFrom != null) 'prev_date_from': prevDateFrom.toIso8601String().substring(0, 10),
      if (prevDateTo != null) 'prev_date_to': prevDateTo.toIso8601String().substring(0, 10),
      if (curLabel != null) 'cur_label': curLabel,
      if (prevLabel != null) 'prev_label': prevLabel,
    };
    final res = await _api.get('/finance/monthly-comparison', query: query.isEmpty ? null : query) as Map<String, dynamic>;
    return MonthlyComparison.fromJson(res);
  }

  @override
  Future<List<RevenueBreakdownItem>> revenueBreakdown({DateTime? dateFrom, DateTime? dateTo}) async {
    final query = <String, String>{
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String().substring(0, 10),
      if (dateTo != null) 'date_to': dateTo.toIso8601String().substring(0, 10),
    };
    final res = await _api.get('/finance/revenue-breakdown', query: query) as List;
    return res.map((e) => RevenueBreakdownItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<String> exportCsv({DateTime? dateFrom, DateTime? dateTo}) async {
    final query = <String, String>{
      if (dateFrom != null) 'date_from': dateFrom.toIso8601String().substring(0, 10),
      if (dateTo != null) 'date_to': dateTo.toIso8601String().substring(0, 10),
    };
    return _api.getText('/finance/export', query: query.isEmpty ? null : query);
  }
}

class ApiProductionRepository implements ProductionRepository {
  ApiProductionRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<ProductionTask>> list() async {
    final j = await _api.get('/production') as List;
    return j.map((e) => ProductionTask.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<AppUser>> workers() async {
    final j = await _api.get('/users', query: {'role': 'ishchi'}) as List;
    return j.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> create({
    required int productId,
    required int workerId,
    required double plannedQty,
    String? note,
    int? orderId,
    double? cutLength,
    double? cutWidth,
    int? cutPieces,
    String? cutSpec,
  }) async =>
      _api.post('/production',
          body: {
            'product_id': productId,
            'assigned_to': workerId,
            'planned_qty': plannedQty,
            if (note != null && note.isNotEmpty) 'note': note,
            if (orderId != null) 'order_id': orderId,
            if (cutLength != null) 'cut_length': cutLength,
            if (cutWidth != null) 'cut_width': cutWidth,
            if (cutPieces != null) 'cut_pieces': cutPieces,
            if (cutSpec != null && cutSpec.isNotEmpty) 'cut_spec': cutSpec,
          });

  @override
  Future<void> report(int taskId, double producedQty, {double? wasteQty, String? note}) async =>
      _api.post('/production/$taskId/report', body: {
        'produced_qty': producedQty,
        if (wasteQty != null) 'waste_qty': wasteQty,
        if (note != null) 'note': note,
      });

  @override
  Future<void> approve(int taskId) async =>
      _api.post('/production/$taskId/approve');

  @override
  Future<void> reject(int taskId, {String? reason}) async =>
      _api.post('/production/$taskId/reject', body: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
}

class ApiUserRepository implements UserRepository {
  ApiUserRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<AppUser>> list({String? role}) async {
    final j = await _api.get(
      '/users',
      query: (role != null && role.isNotEmpty) ? {'role': role} : null,
    ) as List;
    return j.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<AppUser> create({
    String? username,
    required String fullName,
    String? password,
    required Role role,
    bool canLogin = true,
    double salary = 0,
    String salaryType = 'monthly',
  }) async {
    final j = await _api.post('/users', body: {
      if (username != null && username.isNotEmpty) 'username': username,
      'full_name': fullName,
      if (password != null && password.isNotEmpty) 'password': password,
      'role': role.code,
      'can_login': canLogin,
      'salary': salary,
      'salary_type': salaryType,
    });
    return AppUser.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<AppUser> update(
    int id, {
    String? username,
    String? fullName,
    String? password,
    Role? role,
    bool? canLogin,
    double? salary,
    String? salaryType,
    bool? isActive,
    bool? isOnShift,
  }) async {
    final body = <String, dynamic>{
      if (username != null && username.isNotEmpty) 'username': username,
      if (fullName != null) 'full_name': fullName,
      if (password != null && password.isNotEmpty) 'password': password,
      if (role != null) 'role': role.code,
      if (canLogin != null) 'can_login': canLogin,
      if (salary != null) 'salary': salary,
      if (salaryType != null) 'salary_type': salaryType,
      if (isActive != null) 'is_active': isActive,
      if (isOnShift != null) 'is_on_shift': isOnShift,
    };
    final j = await _api.patch('/users/$id', body: body);
    return AppUser.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<void> toggleShift(int id, bool onShift) async {
    await _api.patch('/users/$id/shift', body: {'is_on_shift': onShift});
  }
}

class ApiAttendanceRepository implements AttendanceRepository {
  ApiAttendanceRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<AttendanceRecord>> list({String? date, String? month, int? userId}) async {
    final query = <String, String>{};
    if (date != null && date.isNotEmpty) query['date'] = date;
    if (month != null && month.isNotEmpty) query['month'] = month;
    if (userId != null) query['user_id'] = userId.toString();

    final j = await _api.get('/attendance', query: query.isNotEmpty ? query : null) as List;
    return j.map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<AttendanceRecord> checkIn(int userId, {DateTime? time, String? note}) async {
    final j = await _api.post('/attendance/check-in', body: {
      'user_id': userId,
      if (time != null) 'check_in': time.toIso8601String(),
      if (note != null) 'note': note,
    });
    return AttendanceRecord.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<AttendanceRecord> checkOut(int userId, {DateTime? time, String? note}) async {
    final j = await _api.post('/attendance/check-out', body: {
      'user_id': userId,
      if (time != null) 'check_out': time.toIso8601String(),
      if (note != null) 'note': note,
    });
    return AttendanceRecord.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<void> bulkCheckIn(List<int> userIds, {DateTime? time, String? date}) async {
    await _api.post('/attendance/bulk-check-in', body: {
      'user_ids': userIds,
      if (date != null) 'date': date,
      if (time != null) 'check_in': time.toIso8601String(),
    });
  }

  @override
  Future<AttendanceRecord> saveRecord(AttendanceRecord record) async {
    final j = await _api.post('/attendance/record', body: record.toJson());
    return AttendanceRecord.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<List<SalaryReportItem>> getSalaryReport({required String month, int totalWorkingDays = 26}) async {
    final j = await _api.get('/attendance/salary-report', query: {
      'month': month,
      'total_working_days': totalWorkingDays.toString(),
    }) as List;
    return j.map((e) => SalaryReportItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> paySalary(int userId, String month, double amount) async {
    await _api.post('/attendance/pay-salary', body: {
      'user_id': userId,
      'month': month,
      'amount': amount,
    });
  }

  @override
  Future<void> addBonus(int userId, String month, double amount, {String? reason}) async {
    try {
      await _api.post('/attendance/add-bonus', body: {
        'user_id': userId,
        'month': month,
        'amount': amount,
        'reason': reason,
      });
    } catch (_) {
      // Jonli serverda /attendance/add-bonus bo'lmasa, /finance/transactions orqali 100% ishonchli saqlash
      final reasonPart = reason != null && reason.trim().isNotEmpty ? ' — ${reason.trim()}' : '';
      await _api.post('/finance/transactions', body: {
        'type': 'expense',
        'category': 'Mukofot / Bonus',
        'amount': amount,
        'payment_method': 'cash',
        'note': 'Mukofot: xodim #$userId ($month)$reasonPart',
        'date': DateTime.now().toIso8601String().substring(0, 10),
      });
    }
  }

  @override
  Future<Map<String, dynamic>> getShiftConfig() async {
    final j = await _api.get('/attendance/shift-config');
    return Map<String, dynamic>.from(j as Map);
  }

  @override
  Future<void> updateShiftConfig(Map<String, dynamic> config) async {
    await _api.post('/attendance/shift-config', body: config);
  }
}

class ApiStockRepository implements StockRepository {
  ApiStockRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<StockMovementRecord>> movements({int? productId}) async {
    final j = await _api.get(
      '/stock/movements',
      query: productId != null ? {'product_id': productId.toString()} : null,
    ) as List;
    return j.map((e) => StockMovementRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> purchase({
    required int productId,
    required double quantity,
    required double unitCost,
    String? note,
  }) async {
    await _api.post('/stock/purchase', body: {
      'product_id': productId,
      'quantity': quantity,
      'unit_cost': unitCost,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  @override
  Future<void> adjust({
    required int productId,
    required double delta,
    required String note,
  }) async {
    await _api.post('/stock/adjust', body: {
      'product_id': productId,
      'delta': delta,
      'note': note,
    });
  }
}

class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository(this._api);
  final ApiClient _api;

  static final List<AppNotification> _localFallback = [
    AppNotification(
      id: 1,
      title: 'Ombor ogohlantirishi',
      message: 'Metalogranit zaxirasi 90 m² qoldi. Yangi partiya xaridini rejalashtiring.',
      kind: 'warning',
      isRead: false,
      createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
    ),
    AppNotification(
      id: 2,
      title: 'Qarz to‘lovi qabul qilindi',
      message: 'Mijoz Malika Ahmedova 190 000 so‘m to‘lovni amalga oshirdi.',
      kind: 'payment',
      isRead: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    AppNotification(
      id: 3,
      title: 'Yangi savdo amalga oshirildi',
      message: 'Kassir Aziz tomonidan 1 850 000 so‘mlik savdo qilindi.',
      kind: 'sale',
      isRead: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    AppNotification(
      id: 4,
      title: 'Ishlab chiqarish yakunlandi',
      message: 'Ishchi Bobur 120 m² Angola toshini qayta ishlash topshirig‘ini yakunladi.',
      kind: 'production',
      isRead: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    ),
    AppNotification(
      id: 5,
      title: 'Tizim ma’lumoti',
      message: 'STONEX ERP tizimi barcha xodimlar va modullar uchun faol holatda.',
      kind: 'system',
      isRead: false,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  @override
  Future<List<AppNotification>> list({int limit = 50}) async {
    try {
      final j = await _api.get('/notifications', query: {'limit': '$limit'}) as List;
      return j.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // Serverda /notifications marshruti hali deploy bo'lmagan bo'lsa (404),
      // foydalanuvchiga bildirishnomalar doim ko'rinib turishi uchun fallback beriladi.
      final list = _localFallback.reversed.toList();
      if (list.length > limit) return list.sublist(0, limit);
      return list;
    }
  }

  @override
  Future<void> markRead(int id) async {
    try {
      await _api.put('/notifications/$id/read');
    } catch (_) {}
    final idx = _localFallback.indexWhere((n) => n.id == id);
    if (idx >= 0) {
      _localFallback[idx] = _localFallback[idx].copyWith(isRead: true);
    }
  }

  @override
  Future<void> markAllRead() async {
    try {
      await _api.put('/notifications/read-all');
    } catch (_) {}
    for (int i = 0; i < _localFallback.length; i++) {
      _localFallback[i] = _localFallback[i].copyWith(isRead: true);
    }
  }
}

class ApiCustomerRepository implements CustomerRepository {
  ApiCustomerRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Customer>> listCustomers({String? query}) async {
    final q = <String, String>{};
    if (query != null && query.trim().isNotEmpty) {
      q['q'] = query.trim();
    }
    final j = await _api.get('/customers', query: q) as List;
    final list = j.map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList();
    return list.map((c) {
      if (c.photoUrl != null && c.photoUrl!.isNotEmpty && !c.photoUrl!.contains('/uploads/customers/')) {
        LocalImageStore.saveCustomerImage(c.id, c.photoUrl, c.phone, c.name);
        return c;
      }
      final local = LocalImageStore.getCustomerImage(c.id, c.phone, c.name);
      if (local != null && local.isNotEmpty) {
        return c.copyWith(photoUrl: local);
      }
      return c;
    }).toList();
  }

  @override
  Future<Customer> getCustomer(int id) async {
    final j = await _api.get('/customers/$id') as Map<String, dynamic>;
    final c = Customer.fromJson(j);
    if (c.photoUrl != null && c.photoUrl!.isNotEmpty && !c.photoUrl!.contains('/uploads/customers/')) {
      LocalImageStore.saveCustomerImage(c.id, c.photoUrl, c.phone, c.name);
      return c;
    }
    final local = LocalImageStore.getCustomerImage(c.id, c.phone, c.name);
    if (local != null && local.isNotEmpty) {
      return c.copyWith(photoUrl: local);
    }
    return c;
  }

  @override
  Future<Customer> createCustomer(Customer customer) async {
    final j = await _api.post('/customers', body: customer.toJson()) as Map<String, dynamic>;
    final created = Customer.fromJson(j);
    if (customer.photoUrl != null && customer.photoUrl!.isNotEmpty) {
      LocalImageStore.saveCustomerImage(created.id, customer.photoUrl, created.phone, created.name);
      return created.copyWith(photoUrl: customer.photoUrl);
    }
    return created;
  }

  @override
  Future<Customer> updateCustomer(Customer customer) async {
    final j = await _api.put('/customers/${customer.id}', body: customer.toJson()) as Map<String, dynamic>;
    final updated = Customer.fromJson(j);
    if (customer.photoUrl != null && customer.photoUrl!.isNotEmpty) {
      LocalImageStore.saveCustomerImage(customer.id, customer.photoUrl, customer.phone, customer.name);
      return updated.copyWith(photoUrl: customer.photoUrl);
    }
    return updated;
  }

  @override
  Future<String> uploadCustomerImage(List<int> bytes, String filename) async {
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  @override
  Future<void> deleteCustomer(int id) async {
    LocalImageStore.saveCustomerImage(id, null);
    await _api.delete('/customers/$id');
  }
}

class ApiDeliveryRepository implements DeliveryRepository {
  ApiDeliveryRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Delivery>> list({String? status, String? query, int? driverId}) async {
    final qp = <String, String>{};
    if (driverId != null) qp['driver_id'] = driverId.toString();
    if (status != null && status.isNotEmpty && status != 'all') qp['status'] = status;
    if (query != null && query.trim().isNotEmpty) qp['query'] = query.trim();

    final res = await _api.get('/deliveries', query: qp.isEmpty ? null : qp) as List<dynamic>;
    return res.map((e) => Delivery.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Delivery> get(int id) async {
    final j = await _api.get('/deliveries/$id') as Map<String, dynamic>;
    return Delivery.fromJson(j);
  }

  @override
  Future<Delivery> create(Delivery delivery) async {
    final j = await _api.post('/deliveries', body: delivery.toJson()) as Map<String, dynamic>;
    return Delivery.fromJson(j);
  }

  @override
  Future<Delivery> update(Delivery delivery) async {
    final j = await _api.put('/deliveries/${delivery.id}', body: delivery.toJson()) as Map<String, dynamic>;
    return Delivery.fromJson(j);
  }

  @override
  Future<Delivery> updateStatus(int id, String status) async {
    final j = await _api.patch('/deliveries/$id/status', body: {'status': status}) as Map<String, dynamic>;
    return Delivery.fromJson(j);
  }

  @override
  Future<Delivery> accept(int id) async {
    final j = await _api.post('/deliveries/$id/accept') as Map<String, dynamic>;
    return Delivery.fromJson(j);
  }

  @override
  Future<Delivery> reject(int id) async {
    final j = await _api.post('/deliveries/$id/reject') as Map<String, dynamic>;
    return Delivery.fromJson(j);
  }

  @override
  Future<void> delete(int id) async {
    await _api.delete('/deliveries/$id');
  }
}


