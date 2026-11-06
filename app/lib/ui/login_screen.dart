import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/repository_factory.dart';
import '../domain/models.dart';
import '../state/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController(text: 'admin12345');
  final _formKey = GlobalKey<FormState>();

  Role _role = Role.admin;
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
          _role,
        );

    if (mounted) {
      setState(() => _isSurging = false);
    }
  }

  void _fillDemo(String username, String pass, Role role) {
    setState(() {
      _user.text = username;
      _pass.text = pass;
      _role = role;
    });
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

          // 3. Asosiy responsiv kontent
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 960;

                if (isDesktop) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1160),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Chap tomondagi brend va imkoniyatlar paneli
                            Expanded(
                              flex: 6,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 48),
                                child: _buildBrandingShowcase(),
                              ),
                            ),

                            // O'ng tomondagi kirish kartasi
                            Expanded(
                              flex: 5,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 440),
                                  child: _buildAuthCard(auth),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // Mobil va planshet ekrani: To'liq xatosiz vertikal oqim (Overflow-Proof)
                return Center(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth < 420 ? 16 : 24,
                      vertical: 20,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMobileHeader(),
                          const SizedBox(height: 20),
                          _buildAuthCard(auth),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop uchun Chap Brend Paneli
  // ---------------------------------------------------------------------------

  Widget _buildBrandingShowcase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Brend logotipi va Versiya nishoni
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/app_icon.png',
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.neonLime,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.token_rounded, color: Color(0xFF090D14), size: 28),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NTM',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'NAMUNA TOSH MARKAZI · v2.5',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.neonLime.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 28),

        // Asosiy chaqiruv sarlavhasi
        const Text(
          'Tosh va Tabiiy Granit\nIshlab Chiqarishni Boshqarish',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.18,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Ombor zaxirasi, sexlararo topshiriqlar, QR-kodli yorliqlar, tezkor savdo va moliyaviy oqimlar yagona avtomatlashgan tizimda.',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 14,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 32),

        // 4 ta ustunlik kartasi
        _buildFeatureItem(
          icon: Icons.warehouse_rounded,
          iconColor: AppColors.neonLime,
          title: 'Aqlli Ombor & Partiyalar',
          desc: 'Xomashyo va tayyor plitalar qoldig‘i, kirim-chiqimlar real-vaqtda',
        ),
        const SizedBox(height: 14),
        _buildFeatureItem(
          icon: Icons.qr_code_scanner_rounded,
          iconColor: const Color(0xFF38BDF8),
          title: 'Smart QR-Kod & Tezkor Savdo',
          desc: 'Har bir mahsulotga avtomatik QR-yorliq va kassa skaneri',
        ),
        const SizedBox(height: 14),
        _buildFeatureItem(
          icon: Icons.precision_manufacturing_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: 'Ishlab Chiqarish & Sexlar',
          desc: 'Kesish, arralash, silliqlash buyurtmalari va xodimlar nazorati',
        ),
        const SizedBox(height: 14),
        _buildFeatureItem(
          icon: Icons.account_balance_wallet_rounded,
          iconColor: const Color(0xFF4ADE80),
          title: 'Moliyaviy Oqim & Nasiyalar',
          desc: 'Mijozlar qarzdorligi, kassa tushumi va avtomatik qarz daftari',
        ),

        const SizedBox(height: 28),

        // Tizim holati indikatori
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1724),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Barcha xizmatlar barqaror ishlamoqda (Cloud Sync Online)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1420).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobil uchun Ixcham Header
  // ---------------------------------------------------------------------------

  Widget _buildMobileHeader() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/app_icon.png',
            width: 58,
            height: 58,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.neonLime,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.token_rounded, color: Color(0xFF090D14), size: 30),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'NTM',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Namuna Tosh Markazi — Korxona Boshqaruv Tizimi',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
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

                // Rolni tanlash segment tugmalari
                const Text(
                  'Xodimlarning roli',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141A24),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      _buildRoleButton(Role.admin, 'Admin', Icons.shield_rounded),
                      _buildRoleButton(Role.kassir, 'Kassir', Icons.point_of_sale_rounded),
                      _buildRoleButton(Role.ishBoshqaruvchi, 'Boshqaruvchi', Icons.engineering_rounded),
                      _buildRoleButton(Role.ishchi, 'Ishchi', Icons.handyman_rounded),
                      _buildRoleButton(Role.haydovchi, 'Haydovchi', Icons.local_shipping_rounded),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Login maydoni
                const Text(
                  'Foydalanuvchi nomi (Login)',
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
                    hintText: 'admin, kassir yoki ishchi',
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
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Loginni kiriting' : null,
                ),

                const SizedBox(height: 16),

                // Parol maydoni
                const Text(
                  'Maxfiy parol',
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
                    hintText: '••••••••',
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

                const SizedBox(height: 20),
                const Divider(color: Color(0xFF1E2838), height: 1),
                const SizedBox(height: 14),

                // Tezkor Demo Hisoblar
                const Text(
                  'TEZKOR DEMO HISOB BILAN KIRISH:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildDemoChip('Admin', 'admin', 'admin12345', Role.admin, AppColors.neonLime, Icons.shield_rounded),
                    _buildDemoChip('Kassir', 'kassir', 'kassir123', Role.kassir, const Color(0xFF38BDF8), Icons.point_of_sale_rounded),
                    _buildDemoChip('Boshqaruvchi', 'boshqaruvchi', 'boshqaruvchi123', Role.ishBoshqaruvchi, const Color(0xFF34D399), Icons.engineering_rounded),
                    _buildDemoChip('Ishchi', 'ishchi', 'ishchi123', Role.ishchi, const Color(0xFFFBBF24), Icons.handyman_rounded),
                    _buildDemoChip('Haydovchi', 'haydovchi', 'haydovchi123', Role.haydovchi, const Color(0xFF0284C7), Icons.local_shipping_rounded),
                  ],
                ),

                const SizedBox(height: 18),

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

  Widget _buildRoleButton(Role role, String label, IconData icon) {
    final isSelected = _role == role;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _role = role),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.neonLime : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? const Color(0xFF090D14) : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 3.5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? const Color(0xFF090D14) : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDemoChip(String label, String username, String pass, Role role, Color accent, IconData icon) {
    return ActionChip(
      backgroundColor: const Color(0xFF141C28),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      avatar: Icon(icon, size: 14, color: accent),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: () => _fillDemo(username, pass, role),
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
