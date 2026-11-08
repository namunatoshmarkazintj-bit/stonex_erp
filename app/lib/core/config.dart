import '../data/local_company_store.dart';

/// Ma'lumotlar manbasi sozlamasi.
///
/// Hozir to'g'ridan-to'g'ri haqiqiy serverdan olishga sozlandi (useMock = false).
class AppConfig {
  static const bool useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
  static String apiBaseUrl =
      const String.fromEnvironment('API_URL', defaultValue: 'https://stonex-erp-ppwx.onrender.com');
}

/// Korxona rekvizitlari va aloqa ma'lumotlari (foydalanuvchi tomonidan tahrirlanadigan).
class CompanyInfo {
  static const String defaultName = 'NTJ — NAMUNA TOSH JILO';
  static const String defaultShortName = 'Namuna Tosh Jilo';
  static const String defaultBusinessType = 'Tabiiy tosh va granit markazi';
  static const String defaultAddress = 'Namuna MFY, Sokin ko‘cha, 11-uy';
  static const List<String> defaultPhones = [
    '+998 (90) 588-66-99',
    '+998 (50) 588-66-99',
    '+998 (50) 700-06-06',
  ];

  static String get name => LocalCompanyStore.getName() ?? defaultName;
  static String get shortName => defaultShortName;
  static String get businessType => defaultBusinessType;
  static String get address => LocalCompanyStore.getAddress() ?? defaultAddress;
  static List<String> get phones => LocalCompanyStore.getPhones() ?? defaultPhones;
  static String get phonesFormatted => phones.join('\n');
  static String get phonesInline => phones.join(' • ');
  static String get primaryPhone => phones.isNotEmpty ? phones[0] : '';
}
