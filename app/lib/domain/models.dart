double parseNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ??
      0; // backend Decimal'ni satr sifatida yuboradi
}

double? parseNumOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

enum Role {
  admin('admin', 'Admin'),
  kassir('kassir', 'Kassir'),
  ishBoshqaruvchi('ish_boshqaruvchi', 'Ish boshqaruvchi'),
  ishchi('ishchi', 'Ishchi'),
  haydovchi('haydovchi', 'Haydovchi');

  const Role(this.code, this.label);
  final String code;
  final String label;

  static Role fromCode(String c) =>
      Role.values.firstWhere((r) => r.code == c, orElse: () => Role.ishchi);
}

class AppUser {
  final int id;
  final String username;
  final String fullName;
  final Role role;
  final double salary;
  final String salaryType; // 'monthly', 'daily', 'hourly'
  final bool isActive;
  final bool canLogin;
  final bool isOnShift;

  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.salary = 0,
    this.salaryType = 'monthly',
    this.isActive = true,
    this.canLogin = true,
    this.isOnShift = true,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) {
    final rawCanLogin = j['can_login'];
    final uName = (j['username'] ?? '').toString();
    final bool canLogin = rawCanLogin is bool
        ? rawCanLogin
        : (uName.isNotEmpty && !uName.startsWith('worker_'));

    return AppUser(
      id: (j['id'] as num?)?.toInt() ?? 0,
      username: uName,
      fullName: (j['full_name'] ?? j['username'] ?? '').toString(),
      role: Role.fromCode((j['role'] ?? 'ishchi').toString()),
      salary: parseNum(j['salary']),
      salaryType: (j['salary_type'] ?? 'monthly').toString(),
      isActive: (j['is_active'] ?? true) as bool,
      canLogin: canLogin,
      isOnShift: (j['is_on_shift'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'role': role.code,
        'salary': salary,
        'salary_type': salaryType,
        'is_active': isActive,
        'can_login': canLogin,
        'is_on_shift': isOnShift,
      };

  AppUser copyWith({
    int? id,
    String? username,
    String? fullName,
    Role? role,
    double? salary,
    String? salaryType,
    bool? isActive,
    bool? canLogin,
    bool? isOnShift,
  }) =>
      AppUser(
        id: id ?? this.id,
        username: username ?? this.username,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
        salary: salary ?? this.salary,
        salaryType: salaryType ?? this.salaryType,
        isActive: isActive ?? this.isActive,
        canLogin: canLogin ?? this.canLogin,
        isOnShift: isOnShift ?? this.isOnShift,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUser && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AttendanceRecord {
  final int id;
  final int userId;
  final String? userName;
  final String date; // YYYY-MM-DD
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double workedHours;
  final String status; // 'present', 'late', 'absent', 'half_day'
  final String? note;

  const AttendanceRecord({
    required this.id,
    required this.userId,
    this.userName,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.workedHours = 0,
    this.status = 'present',
    this.note,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: (j['id'] as num?)?.toInt() ?? 0,
        userId: (j['user_id'] as num?)?.toInt() ?? 0,
        userName: j['user_name']?.toString(),
        date: (j['date'] ?? '').toString(),
        checkIn: j['check_in'] != null
            ? DateTime.tryParse(j['check_in'].toString())
            : null,
        checkOut: j['check_out'] != null
            ? DateTime.tryParse(j['check_out'].toString())
            : null,
        workedHours: parseNum(j['worked_hours']),
        status: (j['status'] ?? 'present').toString(),
        note: j['note']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'user_name': userName,
        'date': date,
        'check_in': checkIn?.toIso8601String(),
        'check_out': checkOut?.toIso8601String(),
        'worked_hours': workedHours,
        'status': status,
        'note': note,
      };

  AttendanceRecord copyWith({
    int? id,
    int? userId,
    String? userName,
    String? date,
    DateTime? checkIn,
    DateTime? checkOut,
    double? workedHours,
    String? status,
    String? note,
  }) =>
      AttendanceRecord(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        date: date ?? this.date,
        checkIn: checkIn ?? this.checkIn,
        checkOut: checkOut ?? this.checkOut,
        workedHours: workedHours ?? this.workedHours,
        status: status ?? this.status,
        note: note ?? this.note,
      );
}

class SalaryReportItem {
  final int userId;
  final String fullName;
  final String role;
  final double baseSalary;
  final String salaryType;
  final int daysWorked;
  final double hoursWorked;
  final int daysLate;
  final double calculatedSalary;
  double bonus;
  double deduction;
  final double netSalary;
  final double paidAmount;
  final double remainingSalary;
  bool isPaid;

  SalaryReportItem({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.baseSalary,
    this.salaryType = 'monthly',
    this.daysWorked = 0,
    this.hoursWorked = 0,
    this.daysLate = 0,
    required this.calculatedSalary,
    this.bonus = 0,
    this.deduction = 0,
    required this.netSalary,
    this.paidAmount = 0,
    this.remainingSalary = 0,
    this.isPaid = false,
  });

  factory SalaryReportItem.fromJson(Map<String, dynamic> j) => SalaryReportItem(
        userId: (j['user_id'] as num?)?.toInt() ?? 0,
        fullName: (j['full_name'] ?? '').toString(),
        role: (j['role'] ?? 'ishchi').toString(),
        baseSalary: parseNum(j['base_salary']),
        salaryType: (j['salary_type'] ?? 'monthly').toString(),
        daysWorked: (j['days_worked'] as num?)?.toInt() ?? 0,
        hoursWorked: parseNum(j['hours_worked']),
        daysLate: (j['days_late'] as num?)?.toInt() ?? 0,
        calculatedSalary: parseNum(j['calculated_salary']),
        bonus: parseNum(j['bonus']),
        deduction: parseNum(j['deduction']),
        netSalary: parseNum(j['net_salary']),
        paidAmount: parseNum(j['paid_amount']),
        remainingSalary: parseNum(j['remaining_salary']),
        isPaid: (j['is_paid'] ?? false) as bool,
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'full_name': fullName,
        'role': role,
        'base_salary': baseSalary,
        'salary_type': salaryType,
        'days_worked': daysWorked,
        'hours_worked': hoursWorked,
        'days_late': daysLate,
        'calculated_salary': calculatedSalary,
        'bonus': bonus,
        'deduction': deduction,
        'net_salary': netSalary,
        'paid_amount': paidAmount,
        'remaining_salary': remainingSalary,
        'is_paid': isPaid,
      };
}

const List<String> standardProductCategories = [
  'Granit',
  'Kerama granit',
  'Kafel',
  'Marmar',
  'Tayyor mahsulot',
  'Xomashyo',
  'Qo‘shimcha',
];

String? _cleanColor(String? c) {
  if (c == null || c.trim().isEmpty) return null;
  final t = c.trim();
  if (RegExp(r'sort|\d+\s*[/x*X×]\s*\d+', caseSensitive: false).hasMatch(t)) {
    return null;
  }
  return t;
}

class Product {
  final int id;
  final String name;
  final String?
      category; // Standart kategoriyalar: Granit, Kerama granit, Kafel, Marmar, Tayyor mahsulot, Xomashyo, Qo‘shimcha
  final String sku;
  final String qrCode;
  final String unit; // m2, dona, kg, m
  final double? donaM2; // faqat toshlar uchun (0.25)
  final double? thickness; // tosh qalinligi (sm, masalan: 2.0 sm)
  final double?
      tileLength; // kafel/keramogranit bo'yi (sm, masalan: 60 yoki 120 sm)
  final double? tileWidth; // kafel/keramogranit eni (sm, masalan: 60 sm)
  final int? boxPieces; // 1 pachkadagi donalar soni (masalan: 4 dona)
  final double? boxM2; // 1 pachka kvadrati (m2)
  final String? sort; // 1, 1.5, 2, 3, oliy
  final bool hasSorts; // 1, 1.5, 2 sortlari mavjudligi (kassada tanlanadi)
  final String?
      color; // rangi (masalan: Ko'k, Oq, Qora yoki vergul bilan ajratilgan)
  final double? priceSort1; // 1-sort narxi
  final double? priceSort1_5; // 1.5-sort narxi
  final double? priceSort2; // 2-sort narxi
  final double price; // bazaviy birlik narxi
  final double costPrice;
  final double stock;
  final double reservedQty; // buyurtmalar uchun band qilingan zaxira
  final int? rawMaterialId; // xomashyo (blok yoki plita)
  final double? wasteRatio; // sarf/chiqindi koeffitsiyenti (masalan: 1.15)
  final double? cuttingRate; // ustaga 1 m2 ishbay haq
  final double
      minStock; // kamida qancha bo'lishi kerak (ogohlantirish chegarasi)
  final String? imageUrl;

  const Product({
    required this.id,
    required this.name,
    this.category,
    this.sku = '',
    this.qrCode = '',
    required this.unit,
    this.donaM2,
    this.thickness,
    this.tileLength,
    this.tileWidth,
    this.boxPieces,
    this.boxM2,
    this.sort,
    this.hasSorts = false,
    this.color,
    this.priceSort1,
    this.priceSort1_5,
    this.priceSort2,
    required this.price,
    this.costPrice = 0,
    this.stock = 0,
    this.reservedQty = 0,
    this.rawMaterialId,
    this.wasteRatio,
    this.cuttingRate,
    this.minStock = 15,
    this.imageUrl,
  });

  bool get hasDona => donaM2 != null && donaM2! > 0;
  bool get isTile =>
      category != null &&
      (category!.toLowerCase() == 'kafel' ||
          category!.toLowerCase() == 'kerama granit' ||
          category!.toLowerCase().contains('granit') ||
          category!.toLowerCase().contains('marmar'));
  bool get hasPachka =>
      unit == 'm2' ||
      unit == 'm²' ||
      (effectiveBoxM2 != null && effectiveBoxM2! > 0);
  double? get effectiveBoxM2 {
    if (boxM2 != null && boxM2! > 0) return boxM2;
    if (donaM2 != null && boxPieces != null && boxPieces! > 0) {
      return donaM2! * boxPieces!;
    }
    if (tileLength != null &&
        tileWidth != null &&
        tileLength! > 0 &&
        tileWidth! > 0) {
      final single = (tileLength! * tileWidth!) / 10000.0;
      final pcs = (boxPieces != null && boxPieces! > 0)
          ? boxPieces!
          : (tileLength! >= 120 || tileWidth! >= 120 ? 2 : 4);
      return single * pcs;
    }
    if (donaM2 != null && donaM2! > 0) {
      final pcs = (boxPieces != null && boxPieces! > 0) ? boxPieces! : 2;
      return donaM2! * pcs;
    }
    // Avtomatik tovar nomi yoki sortidan razmerni aniqlash (masalan: 120/60, 60x60, 80x80, 30x90)
    final match =
        RegExp(r'(\d{2,3})\s*[/x*X×]\s*(\d{2,3})').firstMatch('$name $sort');
    if (match != null) {
      final l = double.tryParse(match.group(1)!);
      final w = double.tryParse(match.group(2)!);
      if (l != null && w != null && l > 0 && w > 0) {
        final single = (l * w) / 10000.0;
        final pcs = (boxPieces != null && boxPieces! > 0)
            ? boxPieces!
            : (l >= 120 || w >= 120 ? 2 : 4);
        return single * pcs;
      }
    }
    if (unit == 'm2' || unit == 'm²') {
      return 1.44;
    }
    return null;
  }

  List<String> get availableColors {
    if (color == null || color!.trim().isEmpty) return const [];
    final c = color!.trim();
    if (RegExp(r'sort|\d+\s*[/x*X×]\s*\d+', caseSensitive: false).hasMatch(c)) {
      return const [];
    }
    return c
        .split(RegExp(r'[,•|]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !RegExp(r'^\d+$').hasMatch(s))
        .toList();
  }

  bool get hasMultipleColors => availableColors.length > 1;

  /// Xizmatlar (kesish, silliqlash, faska, chizish) mahsulotlar katalogiga aralashmasligi uchun
  bool get isService => category?.trim().toLowerCase() == 'xizmat';

  double priceForSort(String? s) {
    if (s == '1' && priceSort1 != null && priceSort1! > 0) return priceSort1!;
    if (s == '1.5' && priceSort1_5 != null && priceSort1_5! > 0)
      return priceSort1_5!;
    if (s == '2' && priceSort2 != null && priceSort2! > 0) return priceSort2!;
    return price;
  }

  String get sortLabel {
    if (sort != null && sort!.isNotEmpty) {
      final s = sort!.trim();
      if (s.toLowerCase() == 'oliy') return 'Oliy sort';
      if (RegExp(r'^(1|1\.5|2|3)$').hasMatch(s)) return '$s-sort';
      return s;
    }
    if (color != null && color!.isNotEmpty) {
      return color!.trim();
    }
    final match =
        RegExp(r'\((1|1\.5|2|3|Oliy|oliy)[ -]sort\)', caseSensitive: false)
            .firstMatch(name);
    if (match != null) {
      final s = match.group(1)!;
      return s.toLowerCase() == 'oliy' ? 'Oliy sort' : '$s-sort';
    }
    if (hasSorts) {
      return '1 • 1.5 • 2 sort';
    }
    return '';
  }

  Product copyWith({
    int? id,
    String? name,
    String? category,
    String? sku,
    String? qrCode,
    String? unit,
    double? donaM2,
    double? thickness,
    double? tileLength,
    double? tileWidth,
    int? boxPieces,
    double? boxM2,
    String? sort,
    bool? hasSorts,
    String? color,
    double? priceSort1,
    double? priceSort1_5,
    double? priceSort2,
    double? price,
    double? costPrice,
    double? stock,
    double? minStock,
    String? imageUrl,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        sku: sku ?? this.sku,
        qrCode: qrCode ?? this.qrCode,
        unit: unit ?? this.unit,
        donaM2: donaM2 ?? this.donaM2,
        thickness: thickness ?? this.thickness,
        tileLength: tileLength ?? this.tileLength,
        tileWidth: tileWidth ?? this.tileWidth,
        boxPieces: boxPieces ?? this.boxPieces,
        boxM2: boxM2 ?? this.boxM2,
        sort: sort ?? this.sort,
        hasSorts: hasSorts ?? this.hasSorts,
        color: color ?? this.color,
        priceSort1: priceSort1 ?? this.priceSort1,
        priceSort1_5: priceSort1_5 ?? this.priceSort1_5,
        priceSort2: priceSort2 ?? this.priceSort2,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        stock: stock ?? this.stock,
        minStock: minStock ?? this.minStock,
        imageUrl: imageUrl ?? this.imageUrl,
      );

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        category: j['category']?.toString(),
        sku: (j['sku'] ?? '').toString(),
        qrCode: (j['qr_code'] ?? '').toString(),
        unit: (j['unit'] ?? 'm²').toString(),
        donaM2: j['dona_m2'] == null ? null : parseNum(j['dona_m2']),
        thickness: j['thickness'] == null ? null : parseNum(j['thickness']),
        tileLength:
            j['tile_length'] == null ? null : parseNum(j['tile_length']),
        tileWidth: j['tile_width'] == null ? null : parseNum(j['tile_width']),
        boxPieces: (j['box_pieces'] as num?)?.toInt(),
        boxM2: j['box_m2'] == null ? null : parseNum(j['box_m2']),
        sort: j['sort']?.toString(),
        hasSorts: j['has_sorts'] == true,
        color: _cleanColor(j['color']?.toString()),
        priceSort1:
            j['price_sort1'] == null ? null : parseNum(j['price_sort1']),
        priceSort1_5:
            j['price_sort1_5'] == null ? null : parseNum(j['price_sort1_5']),
        priceSort2:
            j['price_sort2'] == null ? null : parseNum(j['price_sort2']),
        price: parseNum(j['price']),
        costPrice: parseNum(j['cost_price']),
        stock: parseNum(j['stock']),
        reservedQty: parseNum(j['reserved_qty']),
        rawMaterialId: (j['raw_material_id'] as num?)?.toInt(),
        wasteRatio:
            j['waste_ratio'] == null ? null : parseNum(j['waste_ratio']),
        cuttingRate:
            j['cutting_rate'] == null ? null : parseNum(j['cutting_rate']),
        minStock: j['min_stock'] == null ? 15.0 : parseNum(j['min_stock']),
        imageUrl:
            (j['image_url'] != null && j['image_url'].toString().isNotEmpty)
                ? j['image_url'].toString()
                : null,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson({double initialStock = 0}) => {
        'name': name,
        'category': category,
        'sku': sku.isEmpty ? null : sku,
        'qr_code': qrCode.isEmpty ? null : qrCode,
        'unit': unit,
        'dona_m2': donaM2,
        'thickness': thickness,
        'tile_length': tileLength,
        'tile_width': tileWidth,
        'box_pieces': boxPieces,
        'box_m2': boxM2,
        'sort': sort,
        'has_sorts': hasSorts,
        'color': color,
        'price_sort1': priceSort1,
        'price_sort1_5': priceSort1_5,
        'price_sort2': priceSort2,
        'price': price,
        'cost_price': costPrice,
        'stock': stock,
        'min_stock': minStock,
        'initial_stock': initialStock,
        if (rawMaterialId != null) 'raw_material_id': rawMaterialId,
        if (wasteRatio != null) 'waste_ratio': wasteRatio,
        if (cuttingRate != null) 'cutting_rate': cuttingRate,
        'image_url': imageUrl,
      };
}

class CartLine {
  final Product product;
  double quantity;
  bool inDona;
  bool inPachka; // Pachkada sotish (Kafel / Kerama granit)
  String? sort; // '1', '1.5', '2'
  String? color; // rangi (masalan: Ko'k, Oq, Qora)
  double? cutLength; // metrda
  double? cutWidth; // metrda
  double? cutThickness; // santimetrda (sm)
  int? cutPieces; // donasi
  String? cutSpec; // masalan: '1.2 × 0.6 m (2 sm, 5 dona)'
  double? unitPriceOverride;

  CartLine(
    this.product, {
    this.quantity = 1,
    this.inDona = false,
    this.inPachka = false,
    this.sort,
    this.color,
    this.cutLength,
    this.cutWidth,
    this.cutThickness,
    this.cutPieces,
    this.cutSpec,
    this.unitPriceOverride,
  }) {
    if (product.hasSorts && sort == null) {
      sort = '1.5';
    }
    if (color == null && product.availableColors.isNotEmpty) {
      color = product.availableColors.first;
    } else if (color == null &&
        product.color != null &&
        product.color!.isNotEmpty) {
      color = product.color;
    }
  }

  double get unitPrice => unitPriceOverride ?? product.priceForSort(sort);
  double get baseQty {
    if (inPachka && product.effectiveBoxM2 != null) {
      return quantity * product.effectiveBoxM2!;
    }
    if (inDona && product.hasDona) {
      return quantity * product.donaM2!;
    }
    return quantity;
  }

  double get lineTotal => baseQty * unitPrice;

  String get displayName {
    final col = (color != null &&
            color!.isNotEmpty &&
            !product.name.toLowerCase().contains(color!.toLowerCase()))
        ? ' ($color)'
        : '';
    final s = (sort != null && sort!.isNotEmpty) ? ' [$sort-sort]' : '';
    final c = (cutSpec != null && cutSpec!.isNotEmpty) ? ' [$cutSpec]' : '';
    return '${product.name}$col$s$c';
  }

  CartLine copy() => CartLine(
        product,
        quantity: quantity,
        inDona: inDona,
        inPachka: inPachka,
        sort: sort,
        color: color,
        cutLength: cutLength,
        cutWidth: cutWidth,
        cutThickness: cutThickness,
        cutPieces: cutPieces,
        cutSpec: cutSpec,
        unitPriceOverride: unitPriceOverride,
      );
}

class HeldCart {
  final String id;
  final String label;
  final DateTime createdAt;
  final List<CartLine> lines;

  HeldCart({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.lines,
  });

  double get total => lines.fold(0, (a, l) => a + l.lineTotal);
  int get count => lines.length;
}

class SaleItemRecord {
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  const SaleItemRecord({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  bool get isCut =>
      (productName.contains('[') &&
          (productName.contains(']') || productName.contains('dona)'))) ||
      productName.toLowerCase().contains('kesil') ||
      productName.toLowerCase().contains('maxsus razmer');

  factory SaleItemRecord.fromJson(Map<String, dynamic> j) => SaleItemRecord(
        productId: (j['product_id'] as num?)?.toInt() ?? 0,
        productName: (j['product_name'] ?? '').toString(),
        quantity: parseNum(j['quantity']),
        unitPrice: parseNum(j['unit_price']),
        lineTotal: parseNum(j['line_total']),
      );
}

class Customer {
  final int id;
  final String name;
  final String? phone;
  final String? passport;
  final String? photoUrl;
  final DateTime? createdAt;
  final double totalSpent;
  final double totalDebt;
  final int salesCount;

  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.passport,
    this.photoUrl,
    this.createdAt,
    this.totalSpent = 0,
    this.totalDebt = 0,
    this.salesCount = 0,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?) ?? '',
        phone: j['phone'] as String?,
        passport: j['passport'] as String?,
        photoUrl: j['photo_url'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString())
            : null,
        totalSpent: parseNum(j['total_spent']),
        totalDebt: parseNum(j['total_debt']),
        salesCount: (j['sales_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (passport != null && passport!.isNotEmpty) 'passport': passport,
        if (photoUrl != null && photoUrl!.isNotEmpty) 'photo_url': photoUrl,
      };

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? passport,
    String? photoUrl,
    DateTime? createdAt,
    double? totalSpent,
    double? totalDebt,
    int? salesCount,
  }) =>
      Customer(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        passport: passport ?? this.passport,
        photoUrl: photoUrl ?? this.photoUrl,
        createdAt: createdAt ?? this.createdAt,
        totalSpent: totalSpent ?? this.totalSpent,
        totalDebt: totalDebt ?? this.totalDebt,
        salesCount: salesCount ?? this.salesCount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Customer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class SaleResult {
  final int id;
  final double total;
  final double paid;
  final double debt;
  final double? currencyRate;
  final double? paidUzs;
  final double? paidUsd;
  final String status; // 'completed' | 'order' | 'cancelled'
  final String? note;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerPassport;
  final String? customerPhotoUrl;
  final int? cashierId;
  final String? cashierName;
  final String? paymentMethod;
  final DateTime? createdAt;
  final String? receivedByName;
  final String? receivedByPhone;
  final String? deliveryType; // 'pickup' | 'delivery'
  final String? receiverDocOrCar;
  final String? fulfilledByName;
  final DateTime? fulfilledAt;
  final List<SaleItemRecord> items;

  bool get isOrder => status == 'order';

  const SaleResult({
    required this.id,
    required this.total,
    required this.paid,
    required this.debt,
    this.currencyRate,
    this.paidUzs,
    this.paidUsd,
    this.status = 'completed',
    this.note,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerPassport,
    this.customerPhotoUrl,
    this.cashierId,
    this.cashierName,
    this.paymentMethod,
    this.createdAt,
    this.receivedByName,
    this.receivedByPhone,
    this.deliveryType,
    this.receiverDocOrCar,
    this.fulfilledByName,
    this.fulfilledAt,
    this.items = const [],
  });

  SaleResult copyWith({
    int? id,
    double? total,
    double? paid,
    double? debt,
    double? currencyRate,
    double? paidUzs,
    double? paidUsd,
    String? status,
    String? note,
    int? customerId,
    String? customerName,
    String? customerPhone,
    String? customerPassport,
    String? customerPhotoUrl,
    int? cashierId,
    String? cashierName,
    String? paymentMethod,
    DateTime? createdAt,
    String? receivedByName,
    String? receivedByPhone,
    String? deliveryType,
    String? receiverDocOrCar,
    String? fulfilledByName,
    DateTime? fulfilledAt,
    List<SaleItemRecord>? items,
  }) =>
      SaleResult(
        id: id ?? this.id,
        total: total ?? this.total,
        paid: paid ?? this.paid,
        debt: debt ?? this.debt,
        currencyRate: currencyRate ?? this.currencyRate,
        paidUzs: paidUzs ?? this.paidUzs,
        paidUsd: paidUsd ?? this.paidUsd,
        status: status ?? this.status,
        note: note ?? this.note,
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        customerPhone: customerPhone ?? this.customerPhone,
        customerPassport: customerPassport ?? this.customerPassport,
        customerPhotoUrl: customerPhotoUrl ?? this.customerPhotoUrl,
        cashierId: cashierId ?? this.cashierId,
        cashierName: cashierName ?? this.cashierName,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        createdAt: createdAt ?? this.createdAt,
        receivedByName: receivedByName ?? this.receivedByName,
        receivedByPhone: receivedByPhone ?? this.receivedByPhone,
        deliveryType: deliveryType ?? this.deliveryType,
        receiverDocOrCar: receiverDocOrCar ?? this.receiverDocOrCar,
        fulfilledByName: fulfilledByName ?? this.fulfilledByName,
        fulfilledAt: fulfilledAt ?? this.fulfilledAt,
        items: items ?? this.items,
      );

  factory SaleResult.fromJson(Map<String, dynamic> j) {
    final cust = j['customer'] as Map<String, dynamic>?;
    final itemsRaw = j['items'] as List<dynamic>?;
    return SaleResult(
      id: (j['id'] as num?)?.toInt() ?? 0,
      total: parseNum(j['total']),
      paid: parseNum(j['paid']),
      debt: parseNum(j['debt']),
      currencyRate: parseNumOrNull(j['currency_rate']),
      paidUzs: parseNumOrNull(j['paid_uzs']),
      paidUsd: parseNumOrNull(j['paid_usd']),
      status: (j['status'] as String?) ?? 'completed',
      note: j['note'] as String?,
      customerId: cust != null
          ? (cust['id'] as num?)?.toInt()
          : (j['customer_id'] as num?)?.toInt(),
      customerName: cust != null
          ? (cust['name'] as String?)
          : (j['customer_name'] as String?),
      customerPhone: cust != null
          ? (cust['phone'] as String?)
          : (j['customer_phone'] as String?),
      customerPassport: cust != null
          ? (cust['passport'] as String?)
          : (j['customer_passport'] as String?),
      customerPhotoUrl: cust != null
          ? (cust['photo_url'] as String?)
          : (j['customer_photo_url'] as String?),
      cashierId: (j['cashier_id'] as num?)?.toInt(),
      cashierName: j['cashier_name'] as String?,
      paymentMethod: (j['payment_method'] as String?) ?? 'cash',
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString())
          : null,
      receivedByName: j['received_by_name'] as String?,
      receivedByPhone: j['received_by_phone'] as String?,
      deliveryType: j['delivery_type'] as String?,
      receiverDocOrCar: j['receiver_doc_or_car'] as String?,
      fulfilledByName: j['fulfilled_by_name'] as String?,
      fulfilledAt: j['fulfilled_at'] != null
          ? DateTime.tryParse(j['fulfilled_at'].toString())
          : null,
      items: itemsRaw != null
          ? itemsRaw
              .map((e) => SaleItemRecord.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleResult && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class StockMovementRecord {
  final int id;
  final int productId;
  final String? productName;
  final double qtyDelta;
  final String kind;
  final String? note;
  final String? createdByName;
  final double? unitCost;
  final DateTime createdAt;

  const StockMovementRecord({
    required this.id,
    required this.productId,
    this.productName,
    required this.qtyDelta,
    required this.kind,
    this.note,
    this.createdByName,
    this.unitCost,
    required this.createdAt,
  });

  factory StockMovementRecord.fromJson(Map<String, dynamic> j) =>
      StockMovementRecord(
        id: (j['id'] as num?)?.toInt() ?? 0,
        productId: (j['product_id'] as num?)?.toInt() ?? 0,
        productName: j['product_name'] as String?,
        qtyDelta: parseNum(j['qty_delta']),
        kind: (j['kind'] ?? '').toString(),
        note: j['note'] as String?,
        createdByName: j['created_by_name'] as String?,
        unitCost: j['unit_cost'] != null ? parseNum(j['unit_cost']) : null,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockMovementRecord &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class FinanceSummary {
  final double revenue,
      cashCollected,
      cogs,
      grossProfit,
      expenses,
      netProfit,
      receivables;
  const FinanceSummary({
    required this.revenue,
    required this.cashCollected,
    required this.cogs,
    required this.grossProfit,
    required this.expenses,
    required this.netProfit,
    required this.receivables,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> j) => FinanceSummary(
        revenue: parseNum(j['revenue']),
        cashCollected: parseNum(j['cash_collected']),
        cogs: parseNum(j['cogs']),
        grossProfit: parseNum(j['gross_profit']),
        expenses: parseNum(j['expenses']),
        netProfit: parseNum(j['net_profit']),
        receivables: parseNum(j['receivables']),
      );
}

class FinanceTransaction {
  final int id;
  final String type; // 'income' | 'expense'
  final String category;
  final double amount;
  final String paymentMethod; // 'cash' | 'card' | 'bank'
  final String? note;
  final DateTime date;
  final String? createdByName;

  const FinanceTransaction({
    required this.id,
    required this.type,
    required this.category,
    required this.amount,
    this.paymentMethod = 'cash',
    this.note,
    required this.date,
    this.createdByName,
  });

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';

  factory FinanceTransaction.fromJson(Map<String, dynamic> j) =>
      FinanceTransaction(
        id: (j['id'] as num?)?.toInt() ?? 0,
        type: (j['type'] ?? 'expense').toString(),
        category: (j['category'] ?? '').toString(),
        amount: parseNum(j['amount']),
        paymentMethod: (j['payment_method'] ?? 'cash').toString(),
        note: j['note']?.toString(),
        date: j['date'] != null
            ? DateTime.tryParse(j['date'].toString()) ?? DateTime.now()
            : DateTime.now(),
        createdByName: j['created_by_name']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'category': category,
        'amount': amount,
        'payment_method': paymentMethod,
        'note': note,
        'date': date.toIso8601String(),
      };
}

class MonthStats {
  final String monthName;
  final int year;
  final double revenue;
  final double expenses;
  final double cogs;
  final double operationalExpenses;
  final double netProfit;
  final int salesCount;

  const MonthStats({
    required this.monthName,
    required this.year,
    required this.revenue,
    required this.expenses,
    this.cogs = 0,
    this.operationalExpenses = 0,
    required this.netProfit,
    required this.salesCount,
  });

  factory MonthStats.fromJson(Map<String, dynamic> j) => MonthStats(
        monthName: (j['month_name'] ?? '').toString(),
        year: (j['year'] as num?)?.toInt() ?? DateTime.now().year,
        revenue: parseNum(j['revenue']),
        expenses: parseNum(j['expenses']),
        cogs: parseNum(j['cogs']),
        operationalExpenses: parseNum(j['operational_expenses']),
        netProfit: parseNum(j['net_profit']),
        salesCount: (j['sales_count'] as num?)?.toInt() ?? 0,
      );
}

class MonthlyComparison {
  final MonthStats current;
  final MonthStats previous;
  final double revenueGrowthPercent;
  final double expenseGrowthPercent;
  final double netProfitGrowthPercent;

  const MonthlyComparison({
    required this.current,
    required this.previous,
    required this.revenueGrowthPercent,
    required this.expenseGrowthPercent,
    required this.netProfitGrowthPercent,
  });

  factory MonthlyComparison.fromJson(Map<String, dynamic> j) =>
      MonthlyComparison(
        current:
            MonthStats.fromJson(j['current'] as Map<String, dynamic>? ?? {}),
        previous:
            MonthStats.fromJson(j['previous'] as Map<String, dynamic>? ?? {}),
        revenueGrowthPercent: parseNum(j['revenue_growth_percent']),
        expenseGrowthPercent: parseNum(j['expense_growth_percent']),
        netProfitGrowthPercent: parseNum(j['net_profit_growth_percent']),
      );
}

class RevenueBreakdownItem {
  final String category;
  final double amount;
  final double percentage;
  final int count;
  final String colorHex;

  const RevenueBreakdownItem({
    required this.category,
    required this.amount,
    required this.percentage,
    required this.count,
    this.colorHex = '#10B981',
  });

  factory RevenueBreakdownItem.fromJson(Map<String, dynamic> j) =>
      RevenueBreakdownItem(
        category: (j['category'] ?? '').toString(),
        amount: parseNum(j['amount']),
        percentage: parseNum(j['percentage']),
        count: (j['count'] as num?)?.toInt() ?? 0,
        colorHex: (j['color_hex'] ?? '#10B981').toString(),
      );
}

class ProductionTask {
  final int id;
  final int productId;
  final String productName;
  final String unit;
  final int assignedTo;
  final String workerName;
  final double planned;
  final double produced;
  final double waste; // chiqindi / brak
  final String status; // open | pending_approval | done
  final int? approvedBy;
  final DateTime? approvedAt;
  final String? note;
  final int? orderId;
  final double? cutLength;
  final double? cutWidth;
  final int? cutPieces;
  final String? cutSpec;

  const ProductionTask({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.assignedTo,
    required this.workerName,
    required this.planned,
    required this.produced,
    this.waste = 0,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    this.note,
    this.orderId,
    this.cutLength,
    this.cutWidth,
    this.cutPieces,
    this.cutSpec,
  });

  bool get isDone => status == 'done';
  bool get isPendingApproval => status == 'pending_approval';
  bool get isRejected => status == 'rejected';
  bool get isOpen => status == 'open';

  factory ProductionTask.fromJson(Map<String, dynamic> j) => ProductionTask(
        id: (j['id'] as num?)?.toInt() ?? 0,
        productId: (j['product_id'] as num?)?.toInt() ?? 0,
        productName: (j['product_name'] ?? '').toString(),
        unit: (j['unit'] ?? 'm²').toString(),
        assignedTo: (j['assigned_to'] as num?)?.toInt() ?? 0,
        workerName: (j['worker_name'] ?? 'Ishchi').toString(),
        planned: parseNum(j['planned_qty'] ?? j['planned']),
        produced: parseNum(j['produced_qty'] ?? j['produced']),
        waste: parseNum(j['waste_qty'] ?? j['waste']),
        status: (j['status'] ?? 'open').toString(),
        approvedBy: (j['approved_by'] as num?)?.toInt(),
        approvedAt: j['approved_at'] == null
            ? null
            : DateTime.tryParse(j['approved_at'].toString()),
        note: j['note']?.toString(),
        orderId: (j['order_id'] as num?)?.toInt(),
        cutLength: parseNumOrNull(j['cut_length']),
        cutWidth: parseNumOrNull(j['cut_width']),
        cutPieces: (j['cut_pieces'] as num?)?.toInt(),
        cutSpec: j['cut_spec']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'product_name': productName,
        'unit': unit,
        'assigned_to': assignedTo,
        'worker_name': workerName,
        'planned_qty': planned,
        'produced_qty': produced,
        'waste_qty': waste,
        'status': status,
        if (approvedBy != null) 'approved_by': approvedBy,
        if (approvedAt != null) 'approved_at': approvedAt!.toIso8601String(),
        if (note != null) 'note': note,
        if (orderId != null) 'order_id': orderId,
        if (cutLength != null) 'cut_length': cutLength,
        if (cutWidth != null) 'cut_width': cutWidth,
        if (cutPieces != null) 'cut_pieces': cutPieces,
        if (cutSpec != null) 'cut_spec': cutSpec,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductionTask &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AppNotification {
  final int id;
  final String title;
  final String message;
  final String kind; // warning | payment | sale | production | system
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.kind,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        message: (j['message'] ?? '').toString(),
        kind: (j['kind'] ?? 'system').toString(),
        isRead: j['is_read'] == true,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        message: message,
        kind: kind,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotification &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DeliveryItem {
  final int? id;
  final int? productId;
  final String productName;
  final double quantity;
  final String unit;

  const DeliveryItem({
    this.id,
    this.productId,
    required this.productName,
    required this.quantity,
    this.unit = 'dona',
  });

  factory DeliveryItem.fromJson(Map<String, dynamic> j) => DeliveryItem(
        id: (j['id'] as num?)?.toInt(),
        productId: (j['product_id'] as num?)?.toInt(),
        productName: (j['product_name'] ?? '').toString(),
        quantity: parseNum(j['quantity']),
        unit: (j['unit'] ?? 'dona').toString(),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (productId != null) 'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'unit': unit,
      };
}

class Delivery {
  final int id;
  final int? saleId;
  final int? driverId;
  final String vehicleNumber;
  final String vehicleModel;
  final String driverName;
  final String? driverPhone;
  final String recipientName;
  final String? recipientPhone;
  final String? destinationAddress;
  final double deliveryFee;
  final String feePayer; // 'customer', 'store', 'included'
  final String status; // 'loading', 'on_the_way', 'delivered', 'cancelled'
  final DateTime? dispatchTime;
  final DateTime? deliveredTime;
  final String? note;
  final DateTime createdAt;
  final List<DeliveryItem> items;

  const Delivery({
    required this.id,
    this.saleId,
    this.driverId,
    required this.vehicleNumber,
    this.vehicleModel = 'Labo',
    required this.driverName,
    this.driverPhone,
    required this.recipientName,
    this.recipientPhone,
    this.destinationAddress,
    this.deliveryFee = 0,
    this.feePayer = 'customer',
    this.status = 'loading',
    this.dispatchTime,
    this.deliveredTime,
    this.note,
    required this.createdAt,
    this.items = const [],
  });

  bool get isLoading => status == 'loading';
  bool get isOnTheWay => status == 'on_the_way';
  bool get isDelivered => status == 'delivered';
  bool get isCancelled => status == 'cancelled';

  String get statusLabel {
    switch (status) {
      case 'on_the_way':
        return 'Yo‘lda';
      case 'delivered':
        return 'Yetkazildi';
      case 'cancelled':
        return 'Bekor qilingan';
      default:
        return 'Yuklanmoqda';
    }
  }

  String get feePayerLabel {
    switch (feePayer) {
      case 'store':
        return 'Do‘kon hisobidan (Bepul)';
      case 'included':
        return 'Narx ichida';
      default:
        return 'Mijoz to‘laydi';
    }
  }

  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
        id: (j['id'] as num?)?.toInt() ?? 0,
        saleId: (j['sale_id'] as num?)?.toInt(),
        driverId: (j['driver_id'] as num?)?.toInt(),
        vehicleNumber: (j['vehicle_number'] ?? '').toString(),
        vehicleModel: (j['vehicle_model'] ?? 'Labo').toString(),
        driverName: (j['driver_name'] ?? '').toString(),
        driverPhone: j['driver_phone']?.toString(),
        recipientName: (j['recipient_name'] ?? '').toString(),
        recipientPhone: j['recipient_phone']?.toString(),
        destinationAddress: j['destination_address']?.toString(),
        deliveryFee: parseNum(j['delivery_fee']),
        feePayer: (j['fee_payer'] ?? 'customer').toString(),
        status: (j['status'] ?? 'loading').toString(),
        dispatchTime: j['dispatch_time'] != null
            ? DateTime.tryParse(j['dispatch_time'].toString())
            : null,
        deliveredTime: j['delivered_time'] != null
            ? DateTime.tryParse(j['delivered_time'].toString())
            : null,
        note: j['note']?.toString(),
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        items: (j['items'] as List<dynamic>?)
                ?.map((e) => DeliveryItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        if (id > 0) 'id': id,
        if (saleId != null) 'sale_id': saleId,
        if (driverId != null) 'driver_id': driverId,
        'vehicle_number': vehicleNumber,
        'vehicle_model': vehicleModel,
        'driver_name': driverName,
        'driver_phone': driverPhone,
        'recipient_name': recipientName,
        'recipient_phone': recipientPhone,
        'destination_address': destinationAddress,
        'delivery_fee': deliveryFee,
        'fee_payer': feePayer,
        'status': status,
        if (dispatchTime != null)
          'dispatch_time': dispatchTime?.toIso8601String(),
        if (deliveredTime != null)
          'delivered_time': deliveredTime?.toIso8601String(),
        if (note != null) 'note': note,
        'items': items.map((i) => i.toJson()).toList(),
      };

  Delivery copyWith({
    int? id,
    int? saleId,
    int? driverId,
    String? vehicleNumber,
    String? vehicleModel,
    String? driverName,
    String? driverPhone,
    String? recipientName,
    String? recipientPhone,
    String? destinationAddress,
    double? deliveryFee,
    String? feePayer,
    String? status,
    DateTime? dispatchTime,
    DateTime? deliveredTime,
    String? note,
    DateTime? createdAt,
    List<DeliveryItem>? items,
  }) =>
      Delivery(
        id: id ?? this.id,
        saleId: saleId ?? this.saleId,
        driverId: driverId ?? this.driverId,
        vehicleNumber: vehicleNumber ?? this.vehicleNumber,
        vehicleModel: vehicleModel ?? this.vehicleModel,
        driverName: driverName ?? this.driverName,
        driverPhone: driverPhone ?? this.driverPhone,
        recipientName: recipientName ?? this.recipientName,
        recipientPhone: recipientPhone ?? this.recipientPhone,
        destinationAddress: destinationAddress ?? this.destinationAddress,
        deliveryFee: deliveryFee ?? this.deliveryFee,
        feePayer: feePayer ?? this.feePayer,
        status: status ?? this.status,
        dispatchTime: dispatchTime ?? this.dispatchTime,
        deliveredTime: deliveredTime ?? this.deliveredTime,
        note: note ?? this.note,
        createdAt: createdAt ?? this.createdAt,
        items: items ?? this.items,
      );
}
