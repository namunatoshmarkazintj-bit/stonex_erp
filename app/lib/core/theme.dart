import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vault / STONEX dizayn tizimi (zamonaviy quyuq grafit menyu + och kulrang panel + neon-laym urg‘ular).
class AppColors {
  static const sidebar = Color(0xFF131517);
  static const sidebarSelected = Color(0xFF1E2124);
  static const sidebarText = Color(0xFF8E959E);
  static const panel = Color(0xFFF5F6F8);
  static const darkCard = Color(0xFF131517);
  static const cardBg = Colors.white;

  // Vault dizaynidagi xos Neon-Laym (sariq-yashil) urg‘u
  static const neonLime = Color(0xFFD4F638);
  static const neonLimeSoft = Color(0xFFF4FCD3);
  static const neonLimeDark = Color(0xFF3C4800);

  // Standart yashil va ko‘rsatkichlar
  static const green = Color(0xFF10B981);
  static const greenBright = Color(0xFF22C55E);
  static const greenSoft = Color(0xFFDCFCE7);

  // Matn va chegaralar
  static const ink = Color(0xFF111417);
  static const muted = Color(0xFF71767B);
  static const border = Color(0xFFE5E7EB);
  static const borderLight = Color(0xFFEEF0F3);

  // Holatlar
  static const danger = Color(0xFFEF4444);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const warning = Color(0xFFF59E0B);
  static const warningSoft = Color(0xFFFEF3C7);
  static const info = Color(0xFF3B82F6);
  static const infoSoft = Color(0xFFDBEAFE);
}

ThemeData buildTheme([Brightness brightness = Brightness.light]) {
  final isDark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.neonLime,
    brightness: brightness,
  ).copyWith(
    primary: isDark ? AppColors.neonLime : AppColors.ink,
    secondary: AppColors.neonLime,
    surface: isDark ? const Color(0xFF161B22) : AppColors.cardBg,
    error: AppColors.danger,
    onSurface: isDark ? const Color(0xFFF0F3F6) : AppColors.ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0D1015) : AppColors.panel,
    cardColor: isDark ? const Color(0xFF161B22) : Colors.white,
    dialogTheme: DialogThemeData(backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white),
    fontFamily: 'Inter',
  );

  final radius16 = BorderRadius.circular(16);
  final radius30 = BorderRadius.circular(30);

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: isDark ? const Color(0xFFF0F3F6) : AppColors.ink,
      displayColor: isDark ? const Color(0xFFF0F3F6) : AppColors.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? const Color(0xFF0D1015) : AppColors.panel,
      foregroundColor: isDark ? const Color(0xFFF0F3F6) : AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: isDark ? const Color(0xFF0D1015) : Colors.white,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      titleTextStyle: TextStyle(
        color: isDark ? const Color(0xFFF0F3F6) : AppColors.ink,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF161B22) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius16,
        side: BorderSide(color: isDark ? const Color(0xFF262C36) : AppColors.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF21262D) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: radius30,
        borderSide: BorderSide(color: isDark ? const Color(0xFF262C36) : AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius30,
        borderSide: BorderSide(color: isDark ? const Color(0xFF262C36) : AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius30,
        borderSide: BorderSide(color: isDark ? AppColors.neonLime : AppColors.ink, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
        foregroundColor: isDark ? AppColors.ink : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius30),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? const Color(0xFFF0F3F6) : AppColors.ink,
        side: BorderSide(color: isDark ? const Color(0xFF262C36) : AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius30),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
      foregroundColor: isDark ? AppColors.ink : Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: radius30),
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? const Color(0xFF262C36) : AppColors.borderLight,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius16),
    ),
  );
}

/// Dynamic theme extension for consistent styling across light and dark modes
extension ThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get cardColor => isDark ? const Color(0xFF161B22) : Colors.white;
  Color get scaffoldBg => isDark ? const Color(0xFF0D1015) : AppColors.panel;
  Color get inkColor => isDark ? const Color(0xFFF0F3F6) : AppColors.ink;
  Color get mutedColor => isDark ? const Color(0xFF8B949E) : AppColors.muted;
  Color get borderColor => isDark ? const Color(0xFF262C36) : AppColors.border;
  Color get borderLightColor => isDark ? const Color(0xFF202630) : AppColors.borderLight;
  Color get pillColor => isDark ? const Color(0xFF21262D) : AppColors.panel;
  Color get dialogBg => isDark ? const Color(0xFF161B22) : Colors.white;
  Color get cardSubtle => isDark ? const Color(0xFF1B2129) : const Color(0xFFF9FAFB);
  Color get cardBg => cardColor;
  Color get subtextColor => mutedColor;
}