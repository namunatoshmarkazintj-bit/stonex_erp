/// Ma'lumotlar manbasi sozlamasi.
///
/// Hozir to'g'ridan-to'g'ri haqiqiy serverdan olishga sozlandi (useMock = false).
class AppConfig {
  static const bool useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
  static String apiBaseUrl =
      const String.fromEnvironment('API_URL', defaultValue: 'https://stonex-erp-ppwx.onrender.com');
}

/// Korxona rekvizitlari va aloqa ma'lumotlari.
class CompanyInfo {
  static const String name = 'NTJ — NAMUNA TOSH JILO';
  static const String shortName = 'Namuna Tosh Jilo';
  static const String businessType = 'Tabiiy tosh va granit markazi';
  static const String address = 'Namuna MFY, Sokin ko‘cha, 11-uy';
  static const String shortAddress = 'Namuna MFY, Sokin ko‘cha 11';
  static const List<String> phones = [
    '+998 (90) 588-66-99',
    '+998 (50) 588-66-99',
    '+998 (50) 700-06-06',
  ];
  static const String phonesFormatted =
      '+998 (90) 588-66-99\n+998 (50) 588-66-99\n+998 (50) 700-06-06';
  static const String phonesInline =
      '+998 (90) 588-66-99 • +998 (50) 588-66-99 • +998 (50) 700-06-06';
}
