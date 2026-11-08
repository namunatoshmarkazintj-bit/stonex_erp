import '../domain/models.dart';

/// UI faqat shu interfeyslarga murojaat qiladi. Mock yoki API ekanini bilmaydi.
abstract class AuthRepository {
  Future<AppUser> login(String username, String password, [Role? role]);
  Future<AppUser?> tryRestoreSession();
  Future<void> logout();
}

abstract class ProductRepository {
  Future<List<Product>> list({String? query});
  Future<Product?> findByCode(String code);
  Future<Product> create(Product p, {double initialStock = 0});
  Future<Product> update(Product p);
  Future<void> deactivate(int id);
  Future<String> uploadImage(List<int> bytes, String filename);
  Future<Product> uploadProductImage(int productId, List<int> bytes, String filename);
}

abstract class SalesRepository {
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
  });
  Future<List<SaleResult>> listSales({int limit = 50, String? status, int? customerId});
  Future<List<SaleResult>> listDebts();
  Future<SaleResult> payDebt(int saleId, double amount, {String method = 'cash'});
  Future<SaleResult> fulfillOrder(
    int saleId, {
    String? receivedByName,
    String? receivedByPhone,
    String? deliveryType,
    String? receiverDocOrCar,
    String? note,
    double? payAmount,
    String? payMethod,
  });
  Future<SaleResult> cancelOrder(int saleId);
  Future<SaleResult> returnSale(int saleId, {required List<({int productId, double quantity})> items, String? reason});
}

abstract class CustomerRepository {
  Future<List<Customer>> listCustomers({String? query});
  Future<Customer> getCustomer(int id);
  Future<Customer> createCustomer(Customer customer);
  Future<Customer> updateCustomer(Customer customer);
  Future<String> uploadCustomerImage(List<int> bytes, String filename);
  Future<void> deleteCustomer(int id);
}

abstract class FinanceRepository {
  Future<FinanceSummary> summary();
  Future<List<FinanceTransaction>> listTransactions({
    String? type,
    String? category,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 300,
  });
  Future<FinanceTransaction> addTransaction(FinanceTransaction tx);
  Future<MonthlyComparison> monthlyComparison({
    DateTime? curDateFrom,
    DateTime? curDateTo,
    DateTime? prevDateFrom,
    DateTime? prevDateTo,
    String? curLabel,
    String? prevLabel,
  });
  Future<List<RevenueBreakdownItem>> revenueBreakdown({DateTime? dateFrom, DateTime? dateTo});
  Future<String> exportCsv({DateTime? dateFrom, DateTime? dateTo});
}

abstract class ProductionRepository {
  Future<List<ProductionTask>> list();
  Future<List<AppUser>> workers();
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
  });
  Future<void> report(int taskId, double producedQty, {double? wasteQty, String? note});
  Future<void> approve(int taskId);
  Future<void> reject(int taskId, {String? reason});
}

abstract class UserRepository {
  Future<List<AppUser>> list({String? role});
  Future<AppUser> create({
    String? username,
    required String fullName,
    String? password,
    required Role role,
    bool canLogin = true,
    double salary = 0,
    String salaryType = 'monthly',
  });
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
  });
  Future<void> toggleShift(int id, bool onShift);
}

abstract class AttendanceRepository {
  Future<List<AttendanceRecord>> list({String? date, String? month, int? userId});
  Future<AttendanceRecord> checkIn(int userId, {DateTime? time, String? note});
  Future<AttendanceRecord> checkOut(int userId, {DateTime? time, String? note});
  Future<void> bulkCheckIn(List<int> userIds, {DateTime? time, String? date});
  Future<AttendanceRecord> saveRecord(AttendanceRecord record);
  Future<List<SalaryReportItem>> getSalaryReport({required String month, int totalWorkingDays = 26});
  Future<void> paySalary(int userId, String month, double amount);
  Future<void> addBonus(int userId, String month, double amount, {String? reason});
  Future<Map<String, dynamic>> getShiftConfig();
  Future<void> updateShiftConfig(Map<String, dynamic> config);
}

abstract class StockRepository {
  Future<List<StockMovementRecord>> movements({int? productId});
  Future<void> purchase({
    required int productId,
    required double quantity,
    required double unitCost,
    String? note,
  });
  Future<void> adjust({
    required int productId,
    required double delta,
    required String note,
  });
}

abstract class NotificationRepository {
  Future<List<AppNotification>> list({int limit = 50});
  Future<void> markRead(int id);
  Future<void> markAllRead();
}

abstract class DeliveryRepository {
  Future<List<Delivery>> list({String? status, String? query, int? driverId});
  Future<Delivery> get(int id);
  Future<Delivery> create(Delivery delivery);
  Future<Delivery> update(Delivery delivery);
  Future<Delivery> updateStatus(int id, String status);
  Future<Delivery> accept(int id);
  Future<Delivery> reject(int id);
  Future<void> delete(int id);
}

class AppRepositories {
  final AuthRepository auth;
  final ProductRepository products;
  final SalesRepository sales;
  final FinanceRepository finance;
  final ProductionRepository production;
  final UserRepository users;
  final StockRepository stock;
  final NotificationRepository notifications;
  final CustomerRepository customers;
  final AttendanceRepository attendance;
  final DeliveryRepository deliveries;

  const AppRepositories({
    required this.auth,
    required this.products,
    required this.sales,
    required this.finance,
    required this.production,
    required this.users,
    required this.stock,
    required this.notifications,
    required this.customers,
    required this.attendance,
    required this.deliveries,
  });
}

