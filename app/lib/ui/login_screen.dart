import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/repository_factory.dart';
import '../state/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _hidePassword = true;
  bool _isSurging = false;
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_isSurging) return;

    setState(() => _isSurging = true);
    await _animCtrl.forward(from: 0);

    if (!mounted) return;
    await context.read<AuthController>().login(
          _user.text.trim(),
          _pass.text,
        );

    if (mounted) {
      setState(() => _isSurging = false);
    }
  }

  void _showServerDialog() {
    final ctrl = TextEditingController(text: AppConfig.apiBaseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.dns_rounded, color: AppColors.neonLime, size: 22),
            SizedBox(width: 10),
            Text(
              'Server manzilini tanlash',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: AppConfig.apiBaseUrl.contains('onrender')
                    ? AppColors.neonLime.withValues(alpha: 0.12)
                    : Colors.transparent,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF182232),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_queue_rounded, color: AppColors.neonLime, size: 20),
                ),
                title: const Text('Render Bulut Server (Online)',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: const Text('https://stonex-erp-ppwx.onrender.com',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                onTap: () {
                  AppConfig.apiBaseUrl = 'https://stonex-erp-ppwx.onrender.com';
                  appApiClient.baseUrl = AppConfig.apiBaseUrl;
                  setState(() {});
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: AppConfig.apiBaseUrl.contains('127.0.0.1') || AppConfig.apiBaseUrl.contains('localhost')
                    ? AppColors.neonLime.withValues(alpha: 0.12)
                    : Colors.transparent,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF182232),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.computer_rounded, color: Color(0xFF38BDF8), size: 20),
                ),
                title: const Text('Lokal Ishchi Server',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: const Text('http://127.0.0.1:8000',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                onTap: () {
                  AppConfig.apiBaseUrl = 'http://127.0.0.1:8000';
                  appApiClient.baseUrl = AppConfig.apiBaseUrl;
                  setState(() {});
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Boshqa maxsus manzil',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  hintText: 'https://...',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF161E2C),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.neonLime),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          FilledButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                AppConfig.apiBaseUrl = val;
                appApiClient.baseUrl = val;
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.neonLime,
              foregroundColor: const Color(0xFF0A0E13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Saqlash', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: const Color(0xFF070A0F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Orqa fonda yuqori unumdor arxitektura to'ri (GPU-accelerated, no video lag)
          CustomPaint(
            painter: _ArchitecturalPatternPainter(),
          ),

          // 2. Nozik neon yorug'lik effektlari (Ambient Glows)
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.neonLime.withValues(alpha: 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -120,
            child: Container(
              width: 440,
              height: 440,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF0284C7).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 3. Asosiy responsiv kontent (Markaziy toza kirish kartasi)
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 20),
                      _buildAuthCard(auth),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }



  // ---------------------------------------------------------------------------
  // Markaziy Brend Header (Logo va Nom)
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/app_icon.png',
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.neonLime,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.token_rounded, color: Color(0xFF090D14), size: 36),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'NTJ',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'NAMUNA TOSH JILO',
          style: TextStyle(
            fontSize: 12.5,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
            color: AppColors.neonLime.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Markaziy Kirish Kartasi (Desktop & Mobile moslashuvchan)
  // ---------------------------------------------------------------------------

  Widget _buildAuthCard(AuthController auth) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0D121B).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: AppColors.neonLime.withValues(alpha: 0.08),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sarlavha
                const Text(
                  'Tizimga kirish',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ish faoliyatingizni davom ettirish uchun hisobingizga kiring.',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 20),

                // Login maydoni
                const Text(
                  'Foydalanuvchi nomi yoki Kod',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _user,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF141B26),
                    hintText: 'Login yoki kodingizni kiriting',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 19, color: Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.neonLime, width: 1.5),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Login yoki kodni kiriting' : null,
                ),

                const SizedBox(height: 16),

                // Parol maydoni
                const Text(
                  'Maxfiy parol / Kod',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pass,
                  obscureText: _hidePassword,
                  onFieldSubmitted: (_) => _login(),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF141B26),
                    hintText: 'Parol yoki kodni kiriting',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19, color: Color(0xFF94A3B8)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 19,
                        color: const Color(0xFF94A3B8),
                      ),
                      onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.neonLime, width: 1.5),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Parolni kiriting' : null,
                ),

                // Xatolik xabari
                if (auth.error != null && auth.error!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E1315),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF632128)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            auth.error!,
                            style: const TextStyle(
                              color: Color(0xFFF87171),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // Kirish tugmasi
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (auth.loading || _isSurging) ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonLime,
                      foregroundColor: const Color(0xFF0A0E13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                      shadowColor: AppColors.neonLime.withValues(alpha: 0.35),
                    ),
                    child: (auth.loading || _isSurging)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF0A0E13),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Tizimga kirish',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // Server manzili indikatori
                Center(
                  child: InkWell(
                    onTap: _showServerDialog,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141B26),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Server: ${AppConfig.apiBaseUrl.replaceFirst("https://", "").replaceFirst("http://", "")}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.settings_outlined, size: 13, color: Color(0xFF94A3B8)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Yuqori unumdor arxitektura chizma foni (Video o'rniga engil va go'zal fon)
// ---------------------------------------------------------------------------

class _ArchitecturalPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF131924).withValues(alpha: 0.55)
      ..strokeWidth = 0.8;

    final dotPaint = Paint()
      ..color = const Color(0xFF1E2838)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    const step = 56.0;

    // Vertikal chiziqlar
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Gorizontal chiziqlar
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Kesishish nuqtalari
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
