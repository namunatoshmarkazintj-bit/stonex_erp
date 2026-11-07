/// 1234567.5 -> "1 234 568 so'm". Faqat ko'rsatish uchun.
String money(double v) => '${_group(v.round())} so‘m';

/// USD dollar ko'rsatish: 120 -> "$120", 120.5 -> "$120.50"
String moneyUsd(double v) {
  if (v.abs() < 0.001) return '\$0';
  if ((v - v.roundToDouble()).abs() < 0.001) {
    return '\$${_group(v.round())}';
  }
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final whole = int.tryParse(parts[0]) ?? 0;
  return '\$${_group(whole)}.${parts[1]}';
}

/// So'm va Dollar ikkalasini ko'rsatish: "1 200 000 so'm ($100)"
String moneyDual(double som, double rate) {
  if (rate <= 0) return money(som);
  final usd = som / rate;
  return '${money(som)} (${moneyUsd(usd)})';
}

String qty(double v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _group(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return neg ? '-$buf' : buf.toString();
}

/// Foydalanuvchi kiritgan sonni o'qiydi (bo'shliqlar, vergul yoki nuqta tozalangan).
double? parseInput(String s) {
  var clean = s
      .trim()
      .replaceAll(' ', '')
      .replaceAll('\u00A0', '')
      .replaceAll("'", '')
      .replaceAll('’', '')
      .replaceAll(',', '.');
  // Agar '=' yoki boshqa belgilar tasodifan yozilib qolsa (masalan '0.6='), ularni tozalash
  clean = clean.replaceAll(RegExp(r'[^\d.]+$'), '');
  return double.tryParse(clean);
}

/// Sana va vaqtni ko'rsatish uchun: 23.10.2026 14:35
String formatDateTime(DateTime dt) {
  final local = dt.isUtc ? dt.toLocal() : dt;
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final y = local.year;
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$d.$m.$y $h:$min';
}

/// Faqat sanani ko'rsatish uchun: 23.10.2026
String formatDate(DateTime dt) {
  final local = dt.isUtc ? dt.toLocal() : dt;
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final y = local.year;
  return '$d.$m.$y';
}
