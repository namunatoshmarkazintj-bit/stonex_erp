import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/repositories.dart';
import 'data/repository_factory.dart';
import 'state/app_lock_controller.dart';
import 'state/auth_controller.dart';
import 'state/cart_controller.dart';
import 'state/currency_controller.dart';
import 'state/theme_controller.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/pin_lock_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );
  final repos = buildRepositories();
  runApp(StonexApp(repos: repos));
}

class StonexApp extends StatelessWidget {
  const StonexApp({super.key, required this.repos});
  final AppRepositories repos;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppRepositories>.value(value: repos),
        ChangeNotifierProvider(create: (_) => AuthController(repos.auth)),
        ChangeNotifierProvider(create: (_) => AppLockController()),
        ChangeNotifierProvider(create: (_) => CartController(repos.sales)),
        ChangeNotifierProvider(create: (_) => CurrencyController()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: Consumer<ThemeController>(
        builder: (_, themeCtrl, __) {
          final isDark = themeCtrl.isDark;
          final overlayStyle = SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: isDark ? const Color(0xFF0D1015) : Colors.white,
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
          );
          SystemChrome.setSystemUIOverlayStyle(overlayStyle);

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: MaterialApp(
              title: 'NTJ — Namuna Tosh Jilo',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(Brightness.light),
              darkTheme: buildTheme(Brightness.dark),
              themeMode: themeCtrl.mode,
              home: Consumer2<AuthController, AppLockController>(
                builder: (ctx, auth, appLock, _) {
                  if (auth.loading && auth.user == null) {
                    return const Scaffold(
                      backgroundColor: AppColors.panel,
                      body: Center(
                        child: CircularProgressIndicator(color: AppColors.neonLime),
                      ),
                    );
                  }
                  if (auth.user == null) {
                    return const LoginScreen();
                  }

                  if (appLock.currentUser?.id != auth.user?.id) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      appLock.syncUser(auth.user);
                    });
                  }

                  if (appLock.isLocked) {
                    return PinLockScreen(user: auth.user!);
                  }

                  return HomeShell(user: auth.user!);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
