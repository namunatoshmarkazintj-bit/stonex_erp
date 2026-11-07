import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/repositories.dart';
import 'data/repository_factory.dart';
import 'state/auth_controller.dart';
import 'state/cart_controller.dart';
import 'state/currency_controller.dart';
import 'state/theme_controller.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        ChangeNotifierProvider(create: (_) => CartController(repos.sales)),
        ChangeNotifierProvider(create: (_) => CurrencyController()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: Consumer<ThemeController>(
        builder: (_, themeCtrl, __) => MaterialApp(
          title: 'NTJ — Namuna Tosh Jilo',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: themeCtrl.mode,
          home: Consumer<AuthController>(
            builder: (_, auth, __) {
              if (auth.loading && auth.user == null) {
                return const Scaffold(
                  backgroundColor: AppColors.panel,
                  body: Center(
                    child: CircularProgressIndicator(color: AppColors.neonLime),
                  ),
                );
              }
              return auth.user == null ? const LoginScreen() : HomeShell(user: auth.user!);
            },
          ),
        ),
      ),
    );
  }
}
