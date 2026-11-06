/// Ma'lumotlar manbasi sozlamasi.
///
/// Hozir to'g'ridan-to'g'ri haqiqiy serverdan olishga sozlandi (useMock = false).
class AppConfig {
  static const bool useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
  static String apiBaseUrl =
      const String.fromEnvironment('API_URL', defaultValue: 'https://stonex-erp-ppwx.onrender.com');
}
