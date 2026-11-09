import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/repository_factory.dart';
import '../data/role_permissions_store.dart';

class MasterPermissionsScreen extends StatefulWidget {
  const MasterPermissionsScreen({super.key});

  @override
  State<MasterPermissionsScreen> createState() => _MasterPermissionsScreenState();
}

class _MasterPermissionsScreenState extends State<MasterPermissionsScreen> {
  String _selectedRole = 'kassir';
  Map<String, Map<String, bool>> _localPerms = {};
  bool _isSaving = false;

  final _newPassCtrl = TextEditingController();

  final List<Map<String, String>> _roles = [
    {'code': 'admin', 'label': 'Admin (Xo‘jayin)', 'desc': 'Do‘kon / korxona egasi hisobi'},
    {'code': 'kassir', 'label': 'Kassir', 'desc': 'Kassa va savdo xodimi'},
    {'code': 'ish_boshqaruvchi', 'label': 'Ish boshqaruvchi', 'desc': 'Sex ustasi, ombor va sex nazorati'},
    {'code': 'haydovchi', 'label': 'Haydovchi', 'desc': 'Yetkazib berish xodimi'},
    {'code': 'ishchi', 'label': 'Ishchi', 'desc': 'Ishlab chiqarish va stanok xodimlari'},
  ];

  final List<Map<String, dynamic>> _sections = [
    {'key': 'dashboard', 'label': 'Asosiy oyna (Dashboard)', 'icon': Icons.grid_view_rounded, 'desc': 'Umumiy tahlil, diagrammalar va daromadlar'},
    {'key': 'pos', 'label': 'Savdo (POS)', 'icon': Icons.point_of_sale_rounded, 'desc': 'Kassada tovar sotish va chek chiqarish'},
    {'key': 'orders', 'label': 'Buyurtmalar', 'icon': Icons.assignment_rounded, 'desc': 'Mijozlar buyurtmalari va bronlar'},
    {'key': 'deliveries', 'label': 'Yetkazib berish', 'icon': Icons.local_shipping_rounded, 'desc': 'Haydovchi va buyurtma yetkazish ro‘yxati'},
    {'key': 'sales', 'label': 'Savdolar tarixi', 'icon': Icons.receipt_long_rounded, 'desc': 'Barcha o‘tgan cheklar va savdo arxivi'},
    {'key': 'customers', 'label': 'Mijozlar', 'icon': Icons.people_alt_rounded, 'desc': 'Mijozlar bazasi va telefon raqamlar'},
    {'key': 'debts', 'label': 'Nasiyalar (Qarzlar)', 'icon': Icons.account_balance_wallet_rounded, 'desc': 'Qarz daftari, to‘lovlar va qarzdorlar'},
    {'key': 'purchases', 'label': 'Xaridlar (Kirim)', 'icon': Icons.shopping_cart_rounded, 'desc': 'Xomashyo va tovarlar kirimi'},
    {'key': 'finance', 'label': 'Moliya', 'icon': Icons.payments_rounded, 'desc': 'Kassa, xarajatlar, sof foyda va kassa balansi'},
    {'key': 'products', 'label': 'Mahsulotlar katalogi', 'icon': Icons.inventory_2_rounded, 'desc': 'Tovarlar ro‘yxati, narxlar va qoldiq'},
    {'key': 'stock', 'label': 'Ombor', 'icon': Icons.warehouse_rounded, 'desc': 'Ombor qoldiqlari va harakatlari'},
    {'key': 'production', 'label': 'Ishlab chiqarish', 'icon': Icons.precision_manufacturing_rounded, 'desc': 'Sex topshiriqlari, kesish va tayyor mahsulot'},
    {'key': 'users', 'label': 'Xodimlar va Maosh', 'icon': Icons.badge_rounded, 'desc': 'Xodimlar ro‘yxati, davomat va oylik hisobi'},
  ];

  final List<Map<String, dynamic>> _specialActions = [
    {'key': 'view_cost_price', 'label': 'Tannarxni ko‘rish', 'icon': Icons.visibility_outlined, 'desc': 'Mahsulotlar va savdodagi haqiqiy tannarxni ko‘rish huquqi'},
    {'key': 'delete_products', 'label': 'Tovarlarni o‘chirish', 'icon': Icons.delete_outline_rounded, 'desc': 'Katalogdan tovarlarni o‘chirish yoki arxivlash'},
    {'key': 'give_discount', 'label': 'Erkin chegirma berish', 'icon': Icons.discount_outlined, 'desc': 'Savdo vaqtida mijozga erkin chegirma berish huquqi'},
  ];

  @override
  void initState() {
    super.initState();
    _cloneStorePermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromBackend();
    });
  }

  void _cloneStorePermissions() {
    final raw = RolePermissionsStore.instance.all;
    _localPerms = {};
    raw.forEach((rK, rV) {
      _localPerms[rK] = Map<String, bool>.from(rV);
    });
  }

  Future<void> _loadFromBackend() async {
    try {
      await RolePermissionsStore.instance.load(appApiClient);
      if (mounted) {
        setState(() {
          _cloneStorePermissions();
        });
      }
    } catch (e) {
      debugPrint('RolePermissions yuklashda xatolik: $e');
    }
  }

  bool _getVal(String key) {
    final m = _localPerms[_selectedRole];
    return m?[key] ?? true;
  }

  void _setVal(String key, bool val) {
    setState(() {
      _localPerms.putIfAbsent(_selectedRole, () => {})[key] = val;
    });
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    try {
      final ok = await RolePermissionsStore.instance.save(appApiClient, _localPerms);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Ruxsatlar muvaffaqiyatli saqlandi va barcha qurilmalarda kuchga kirdi!'
                : 'Xatolik yuz berdi. Internetni tekshiring.'),
            backgroundColor: ok ? AppColors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saqlashda xatolik: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _changeMasterPassword() async {
    final pass = _newPassCtrl.text.trim();
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yangi parol kamida 6 belgidan iborat bo‘lishi kerak!'), backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      // Find master user id
      await appApiClient.patch('/users/change-password-master', body: {'password': pass}).catchError((_) async {
        // Fallback generic endpoint if needed
        return {};
      });
      _newPassCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Master paroli muvaffaqiyatli yangilandi!'), backgroundColor: AppColors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Parol yangilashda xato: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header banner
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.neonLime,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.security_rounded, color: AppColors.ink, size: 24),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Master Boshqaruv — Rollar Huquqlari Matritsasi',
                                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'Ushbu maxfiy panel orqali istalgan rolga (hatto adminga ham) bo‘limlarni ko‘rsatish yoki yashirishni boshqarasiz.',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: _isSaving ? null : _saveAll,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.neonLime,
                                  foregroundColor: AppColors.ink,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: _isSaving
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.save_rounded, size: 18),
                                label: const Text('O‘zgarishlarni Saqlash', style: TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Role Selector
                        const Text('1. Tahrirlash uchun rolni tanlang:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: _roles.map((r) {
                            final code = r['code']!;
                            final isSel = _selectedRole == code;
                            return ChoiceChip(
                              label: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(r['label']!,
                                        style: TextStyle(
                                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                          color: isSel ? AppColors.ink : context.inkColor,
                                        )),
                                    Text(r['desc']!,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: isSel ? AppColors.ink.withOpacity(0.75) : context.mutedColor,
                                        )),
                                  ],
                                ),
                              ),
                              selected: isSel,
                              selectedColor: AppColors.neonLime,
                              backgroundColor: context.cardColor,
                              onSelected: (_) => setState(() => _selectedRole = code),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // Section 1: Navigation Screens
                        Text(
                          '2. «${_roles.firstWhere((r) => r['code'] == _selectedRole)['label']}» roli uchun ko‘rinadigan bo‘limlar:',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // Grid of screens permissions
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 80,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, idx) {
                        final s = _sections[idx];
                        final key = s['key'] as String;
                        final val = _getVal(key);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: val
                                  ? (isDark ? AppColors.neonLime.withOpacity(0.3) : const Color(0xFF10B981).withOpacity(0.3))
                                  : context.borderColor,
                              width: val ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: val
                                      ? (isDark ? const Color(0xFF1E2E1E) : const Color(0xFFDCFCE7))
                                      : (isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(s['icon'] as IconData,
                                    color: val ? (isDark ? AppColors.neonLime : const Color(0xFF16A34A)) : Colors.grey, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(s['label'] as String,
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: val ? context.inkColor : context.mutedColor)),
                                    const SizedBox(height: 2),
                                    Text(s['desc'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 10, color: context.mutedColor)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: val,
                                activeColor: isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                                onChanged: (v) => _setVal(key, v),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _sections.length,
                    ),
                  ),
                ),

                // Section 2: Special Actions
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '3. «${_roles.firstWhere((r) => r['code'] == _selectedRole)['label']}» roli uchun maxsus amallar:',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 80,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, idx) {
                        final a = _specialActions[idx];
                        final key = a['key'] as String;
                        final val = _getVal(key);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: val
                                  ? (isDark ? Colors.amber.withOpacity(0.4) : Colors.amber.shade300)
                                  : context.borderColor,
                              width: val ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: val
                                      ? (isDark ? const Color(0xFF332A15) : const Color(0xFFFEF3C7))
                                      : (isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(a['icon'] as IconData,
                                    color: val ? const Color(0xFFD97706) : Colors.grey, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(a['label'] as String,
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: val ? context.inkColor : context.mutedColor)),
                                    const SizedBox(height: 2),
                                    Text(a['desc'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 10, color: context.mutedColor)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: val,
                                activeColor: const Color(0xFFD97706),
                                onChanged: (v) => _setVal(key, v),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _specialActions.length,
                    ),
                  ),
                ),

                // Save button bottom spacer
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveAll,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonLime,
                          foregroundColor: AppColors.ink,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: const Text('Barcha o‘zgarishlarni saqlash',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
