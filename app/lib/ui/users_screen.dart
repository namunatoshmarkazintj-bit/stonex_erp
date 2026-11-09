import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import 'common.dart';
import 'archived_users_screen.dart';
import 'finance_screen.dart';

class _KpiItem {
  final String label;
  final String value;
  final String subtext;
  final IconData icon;
  final Color color;

  const _KpiItem({
    required this.label,
    required this.value,
    required this.subtext,
    required this.icon,
    required this.color,
  });
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  int _currentTab = 0; // 0: Xodimlar, 1: Davomat (Keldi-Ketdi), 2: Oylik hisobi

  // Tab 0: Xodimlar
  late Future<List<AppUser>> _usersFuture;
  String _selectedFilter = 'Barchasi';
  final _searchCtrl = TextEditingController();

  // Tab 1: Davomat
  DateTime _selectedDate = DateTime.now();
  late Future<List<AttendanceRecord>> _attendanceFuture;
  final _attSearchCtrl = TextEditingController();
  String _attFilter = 'Barchasi'; // 'Barchasi', 'Kelganlar', 'Hali kelmaganlar', 'Kechikkanlar'

  // Tab 2: Oylik hisobi
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final int _totalWorkingDays = 26;
  late Future<List<SalaryReportItem>> _salaryFuture;
  final _salarySearchCtrl = TextEditingController();
  String _salaryFilter = 'Barchasi'; // 'Barchasi', 'Ishchilar', 'Haydovchilar', 'Maoshi borlar', 'Intizomli', 'Kechikkanlar'
  String _salarySort = 'default'; // 'default', 'salary_desc', 'days_desc', 'name_asc'

  UserRepository get _usersRepo => context.read<AppRepositories>().users;
  AttendanceRepository get _attRepo => context.read<AppRepositories>().attendance;

  String get _dateStr =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  String get _monthStr =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _reloadUsers();
    _reloadAttendance();
    _reloadSalary();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _attSearchCtrl.dispose();
    _salarySearchCtrl.dispose();
    super.dispose();
  }

  void _reloadUsers() {
    setState(() {
      _usersFuture = _usersRepo.list();
    });
  }

  void _reloadAttendance() {
    setState(() {
      _attendanceFuture = _attRepo.list(date: _dateStr);
    });
  }

  void _reloadSalary() {
    setState(() {
      _salaryFuture = _attRepo.getSalaryReport(
        month: _monthStr,
        totalWorkingDays: _totalWorkingDays,
      );
    });
  }

  void _reloadAll() {
    _reloadUsers();
    _reloadAttendance();
    _reloadSalary();
  }

  // --- Xodim qo'shish va tahrirlash ---
  Future<void> _addUser() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => UserDialog(repo: _usersRepo),
    );
    if (ok == true && mounted) {
      showMessage(context, 'Yangi xodim muvaffaqiyatli qo‘shildi');
      _reloadAll();
    }
  }

  Future<void> _editUser(AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => UserDialog(repo: _usersRepo, user: user),
    );
    if (ok == true && mounted) {
      showMessage(context, 'Xodim ma’lumotlari yangilandi');
      _reloadAll();
    }
  }

  Future<void> _toggleUserStatus(AppUser user) async {
    final action = user.isActive ? 'bloklash' : 'faollashtirish';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          user.isActive ? 'Xodimni bloklash' : 'Xodimni faollashtirish',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          user.isActive
              ? '"${user.fullName}" hisobini bloklamoqchimisiz? U tizimga kira olmaydi.'
              : '"${user.fullName}" hisobini qayta faollashtirmoqchimisiz?',
          style: const TextStyle(height: 1.4, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: user.isActive ? AppColors.danger : AppColors.darkCard,
            ),
            child: Text(user.isActive ? 'Bloklash' : 'Faollashtirish'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _usersRepo.update(
        user.id,
        fullName: user.fullName,
        role: user.role,
        isActive: !user.isActive,
      );
      if (mounted) {
        showMessage(context, 'Xodim muvaffaqiyatli $action qilindi');
        _reloadAll();
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Xatolik: $e', error: true);
      }
    }
  }

  Future<void> _archiveUser(AppUser user) async {
    if (user.role == Role.admin) {
      showMessage(context, "Asosiy admin akkauntini arxivga olib bo‘lmaydi!", error: true);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.archive_outlined, color: AppColors.danger, size: 22),
            SizedBox(width: 10),
            Text('Xodimni arxivlash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Text(
          '"${user.fullName}" hisobi arxivga olinsinmi?\nU dasturga kira olmay qoladi va faol ishchilar ro‘yxatidan olib tashlanadi.',
          style: const TextStyle(height: 1.4, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: const Text('Arxivga olish', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _usersRepo.archive(user.id);
      if (mounted) {
        showMessage(context, '${user.fullName} arxivga o‘tkazildi');
        _reloadAll();
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Xatolik: $e', error: true);
      }
    }
  }

  Future<void> _openArchivedUsers() async {
    final anyRestored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ArchivedUsersScreen()),
    );
    if (anyRestored == true && mounted) {
      _reloadAll();
    }
  }

  // --- Davomat amallari ---
  Future<void> _checkIn(AppUser user, {String status = 'present'}) async {
    try {
      final now = DateTime.now();
      if (status == 'late' || status == 'absent') {
        final rec = AttendanceRecord(
          id: 0,
          userId: user.id,
          userName: user.fullName,
          date: _dateStr,
          status: status,
          checkIn: status == 'absent' ? null : now,
          workedHours: 0,
        );
        await _attRepo.saveRecord(rec);
      } else {
        await _attRepo.checkIn(user.id, time: now);
      }
      if (mounted) {
        final statusLabel = status == 'late'
            ? 'kechikkan'
            : (status == 'absent' ? 'kelmagan' : 'keldi');
        showMessage(
          context,
          '✓ ${user.fullName} $statusLabel deb qayd etildi (${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')})',
        );
        _reloadAttendance();
        _reloadSalary();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Xatolik: $e', error: true);
    }
  }

  Future<void> _checkInAllAbsent(List<AppUser> absentUsers) async {
    if (absentUsers.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: AppColors.green),
            SizedBox(width: 8),
            Text('Tezkor umumiy davomat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          'Hali kelmagan ${absentUsers.length} nafar xodim uchun hozirgi vaqt bilan kirish (keldi) qayd etilsinmi?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Ha, barchasini belgilash'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final now = DateTime.now();
    int count = 0;
    try {
      await _attRepo.bulkCheckIn(absentUsers.map((u) => u.id).toList(), time: now, date: _dateStr);
      count = absentUsers.length;
    } catch (_) {
      // Fallback
      for (final u in absentUsers) {
        try {
          await _attRepo.checkIn(u.id, time: now);
          count++;
        } catch (_) {}
      }
    } finally {
      if (mounted) {
        if (count > 0) {
          showMessage(context, '✓ $count nafar xodim keldi deb belgilandi');
        }
        _reloadAttendance();
        _reloadSalary();
      }
    }
  }

  Future<void> _checkOut(AppUser user) async {
    try {
      final now = DateTime.now();
      await _attRepo.checkOut(user.id, time: now);
      if (mounted) {
        showMessage(
          context,
          '✓ ${user.fullName} ketdi deb qayd etildi (${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')})',
        );
        _reloadAttendance();
        _reloadSalary();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Xatolik: $e', error: true);
    }
  }

  Future<void> _checkOutAllWorking(List<AppUser> workingUsers) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFEA580C), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Hammasini ketdi qilish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          'Barcha hozir ishlayotgan xodimlarning (${workingUsers.length} ta) ish vaqtini yakunlamoqchimisiz?\nChiqish vaqti hozirgi vaqt deb belgilanadi.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ha, barchasini yakunlash', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final now = DateTime.now();
      for (final u in workingUsers) {
        await _attRepo.checkOut(u.id, time: now);
      }
      if (mounted) {
        showMessage(
          context,
          '✓ ${workingUsers.length} ta xodimning ish vaqti yakunlandi (${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')})',
        );
        _reloadAttendance();
        _reloadSalary();
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Xatolik: $e', error: true);
    }
  }

  Future<void> _editAttendance(AppUser user, AttendanceRecord? rec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AttendanceDialog(
        repo: _attRepo,
        user: user,
        date: _dateStr,
        record: rec,
      ),
    );
    if (ok == true && mounted) {
      showMessage(context, 'Davomat ma’lumotlari saqlandi');
      _reloadAttendance();
      _reloadSalary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      floatingActionButton: _buildFab(),
      body: Column(
        children: [
          // 1. Yuqori zamonaviy Tab Switcher
          _buildTopTabs(),

          // 2. Tab mazmuni
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: [
                _buildUsersTab(),
                _buildAttendanceTab(),
                _buildSalaryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildFab() {
    if (_currentTab == 0) {
      return FloatingActionButton.extended(
        backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
        foregroundColor: context.isDark ? AppColors.ink : Colors.white,
        onPressed: _addUser,
        icon: Icon(Icons.person_add_rounded, color: context.isDark ? AppColors.ink : AppColors.neonLime),
        label: const Text('Xodim qo‘shish', style: TextStyle(fontWeight: FontWeight.w700)),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Top Tabs (Burchaksiz zamonaviy kapsula / Segmented UI)
  // ---------------------------------------------------------------------------
  Widget _buildTopTabs() {
    final tabs = [
      ('Xodimlar', Icons.people_alt_rounded),
      ('Davomat (Keldi / Ketdi)', Icons.access_time_rounded),
      ('Oylik hisobi', Icons.account_balance_wallet_rounded),
    ];

    final isDark = context.isDark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(bottom: BorderSide(color: context.borderColor.withValues(alpha: 0.6))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161E28) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: context.borderColor.withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                InkWell(
                  onTap: () => setState(() => _currentTab = i),
                  borderRadius: BorderRadius.circular(100),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8.5),
                    decoration: BoxDecoration(
                      color: _currentTab == i
                          ? (isDark ? const Color(0xFF242A35) : const Color(0xFF2D3748))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: _currentTab == i
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tabs[i].$2,
                          size: 16,
                          color: _currentTab == i ? Colors.white : context.mutedColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tabs[i].$1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _currentTab == i ? FontWeight.w800 : FontWeight.w600,
                            color: _currentTab == i ? Colors.white : context.mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 0: Xodimlar Ro'yxati
  // ---------------------------------------------------------------------------
  Widget _buildUsersTab() {
    final filterOptions = ['Barchasi', 'Adminlar', 'Kassirlar', 'Ish boshqaruvchi', 'Ishchilar', 'Haydovchilar', 'Dasturga kiradiganlar', 'Faqat ro‘yxatdagilar', 'Bloklanganlar'];

    return FutureBuilder<List<AppUser>>(
      future: _usersFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: snap.error.toString(), onRetry: _reloadUsers);
        }

        final allUsers = (snap.data ?? [])
            .where((u) => u.role != Role.master && u.username != 'master')
            .toList();
        final totalCount = allUsers.length;
        final adminCount = allUsers.where((u) => u.role == Role.admin).length;
        final cashierCount = allUsers.where((u) => u.role == Role.kassir).length;
        final workerCount = allUsers.where((u) => u.role == Role.ishchi).length;
        final driverCount = allUsers.where((u) => u.role == Role.haydovchi).length;
        final blockedCount = allUsers.where((u) => !u.isActive).length;

        var users = allUsers.where((u) {
          final query = _searchCtrl.text.toLowerCase().trim();
          final matchesSearch = query.isEmpty ||
              u.fullName.toLowerCase().contains(query) ||
              u.username.toLowerCase().contains(query);

          if (!matchesSearch) return false;

          switch (_selectedFilter) {
            case 'Adminlar':
              return u.role == Role.admin && u.isActive;
            case 'Kassirlar':
              return u.role == Role.kassir && u.isActive;
            case 'Ish boshqaruvchi':
              return u.role == Role.ishBoshqaruvchi && u.isActive;
            case 'Ishchilar':
              return u.role == Role.ishchi && u.isActive;
            case 'Haydovchilar':
              return u.role == Role.haydovchi && u.isActive;
            case 'Dasturga kiradiganlar':
              return u.canLogin && u.isActive;
            case 'Faqat ro‘yxatdagilar':
              return !u.canLogin && u.isActive;
            case 'Bloklanganlar':
              return !u.isActive;
            default:
              return true;
          }
        }).toList();

        return RefreshIndicator(
          onRefresh: () async => _reloadUsers(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // KPI Kartalari
              Row(
                children: [
                  _buildKpiCard('Jami Xodimlar', '$totalCount ta', Icons.badge_rounded, AppColors.ink),
                  const SizedBox(width: 10),
                  _buildKpiCard('Adminlar', '$adminCount ta', Icons.admin_panel_settings_rounded, AppColors.neonLime),
                  const SizedBox(width: 10),
                  _buildKpiCard('Kassirlar', '$cashierCount ta', Icons.point_of_sale_rounded, AppColors.green),
                  const SizedBox(width: 10),
                  _buildKpiCard('Ishchilar', '$workerCount ta', Icons.precision_manufacturing_rounded, const Color(0xFFD97706)),
                ],
              ),
              const SizedBox(height: 14),

              // Qidiruv va Filter
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Xodim nomi yoki logini bo‘yicha qidirish...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          filled: true,
                          fillColor: context.cardColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: context.borderColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Arxivdagi xodimlar',
                    child: OutlinedButton(
                      onPressed: _openArchivedUsers,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: BorderSide(color: AppColors.danger.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.archive_outlined, size: 18, color: AppColors.danger),
                          SizedBox(width: 6),
                          Text('Arxiv', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Filter teglari
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: filterOptions.map((f) {
                    final isSel = _selectedFilter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(f, style: TextStyle(fontSize: 12, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: isSel ? Colors.white : context.inkColor)),
                        selected: isSel,
                        onSelected: (_) => setState(() => _selectedFilter = f),
                        selectedColor: context.isDark ? const Color(0xFF242A35) : const Color(0xFF2D3748),
                        checkmarkColor: Colors.white,
                        side: BorderSide(
                          color: isSel
                              ? (context.isDark ? const Color(0xFF3B4454) : const Color(0xFF334155))
                              : context.borderColor,
                          width: 1,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Xodimlar ro'yxati
              if (users.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(Icons.person_off_rounded, size: 48, color: context.mutedColor.withValues(alpha: 0.5)),
                        const SizedBox(height: 10),
                        Text('Xodimlar topilmadi', style: TextStyle(color: context.mutedColor, fontSize: 14)),
                      ],
                    ),
                  ),
                )
              else
                for (final u in users) _buildUserCard(u),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserCard(AppUser u) {
    Color roleColor;
    switch (u.role) {
      case Role.master:
        roleColor = const Color(0xFFEF4444);
        break;
      case Role.admin:
        roleColor = const Color(0xFF8B5CF6);
        break;
      case Role.kassir:
        roleColor = AppColors.green;
        break;
      case Role.ishBoshqaruvchi:
        roleColor = const Color(0xFF0D9488);
        break;
      case Role.ishchi:
        roleColor = const Color(0xFFD97706);
        break;
      case Role.haydovchi:
        roleColor = const Color(0xFF0284C7);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: u.isActive ? context.borderColor : AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: roleColor.withValues(alpha: 0.15),
            child: Text(
              u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
              style: TextStyle(fontWeight: FontWeight.w800, color: roleColor, fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.fullName,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.inkColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        u.role.label,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: roleColor),
                      ),
                    ),
                    if (!u.canLogin)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF21262D) : const Color(0xFFEFF2F6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: context.borderColor, width: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.badge_outlined, size: 11, color: context.mutedColor),
                            const SizedBox(width: 3),
                            Text(
                              'Faqat ro‘yxatda',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.mutedColor),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.key_rounded, size: 10, color: AppColors.green),
                            SizedBox(width: 3),
                            Text(
                              'Kirish ruxsati bor',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.green),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (u.canLogin) ...[
                      Text(
                        '@${u.username}',
                        style: TextStyle(fontSize: 11.5, color: context.mutedColor),
                      ),
                      const Text('·', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ],
                    Text(
                      u.salaryType == 'trip'
                          ? (u.salary > 0
                              ? 'Maosh: ${money(u.salary)} (reysbay)'
                              : 'Maosh: Reysbay (yetkazishdan)')
                          : 'Maosh: ${money(u.salary)} (${u.salaryType == "daily" ? "kunbay" : (u.salaryType == "hourly" ? "soatbay" : "oylik")})',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.inkColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.edit_rounded, size: 18),
                onPressed: () => _editUser(u),
                tooltip: 'Tahrirlash',
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                icon: Icon(
                  u.isActive ? Icons.lock_open_rounded : Icons.lock_rounded,
                  size: 18,
                  color: u.isActive ? AppColors.green : AppColors.danger,
                ),
                onPressed: () => _toggleUserStatus(u),
                tooltip: u.isActive ? 'Bloklash' : 'Faollashtirish',
              ),
              if (u.role != Role.admin) ...[
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.danger),
                  onPressed: () => _archiveUser(u),
                  tooltip: 'Arxivga olish (o‘chirish)',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: Davomat (Keldi / Ketdi) - Zamonaviy, qulay va tezkor UI
  // ---------------------------------------------------------------------------
  Widget _buildAttendanceTab() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_usersFuture, _attendanceFuture]),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: snap.error.toString(), onRetry: _reloadAttendance);
        }

        final users = (snap.data?[0] as List<AppUser>?)
                ?.where((u) => u.isActive && u.role != Role.master && u.username != 'master')
                .toList() ??
            [];
        final attendances = (snap.data?[1] as List<AttendanceRecord>?) ?? [];

        final attMap = <int, AttendanceRecord>{};
        for (final a in attendances) {
          attMap[a.userId] = a;
        }

        final presentCount = attendances.where((a) => a.checkIn != null).length;
        final lateCount = attendances.where((a) => a.status == 'late').length;
        final totalActive = users.length;
        final absentUsers = users.where((u) => attMap[u.id]?.checkIn == null).toList();
        final absentCount = absentUsers.length;
        final workingUsers = users.where((u) {
          final a = attMap[u.id];
          return a?.checkIn != null && a?.checkOut == null;
        }).toList();

        // Qidiruv va filtr bo'yicha saralash
        final query = _attSearchCtrl.text.toLowerCase().trim();
        final filteredUsers = users.where((u) {
          final matchesSearch = query.isEmpty ||
              u.fullName.toLowerCase().contains(query) ||
              u.username.toLowerCase().contains(query);
          if (!matchesSearch) return false;

          final att = attMap[u.id];
          final hasCheckedIn = att?.checkIn != null;
          final isLate = att?.status == 'late';

          switch (_attFilter) {
            case 'Kelganlar':
              return hasCheckedIn;
            case 'Hali kelmaganlar':
              return !hasCheckedIn;
            case 'Kechikkanlar':
              return isLate;
            default:
              return true;
          }
        }).toList();

        final isToday = _isToday(_selectedDate);

        return RefreshIndicator(
          onRefresh: () async => _reloadAttendance(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Sana boshqaruvi va Ish vaqti sozlamalari
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final changed = await ShiftConfigDialog.show(context, _attRepo);
                      if (changed == true && mounted) {
                        showMessage(context, '✓ Ish vaqti sozlamalari yangilandi');
                        _reloadAll();
                      }
                    },
                    icon: const Icon(Icons.more_time_rounded, size: 16),
                    label: const Text('Ish vaqti sozlamalari', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.inkColor,
                      side: BorderSide(color: context.borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: context.borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tezkor 'Kecha' va 'Bugun'
                        _buildQuickDateChip('Kecha', DateTime.now().subtract(const Duration(days: 1))),
                        const SizedBox(width: 3),
                        _buildQuickDateChip('Bugun', DateTime.now()),
                        const SizedBox(width: 6),

                        // Ajratuvchi nozik chiziq
                        Container(
                          width: 1,
                          height: 22,
                          color: context.borderColor.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),

                        // Oldingi kun <
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 22),
                          onPressed: () {
                            setState(() {
                              _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                              _reloadAttendance();
                            });
                          },
                          tooltip: 'Oldingi kun',
                          splashRadius: 18,
                          visualDensity: VisualDensity.compact,
                        ),

                        // Markaziy interaktiv sana (Stonex Custom Kalendar)
                        InkWell(
                          onTap: () async {
                            final picked = await StonexDatePickerDialog.show(
                              context: context,
                              initialDate: _selectedDate,
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedDate = picked;
                                _reloadAttendance();
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(100),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? (context.isDark ? AppColors.neonLime.withValues(alpha: 0.15) : const Color(0xFFF0FDF4))
                                  : context.pillColor,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: isToday
                                    ? (context.isDark ? AppColors.neonLime : const Color(0xFF22C55E))
                                    : context.borderColor.withValues(alpha: 0.6),
                                width: isToday ? 1.2 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 16,
                                  color: isToday
                                      ? (context.isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                      : context.inkColor,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  _formatDateUz(_selectedDate),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: isToday
                                        ? (context.isDark ? AppColors.neonLime : const Color(0xFF15803D))
                                        : context.inkColor,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: isToday
                                      ? (context.isDark ? AppColors.neonLime : const Color(0xFF16A34A))
                                      : context.mutedColor,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Keyingi kun >
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 22),
                          onPressed: () {
                            setState(() {
                              _selectedDate = _selectedDate.add(const Duration(days: 1));
                              _reloadAttendance();
                            });
                          },
                          tooltip: 'Keyingi kun',
                          splashRadius: 18,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

              // 2. KPI statistika kartalari
              Row(
                children: [
                  _buildKpiCard('Jami xodimlar', '$totalActive ta', Icons.people_outline_rounded, AppColors.ink),
                  const SizedBox(width: 8),
                  _buildKpiCard('Kelganlar', '$presentCount ta', Icons.check_circle_outline_rounded, AppColors.green),
                  const SizedBox(width: 8),
                  _buildKpiCard('Kechikkanlar', '$lateCount ta', Icons.warning_amber_rounded, const Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  _buildKpiCard('Kelmaganlar', '$absentCount ta', Icons.cancel_outlined, AppColors.danger),
                ],
              ),
              const SizedBox(height: 14),

              // 3. Qidiruv va Tezkor "Barchasini keldi qilish" tugmasi
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _attSearchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Xodim nomi bo‘yicha qidirish...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _attSearchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () {
                                    _attSearchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          filled: true,
                          fillColor: context.cardColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(100),
                            borderSide: BorderSide(color: context.borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(100),
                            borderSide: BorderSide(color: context.borderColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (absentUsers.isNotEmpty && isToday) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _checkInAllAbsent(absentUsers),
                      icon: const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(
                        'Hammasini keldi qilish (${absentUsers.length})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      ),
                    ),
                  ] else if (workingUsers.isNotEmpty && isToday) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _checkOutAllWorking(workingUsers),
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: Text(
                        'Hammasini ketdi qilish (${workingUsers.length})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEA580C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // 4. Filtr chiplari (Yaxlit burchaksiz kapsula segmented control)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: context.isDark ? AppColors.darkCard : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: context.borderColor.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in [
                        ('Barchasi', totalActive, null),
                        ('Kelganlar', presentCount, AppColors.green),
                        ('Kechikkanlar', lateCount, const Color(0xFFD97706)),
                        ('Hali kelmaganlar', absentCount, AppColors.danger),
                      ])
                        _buildAttendanceFilterChip(
                          label: item.$1,
                          count: item.$2,
                          dotColor: item.$3,
                          isSelected: _attFilter == item.$1,
                          onTap: () => setState(() => _attFilter = item.$1),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 5. Xodimlar davomat kartalari ro'yxati
              if (filteredUsers.isEmpty) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(Icons.person_off_rounded, size: 44, color: context.mutedColor.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text('Xodimlar topilmadi', style: TextStyle(color: context.mutedColor, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                for (final u in filteredUsers)
                  _buildAttendanceRow(u, attMap[u.id]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickDateChip(String label, DateTime targetDate) {
    final isSelected = _selectedDate.year == targetDate.year &&
        _selectedDate.month == targetDate.month &&
        _selectedDate.day == targetDate.day;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedDate = targetDate;
          _reloadAttendance();
        });
      },
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (context.isDark ? const Color(0xFF242A35) : const Color(0xFF2D3748))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? (context.isDark ? AppColors.ink : Colors.white)
                : context.mutedColor,
          ),
        ),
      ),
    );
  }

  String _formatDateUz(DateTime dt) {
    const months = [
      'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun',
      'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'
    ];
    const weekdays = [
      'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'
    ];
    final dayName = weekdays[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    return '${dt.day}-$monthName, ${dt.year} ($dayName)';
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Widget _buildAttendanceFilterChip({
    required String label,
    required int count,
    required Color? dotColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (context.isDark ? const Color(0xFF242A35) : const Color(0xFF2D3748))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isSelected && dotColor != null && count > 0) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (context.isDark ? AppColors.ink : Colors.white)
                    : context.mutedColor,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? (context.isDark ? AppColors.ink.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.2))
                    : (context.isDark ? AppColors.cardBg : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? (context.isDark ? AppColors.ink : Colors.white)
                      : context.inkColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Widget _buildAttendanceRow(AppUser u, AttendanceRecord? att) {
    final hasCheckedIn = att?.checkIn != null;
    final hasCheckedOut = att?.checkOut != null;
    final isLate = att?.status == 'late';

    String statusText = 'Kelmagan';
    Color statusColor = AppColors.danger;
    IconData statusIcon = Icons.close_rounded;

    if (isLate) {
      statusText = 'Kechikkan';
      statusColor = const Color(0xFFD97706);
      statusIcon = Icons.access_time_rounded;
    } else if (hasCheckedIn) {
      statusText = 'Kelgan';
      statusColor = AppColors.green;
      statusIcon = Icons.check_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.borderColor.withValues(alpha: 0.8),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. Initial Avatar with mini-status indicator
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 1.2),
                ),
                alignment: Alignment.center,
                child: Text(
                  _getInitials(u.fullName),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: statusColor,
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.cardColor, width: 2),
                  ),
                  child: Icon(statusIcon, size: 9, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),

          // 2. Worker info and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1-qator: Xodim ismi va roli (och, ixcham, burchaksiz yozuv)
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        u.fullName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: context.inkColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• ${u.role.label}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.mutedColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // 2-qator: Yagona, ixcham va toza holat ko'rsatkichi (tiqilinchsiz)
                Row(
                  children: [
                    if (hasCheckedIn) ...[
                      if (hasCheckedOut) ...[
                        // Ish yakunlangan
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: context.isDark ? AppColors.darkCard : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: context.borderColor.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, size: 13, color: AppColors.green),
                              const SizedBox(width: 5),
                              Text(
                                '${_formatTime(att!.checkIn!)} – ${_formatTime(att.checkOut!)} (${att.workedHours.toStringAsFixed(1)} soat)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: context.inkColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Hozir ishlayotgan xodim
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: isLate
                                ? (context.isDark
                                    ? const Color(0xFFD97706).withValues(alpha: 0.16)
                                    : const Color(0xFFFEF3C7))
                                : (context.isDark
                                    ? AppColors.green.withValues(alpha: 0.16)
                                    : const Color(0xFFDCFCE7)),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLate ? Icons.access_time_rounded : Icons.check_circle_rounded,
                                size: 13,
                                color: isLate ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isLate
                                    ? 'Kechikkan · Keldi ${_formatTime(att!.checkIn!)}'
                                    : 'Hozir ishda · Keldi ${_formatTime(att!.checkIn!)}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: isLate ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      // Hali kelmagan
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? AppColors.darkCard
                              : const Color(0xFFFEE2E2).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 13, color: AppColors.danger),
                            SizedBox(width: 5),
                            Text(
                              'Hali kelmagan',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (att?.note != null && att!.note!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '📝 ${att.note}',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: context.mutedColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 3. Action Buttons
          if (!hasCheckedIn) ...[
            InkWell(
              onTap: () => _checkIn(u, status: 'present'),
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: context.isDark ? AppColors.green.withValues(alpha: 0.18) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.green.withValues(alpha: 0.4), width: 1.2),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.login_rounded, size: 14, color: AppColors.green),
                    SizedBox(width: 5),
                    Text('Keldi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.green)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 18, color: context.mutedColor),
              splashRadius: 18,
              tooltip: 'Boshqa amallar',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (val) {
                if (val == 'late') {
                  _checkIn(u, status: 'late');
                } else if (val == 'absent') {
                  _checkIn(u, status: 'absent');
                } else if (val == 'edit') {
                  _editAttendance(u, att);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'late',
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
                      SizedBox(width: 8),
                      Text('Kechikkan deb belgilash', style: TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'absent',
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined, size: 16, color: AppColors.danger),
                      SizedBox(width: 8),
                      Text('Kelmagan deb belgilash', style: TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_note_rounded, size: 16),
                      SizedBox(width: 8),
                      Text('Vaqtni qo‘lda kiritish', style: TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ] else if (!hasCheckedOut) ...[
            InkWell(
              onTap: () => _checkOut(u),
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFFEA580C).withValues(alpha: 0.18) : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.45), width: 1.2),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.logout_rounded, size: 14, color: Color(0xFFEA580C)),
                    SizedBox(width: 5),
                    Text('Ketdi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFEA580C))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              decoration: BoxDecoration(
                color: context.pillColor,
                shape: BoxShape.circle,
                border: Border.all(color: context.borderColor.withValues(alpha: 0.8)),
              ),
              child: IconButton(
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                onPressed: () => _editAttendance(u, att),
                tooltip: 'Tahrirlash',
                splashRadius: 18,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: AppColors.green),
                  SizedBox(width: 4),
                  Text(
                    'Yakunlangan',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Container(
              decoration: BoxDecoration(
                color: context.pillColor,
                shape: BoxShape.circle,
                border: Border.all(color: context.borderColor.withValues(alpha: 0.8)),
              ),
              child: IconButton(
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                onPressed: () => _editAttendance(u, att),
                tooltip: 'Tahrirlash',
                splashRadius: 18,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _getMonthNameUz(int m) {
    const months = [
      'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun',
      'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'
    ];
    return months[(m - 1).clamp(0, 11)];
  }

  Widget _getRoleBadge(String role) {
    String text = 'Xodim';
    Color color = const Color(0xFF64748B);
    IconData icon = Icons.badge_rounded;

    switch (role.toLowerCase()) {
      case 'admin':
        text = 'Admin';
        color = const Color(0xFF8B5CF6);
        icon = Icons.admin_panel_settings_rounded;
        break;
      case 'kassir':
        text = 'Kassir';
        color = AppColors.green;
        icon = Icons.point_of_sale_rounded;
        break;
      case 'ish_boshqaruvchi':
      case 'ishboshqaruvchi':
        text = 'Boshqaruvchi';
        color = const Color(0xFF0D9488);
        icon = Icons.manage_accounts_rounded;
        break;
      case 'ishchi':
        text = 'Ishchi';
        color = const Color(0xFFD97706);
        icon = Icons.precision_manufacturing_rounded;
        break;
      case 'haydovchi':
        text = 'Haydovchi';
        color = const Color(0xFF0284C7);
        icon = Icons.local_shipping_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return const Color(0xFF8B5CF6);
      case 'kassir':
        return AppColors.green;
      case 'ish_boshqaruvchi':
      case 'ishboshqaruvchi':
        return const Color(0xFF0D9488);
      case 'ishchi':
        return const Color(0xFFD97706);
      case 'haydovchi':
        return const Color(0xFF0284C7);
      default:
        return const Color(0xFF64748B);
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 2: Oylik va Ish haqi hisoboti (Payroll)
  // ---------------------------------------------------------------------------
  Widget _buildSalaryTab() {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final isDark = context.isDark;

    return FutureBuilder<List<SalaryReportItem>>(
      future: _salaryFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: snap.error.toString(), onRetry: _reloadSalary);
        }

        final allReports = snap.data ?? [];
        // Xo'jayinga (admin) oylik to'lanmaydi! Malik Abduxalilov va boshqa adminlar chiqarilmaydi
        final reports = allReports.where((r) {
          final roleLower = r.role.toLowerCase();
          return roleLower != 'admin' && roleLower != 'ta’sischi' && !roleLower.contains('admin');
        }).toList();
        final totalNet = reports.fold(0.0, (sum, r) => sum + r.netSalary);
        final totalBase = reports.fold(0.0, (sum, r) => sum + r.baseSalary);
        final totalCalculated = reports.fold(0.0, (sum, r) => sum + r.calculatedSalary);
        final totalPaid = reports.fold(0.0, (sum, r) => sum + r.paidAmount);
        final totalRemaining = reports.fold(0.0, (sum, r) => sum + r.remainingSalary);
        final totalDeductions = reports.fold(0.0, (sum, r) => sum + r.deduction);
        final lateCount = reports.where((r) => r.daysLate > 0).length;

        // Qidiruv va filtr
        final query = _salarySearchCtrl.text.toLowerCase().trim();
        var filteredReports = reports.where((r) {
          final matchesSearch = query.isEmpty ||
              r.fullName.toLowerCase().contains(query) ||
              r.role.toLowerCase().contains(query);
          if (!matchesSearch) return false;

          switch (_salaryFilter) {
            case 'Ishchilar':
              return r.role.toLowerCase() == 'ishchi';
            case 'Haydovchilar':
              return r.role.toLowerCase() == 'haydovchi';
            case 'Maoshi borlar':
              return r.baseSalary > 0;
            case 'Intizomli':
              return r.daysLate == 0;
            case 'Kechikkanlar':
              return r.daysLate > 0;
            default:
              return true;
          }
        }).toList();

        // Saralash
        if (_salarySort == 'salary_desc') {
          filteredReports.sort((a, b) => b.netSalary.compareTo(a.netSalary));
        } else if (_salarySort == 'days_desc') {
          filteredReports.sort((a, b) => b.daysWorked.compareTo(a.daysWorked));
        } else if (_salarySort == 'name_asc') {
          filteredReports.sort((a, b) => a.fullName.compareTo(b.fullName));
        }

        return RefreshIndicator(
          onRefresh: () async => _reloadSalary(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Oyni tanlash va Harakatlar paneli
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    // Oy boshqaruvi
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: context.pillColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            tooltip: 'Oldingi oy',
                            onPressed: () {
                              setState(() {
                                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                                _reloadSalary();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: context.pillColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_month_rounded,
                                size: 18,
                                color: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_getMonthNameUz(_selectedMonth.month)}, ${_selectedMonth.year}',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: context.inkColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: context.pillColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            tooltip: 'Keyingi oy',
                            onPressed: () {
                              setState(() {
                                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                                _reloadSalary();
                              });
                            },
                          ),
                        ),
                        if (!isCurrentMonth) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _selectedMonth = DateTime(now.year, now.month);
                                _reloadSalary();
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.neonLime.withValues(alpha: 0.15)
                                    : const Color(0xFF0284C7).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.neonLime.withValues(alpha: 0.3)
                                      : const Color(0xFF0284C7).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                'Joriy oy',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Tezkor amallar: Barchasiga oylik to'lash va Excel yuklash
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Ish vaqti sozlamalari
                        OutlinedButton.icon(
                          onPressed: () async {
                            final changed = await ShiftConfigDialog.show(context, _attRepo);
                            if (changed == true && mounted) {
                              showMessage(context, '✓ Ish vaqti sozlamalari yangilandi');
                              _reloadAll();
                            }
                          },
                          icon: const Icon(Icons.more_time_rounded, size: 16),
                          label: const Text(
                            'Ish vaqti',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.inkColor,
                            side: BorderSide(color: context.borderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Excel export tugmasi
                        OutlinedButton.icon(
                          onPressed: reports.isEmpty ? null : () => _exportSalaryCsv(reports),
                          icon: const Icon(Icons.table_view_rounded, size: 16),
                          label: const Text(
                            'Excel tabel',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.inkColor,
                            side: BorderSide(color: context.borderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Barchasiga to'lash tugmasi
                        FilledButton.icon(
                          onPressed: reports.isEmpty
                              ? null
                              : () async {
                                  final ok = await FinanceTransactionDialog.show(
                                    context,
                                    autoPayAll: true,
                                    initialCategory: 'Ish haqi / Avans',
                                    initialType: 'expense',
                                  );
                                  if (ok == true && mounted) {
                                    showMessage(context, '✓ Oylik to‘lovlari moliya bo‘limiga saqlandi');
                                    _reloadSalary();
                                  }
                                },
                          icon: const Icon(Icons.payments_rounded, size: 16),
                          label: const Text(
                            'Barchasiga oylik to‘lash',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF242A35) : const Color(0xFF2D3748),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. Kengaytirilgan 4 ta KPI kartasi
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;
                  final itemW = isWide ? (constraints.maxWidth - 30) / 4 : (constraints.maxWidth - 10) / 2;

                  final kpiList = [
                    _KpiItem(
                      label: 'Jami Sof Oylik',
                      value: money(totalRemaining > 0 ? totalRemaining : totalNet),
                      subtext: totalPaid > 0 ? 'Qoldiq: ${money(totalRemaining)} (${money(totalPaid)} to‘langan)' : 'To‘lanadigan yakuniy hisob',
                      icon: Icons.payments_rounded,
                      color: AppColors.green,
                    ),
                    _KpiItem(
                      label: 'Rejadagi Oylik Fond',
                      value: money(totalBase),
                      subtext: 'Shtat bo‘yicha to‘liq summa',
                      icon: Icons.account_balance_wallet_rounded,
                      color: const Color(0xFF3B82F6),
                    ),
                    _KpiItem(
                      label: 'Haqiqiy Ishlagani',
                      value: money(totalCalculated),
                      subtext: 'Davomat kunlari hisobi',
                      icon: Icons.work_history_rounded,
                      color: const Color(0xFFD97706),
                    ),
                    _KpiItem(
                      label: 'Kechikish Jarimalari',
                      value: totalDeductions > 0 ? '-${money(totalDeductions)}' : '0 so‘m',
                      subtext: lateCount > 0 ? '$lateCount nafar xodim kechikkan' : 'Kechikishlar yo‘q',
                      icon: Icons.gavel_rounded,
                      color: totalDeductions > 0 ? AppColors.danger : AppColors.green,
                    ),
                  ];

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kpiList.map((item) {
                      return SizedBox(
                        width: itemW,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: item.color.withValues(alpha: isDark ? 0.2 : 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(item.icon, size: 20, color: item.color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.label,
                                      style: TextStyle(fontSize: 10.5, color: context.mutedColor, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.value,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: item.color == AppColors.green && item.label == 'Jami Sof Oylik'
                                            ? (isDark ? AppColors.neonLime : AppColors.green)
                                            : context.inkColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      item.subtext,
                                      style: TextStyle(fontSize: 9.5, color: context.mutedColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 14),

              // 3. Qidiruv va Filtr paneli
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        // Qidiruv maydoni
                        Expanded(
                          child: TextField(
                            controller: _salarySearchCtrl,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(fontSize: 13, color: context.inkColor),
                            decoration: InputDecoration(
                              hintText: 'Xodim ismi yoki lavozimi bo‘yicha qidirish...',
                              hintStyle: TextStyle(fontSize: 12.5, color: context.mutedColor),
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              suffixIcon: _salarySearchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 16),
                                      onPressed: () {
                                        _salarySearchCtrl.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              filled: true,
                              fillColor: context.pillColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: context.borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: context.borderColor.withValues(alpha: 0.5)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Saralash popup
                        PopupMenuButton<String>(
                          tooltip: 'Saralash',
                          initialValue: _salarySort,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          color: context.cardColor,
                          onSelected: (val) => setState(() => _salarySort = val),
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'default',
                              child: Text('Standart ketma-ketlik', style: TextStyle(fontSize: 12.5)),
                            ),
                            const PopupMenuItem(
                              value: 'salary_desc',
                              child: Text('Maosh bo‘yicha (eng ko‘p)', style: TextStyle(fontSize: 12.5)),
                            ),
                            const PopupMenuItem(
                              value: 'days_desc',
                              child: Text('Davomat bo‘yicha (eng ko‘p kun)', style: TextStyle(fontSize: 12.5)),
                            ),
                            const PopupMenuItem(
                              value: 'name_asc',
                              child: Text('Alifbo bo‘yicha (A-Z)', style: TextStyle(fontSize: 12.5)),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: context.pillColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: context.borderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.sort_rounded, size: 16, color: context.mutedColor),
                                const SizedBox(width: 4),
                                Text(
                                  _salarySort == 'salary_desc'
                                      ? 'Maosh'
                                      : (_salarySort == 'days_desc' ? 'Davomat' : (_salarySort == 'name_asc' ? 'A-Z' : 'Tartib')),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.inkColor),
                                ),
                                const SizedBox(width: 2),
                                Icon(Icons.arrow_drop_down_rounded, size: 16, color: context.mutedColor),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Filtr chiplari
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          for (final f in [
                            'Barchasi',
                            'Ishchilar',
                            'Haydovchilar',
                            'Maoshi borlar',
                            'Intizomli',
                            'Kechikkanlar'
                          ]) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  f == 'Barchasi' ? 'Barchasi (${reports.length})' : f,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: _salaryFilter == f ? FontWeight.w800 : FontWeight.w600,
                                    color: _salaryFilter == f ? Colors.white : context.inkColor,
                                  ),
                                ),
                                selected: _salaryFilter == f,
                                onSelected: (_) => setState(() => _salaryFilter = f),
                                selectedColor: isDark ? const Color(0xFF242A35) : const Color(0xFF2D3748),
                                checkmarkColor: Colors.white,
                                backgroundColor: context.pillColor,
                                side: BorderSide(
                                  color: _salaryFilter == f
                                      ? (isDark ? const Color(0xFF3B4454) : const Color(0xFF334155))
                                      : context.borderColor,
                                  width: 1,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 4. Xodimlar ro'yxati yoki Bo'sh holat
              if (filteredReports.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.person_search_rounded, size: 48, color: context.mutedColor),
                      const SizedBox(height: 10),
                      Text(
                        'Mos keluvchi xodimlar topilmadi',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: context.inkColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qidiruv yoki filtr parametrlarini o‘zgartirib ko‘ring',
                        style: TextStyle(fontSize: 12, color: context.mutedColor),
                      ),
                    ],
                  ),
                )
              else
                for (final rep in filteredReports) _buildSalaryItemCard(rep),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSalaryItemCard(SalaryReportItem r) {
    final isDark = context.isDark;
    final roleColor = _getRoleColor(r.role);
    final unit = r.salaryType == "daily"
        ? "kun"
        : (r.salaryType == "hourly" ? "soat" : (r.salaryType == "trip" ? "reys" : "oy"));

    final hasSalaryRate = r.baseSalary > 0;
    final progress = _totalWorkingDays > 0 ? (r.daysWorked / _totalWorkingDays).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1-Qator: Xodim shaxsi (Avatar, Ism, Lavozim) va Sof maosh
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      roleColor.withValues(alpha: isDark ? 0.35 : 0.2),
                      roleColor.withValues(alpha: isDark ? 0.15 : 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: roleColor.withValues(alpha: 0.4), width: 1.2),
                ),
                alignment: Alignment.center,
                child: Text(
                  _getInitials(r.fullName),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: roleColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Ism, Lavozim va Oylik stavkasi
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.fullName,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: context.inkColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _getRoleBadge(r.role),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (hasSalaryRate)
                      Text(
                        'Stavka: ${money(r.baseSalary)} / $unit',
                        style: TextStyle(fontSize: 12, color: context.mutedColor, fontWeight: FontWeight.w600),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '⚠️ Stavka belgilanmagan',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // To'lanadigan sof maosh / Qoldiq
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (r.remainingSalary <= 0 && r.paidAmount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                          SizedBox(width: 4),
                          Text(
                            'To‘liq to‘langan',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'To‘langan: ${money(r.paidAmount)}',
                      style: TextStyle(fontSize: 11, color: context.mutedColor, fontWeight: FontWeight.w700),
                    ),
                  ] else ...[
                    Text(
                      money(r.remainingSalary > 0 ? r.remainingSalary : r.netSalary),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: isDark ? const Color(0xFF10B981) : const Color(0xFF16A34A),
                      ),
                    ),
                    Text(
                      'To‘lanadigan sof maosh',
                      style: TextStyle(fontSize: 10, color: context.mutedColor, fontWeight: FontWeight.w600),
                    ),

                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2-Qator: Tartibli ko'rsatkichlar paneli (2x2 qulay katakcha)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.pillColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // 1. Davomat
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Davomat',
                            style: TextStyle(fontSize: 11, color: context.mutedColor, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: [
                              Text(
                                '${r.daysWorked}/$_totalWorkingDays kun',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.inkColor),
                              ),
                              Text(
                                '(${r.hoursWorked.toStringAsFixed(1)}s)',
                                style: TextStyle(fontSize: 11, color: context.mutedColor, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            r.daysLate > 0
                                ? '${r.daysLate} kun kechikdi'
                                : 'Intizomli (kechikishsiz)',
                            style: TextStyle(
                              fontSize: 10,
                              color: r.daysLate > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 42, color: context.borderColor.withValues(alpha: 0.6), margin: const EdgeInsets.symmetric(horizontal: 10)),
                    // 2. Qoldiq to'lov
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Qoldiq summa',
                            style: TextStyle(fontSize: 11, color: context.mutedColor, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              money(r.remainingSalary > 0 ? r.remainingSalary : r.netSalary),
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: (r.remainingSalary <= 0 && r.paidAmount > 0)
                                    ? const Color(0xFF10B981)
                                    : (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            (r.remainingSalary <= 0 && r.paidAmount > 0) ? 'To‘liq to‘langan' : 'To‘lanishi kerak',
                            style: TextStyle(
                              fontSize: 10,
                              color: (r.remainingSalary <= 0 && r.paidAmount > 0) ? const Color(0xFF10B981) : context.mutedColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: context.borderColor.withValues(alpha: 0.5)),
                ),
                Row(
                  children: [
                    // 3. Ishlagan qismi
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ishlagan qismi:',
                            style: TextStyle(fontSize: 11, color: context.mutedColor, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              money(r.calculatedSalary),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.inkColor),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            r.bonus > 0 ? 'Mukofot: +${money(r.bonus)}' : (r.deduction > 0 ? 'Jarima: -${money(r.deduction)}' : 'Hisoblangan maosh'),
                            style: TextStyle(
                              fontSize: 10,
                              color: r.bonus > 0 ? const Color(0xFFD97706) : context.mutedColor,
                              fontWeight: r.bonus > 0 ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 42, color: context.borderColor.withValues(alpha: 0.6), margin: const EdgeInsets.symmetric(horizontal: 10)),
                    // 4. To'langan (Avans)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'To‘langan',
                            style: TextStyle(fontSize: 11, color: context.mutedColor, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              money(r.paidAmount),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: r.paidAmount > 0 ? context.inkColor : context.mutedColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            r.paidAmount > 0 ? 'Avans / To‘lovlar' : 'To‘lanmagan',
                            style: TextStyle(fontSize: 10, color: context.mutedColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3-Qator: Amallar tugmalari (Ustma-ust va qulay taqsimlangan)
          Row(
            children: [
              // 1. Davomat tafsilotlari (kunlar)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showEmployeeAttendanceDetails(r),
                  icon: Icon(Icons.calendar_today_rounded, size: 14, color: context.mutedColor),
                  label: const Text(
                    'Davomat kunlari',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.inkColor,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 2. Mukofot (Bonus) berish
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await EmployeeBonusDialog.show(
                    context,
                    item: r,
                    month: '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}',
                    repos: context.read<AppRepositories>(),
                  );
                  if (ok == true && mounted) {
                    showMessage(context, '✓ ${r.fullName} uchun mukofot muvaffaqiyatli saqlandi');
                    _reloadSalary();
                  }
                },
                icon: const Icon(Icons.card_giftcard_rounded, size: 14, color: Color(0xFFD97706)),
                label: Text(
                  'Mukofot',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.inkColor),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.inkColor,
                  side: BorderSide(color: context.borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 3. Oylik to'lash / To'lov qilish (To'liq kenglikda)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final ok = await FinanceTransactionDialog.show(
                  context,
                  initialCategory: 'Ish haqi / Avans',
                  initialType: 'expense',
                  initialUserId: r.userId,
                  initialAmount: r.remainingSalary > 0
                      ? r.remainingSalary
                      : (r.netSalary > 0 ? r.netSalary : (r.calculatedSalary > 0 ? r.calculatedSalary : null)),
                );
                if (ok == true && mounted) {
                  showMessage(context, '✓ ${r.fullName} uchun to‘lov saqlandi');
                  _reloadSalary();
                }
              },
              icon: const Icon(Icons.payments_rounded, size: 15),
              label: Text(
                r.remainingSalary <= 0 && r.paidAmount > 0 ? '+ To‘lov / Avans' : 'Oylik to‘lash',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Xodimning oylik davomat tafsilotlari dialogi
  Future<void> _showEmployeeAttendanceDetails(SalaryReportItem r) async {
    final isDark = context.isDark;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: dialogCtx.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Sarlavhasi
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _getRoleColor(r.role).withValues(alpha: isDark ? 0.3 : 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _getInitials(r.fullName),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _getRoleColor(r.role),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.fullName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: dialogCtx.inkColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_getMonthNameUz(_selectedMonth.month)} ${_selectedMonth.year} davomat tabeli · ${r.daysWorked} kun / ${r.hoursWorked.toStringAsFixed(1)} soat',
                              style: TextStyle(fontSize: 12, color: dialogCtx.mutedColor),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Yopish',
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Qaydlar ro'yxati
                Flexible(
                  child: FutureBuilder<List<AttendanceRecord>>(
                    future: _attRepo.list(month: _monthStr, userId: r.userId),
                    builder: (c, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
                      }
                      final list = snap.data ?? [];
                      if (list.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_busy_rounded, size: 40, color: dialogCtx.mutedColor),
                                const SizedBox(height: 8),
                                Text(
                                  'Bu oyda davomat yozuvlari topilmadi',
                                  style: TextStyle(fontSize: 13, color: dialogCtx.mutedColor),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Kunlar bo'yicha saralash
                      list.sort((a, b) => a.date.compareTo(b.date));

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (c, idx) {
                          final att = list[idx];
                          final isLate = att.status == 'late';
                          final inTime = att.checkIn != null ? _formatTime(att.checkIn!) : '--:--';
                          final outTime = att.checkOut != null ? _formatTime(att.checkOut!) : 'Ketmagan';

                          final parsedDate = DateTime.tryParse(att.date);
                          final dateLabel = parsedDate != null
                              ? '${parsedDate.day.toString().padLeft(2, '0')}.${parsedDate.month.toString().padLeft(2, '0')}'
                              : att.date;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: dialogCtx.pillColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: dialogCtx.borderColor.withValues(alpha: 0.6)),
                            ),
                            child: Row(
                              children: [
                                // Sana
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: dialogCtx.cardColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    dateLabel,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: dialogCtx.inkColor),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Kirish va Chiqish
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 2,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.login_rounded, size: 13, color: isLate ? AppColors.danger : AppColors.green),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Kirish: $inTime',
                                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: dialogCtx.inkColor),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.logout_rounded, size: 13, color: att.checkOut != null ? const Color(0xFF3B82F6) : dialogCtx.mutedColor),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Chiqish: $outTime',
                                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: dialogCtx.inkColor),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if (att.workedHours > 0) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Ishlangan: ${att.workedHours.toStringAsFixed(1)} soat',
                                          style: TextStyle(fontSize: 10.5, color: dialogCtx.mutedColor),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // Holat badge
                                if (isLate)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.danger.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Kechikkan',
                                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.danger),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Vaqtida',
                                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.green),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const Divider(height: 1),
                // Footer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Yopish'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Excel (CSV) fayl qilib eksport qilish
  Future<void> _exportSalaryCsv(List<SalaryReportItem> reports) async {
    try {
      final buf = StringBuffer();
      // CSV Header
      buf.writeln('Xodim;Lavozim;Stavka turi;Oylik stavka (so‘m);Ishlagan kun;Ishlagan soat;Kechikkan kun;Hisoblangan ish haqi (so‘m);Jarima/Chegirma (so‘m);To‘lanadigan sof maosh (so‘m)');

      for (final r in reports) {
        final sType = r.salaryType == 'daily' ? 'Kunlik' : (r.salaryType == 'hourly' ? 'Soatbay' : (r.salaryType == 'trip' ? 'Reysbay' : 'Oylik'));
        buf.writeln('${r.fullName};${r.role};$sType;${r.baseSalary.toInt()};${r.daysWorked};${r.hoursWorked};${r.daysLate};${r.calculatedSalary.toInt()};${r.deduction.toInt()};${r.netSalary.toInt()}');
      }

      var csv = buf.toString();
      if (!csv.startsWith('\uFEFF')) {
        csv = '\uFEFF$csv';
      }

      final defaultFileName = 'Oylik_va_davomat_${_selectedMonth.year}_${_selectedMonth.month.toString().padLeft(2, '0')}.csv';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      Uri? savedUri;
      try {
        savedUri = await FilePicker.saveFile(
          dialogTitle: 'Oylik tabelini saqlash joyini tanlang',
          fileName: defaultFileName,
          bytes: bytes,
        );
      } catch (_) {
        savedUri = null;
      }

      if (savedUri == null) return;

      final savedPath = savedUri.scheme == 'file' ? savedUri.toFilePath() : savedUri.path;
      try {
        final f = File(savedPath);
        await f.writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint('Fayl yozish: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.table_view_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Oylik tabeli muvaffaqiyatli saqlandi: $defaultFileName',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Eksportda xatolik: $e', error: true);
    }
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10.5, color: context.mutedColor, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: context.inkColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Xodim qo'shish va tahrirlash dialogi
// ---------------------------------------------------------------------------

class UserDialog extends StatefulWidget {
  const UserDialog({super.key, required this.repo, this.user});
  final UserRepository repo;
  final AppUser? user;

  @override
  State<UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<UserDialog> {
  late final _userCtrl = TextEditingController(text: widget.user?.username ?? '');
  late final _nameCtrl = TextEditingController(text: widget.user?.fullName ?? '');
  final _passCtrl = TextEditingController();
  late Role _role = widget.user?.role ?? Role.ishchi;
  late String _salaryType = widget.user?.salaryType ?? (_role == Role.haydovchi ? 'trip' : 'monthly');
  late final _salaryCtrl = TextEditingController(
    text: widget.user != null
        ? widget.user!.salary.toInt().toString()
        : (_role == Role.haydovchi ? '0' : '5000000'),
  );
  late bool _isActive = widget.user?.isActive ?? true;
  late bool _canLogin = widget.user?.canLogin ?? (_role != Role.ishchi);

  String? _error;
  bool _busy = false;

  bool get _isEditing => widget.user != null;

  @override
  void dispose() {
    _userCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = _nameCtrl.text.trim();
    final sal = double.tryParse(_salaryCtrl.text.replaceAll(' ', '')) ?? 0;

    if (n.isEmpty) {
      setState(() {
        _error = 'Xodimning to‘liq ismini kiriting';
      });
      return;
    }

    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;

    if (_canLogin) {
      if (u.isEmpty) {
        setState(() {
          _error = 'Dasturga kirish uchun loginni kiriting';
        });
        return;
      }
      if (!_isEditing && p.isEmpty) {
        setState(() {
          _error = 'Dasturga kirish uchun parol kiritish shart';
        });
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await widget.repo.update(
          widget.user!.id,
          username: _canLogin ? u : null,
          fullName: n,
          password: (_canLogin && p.isNotEmpty) ? p : null,
          role: _role,
          canLogin: _canLogin,
          salary: sal,
          salaryType: _salaryType,
          isActive: _isActive,
        );
      } else {
        await widget.repo.create(
          username: _canLogin ? u : null,
          fullName: n,
          password: _canLogin ? p : null,
          role: _role,
          canLogin: _canLogin,
          salary: sal,
          salaryType: _salaryType,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.pillColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isEditing ? Icons.manage_accounts_rounded : Icons.person_add_rounded,
              color: context.inkColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isEditing ? 'Xodimni tahrirlash' : 'Yangi xodim qo‘shish',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. To'liq ismi (F.I.O)
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'To‘liq ismi (F.I.O)',
                  hintText: 'masalan: Bobur Rahimov',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Tizimdagi roli
              DropdownButtonFormField<Role>(
                value: _role,
                decoration: const InputDecoration(
                  labelText: 'Tizimdagi roli',
                  prefixIcon: Icon(Icons.work_outline_rounded),
                ),
                items: Role.values
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _role = v ?? _role;
                    if (_role == Role.admin || _role == Role.kassir || _role == Role.haydovchi || _role == Role.ishBoshqaruvchi) {
                      _canLogin = true;
                    }
                    if (_role == Role.haydovchi) {
                      _salaryType = 'trip';
                      if (_salaryCtrl.text == '5000000' || _salaryCtrl.text.isEmpty) {
                        _salaryCtrl.text = '0';
                      }
                    } else if (_salaryType == 'trip') {
                      _salaryType = 'monthly';
                      if (_salaryCtrl.text == '0') {
                        _salaryCtrl.text = '5000000';
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),

              // 3. Dasturga kirish huquqi (Login & Parol) switch card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.pillColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      _canLogin ? Icons.lock_open_rounded : Icons.lock_clock_rounded,
                      size: 20,
                      color: _canLogin
                          ? (context.isDark ? AppColors.neonLime : AppColors.ink)
                          : context.mutedColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dasturga kirish huquqi',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _canLogin
                                ? 'Login va parol orqali tizimga kira oladi'
                                : 'Faqat ro‘yxatda (dasturga kirmaydi, login/parol shart emas)',
                            style: TextStyle(
                              fontSize: 11,
                              color: _canLogin ? AppColors.green : context.mutedColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _canLogin,
                      activeColor: AppColors.green,
                      onChanged: (_role == Role.admin || _role == Role.kassir || _role == Role.ishBoshqaruvchi)
                          ? null
                          : (v) => setState(() => _canLogin = v),
                    ),
                  ],
                ),
              ),

              // 4. Login & Parol maydonlari (agar dasturga kirishi kerak bo'lsa)
              if (_canLogin) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _userCtrl,
                  enabled: !_isEditing,
                  decoration: InputDecoration(
                    labelText: 'Login (foydalanuvchi nomi)',
                    hintText: 'masalan: bobur_uz',
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                    helperText: _isEditing ? 'Loginni o‘zgartirib bo‘lmaydi' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _isEditing ? 'Yangi parol (ixtiyoriy)' : 'Parol',
                    hintText: _isEditing ? 'O‘zgartirmaslik uchun bo‘sh qoldiring' : 'Kamida 6 ta belgi',
                    prefixIcon: const Icon(Icons.password_rounded),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (context.isDark ? AppColors.neonLime : const Color(0xFF16A34A)).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (context.isDark ? AppColors.neonLime : const Color(0xFF16A34A)).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: context.isDark ? AppColors.neonLime : const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Xodim faqat ro‘yxatda saqlanadi. U ishlab chiqarish vazifalarida (kesish, faska, silliqlash), davomatda va oylik hisobida to‘liq qatnashadi, ammo dasturga kirish uchun login va parol talab etilmaydi.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: context.inkColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // 5. Maosh stavkasi
              TextField(
                controller: _salaryCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _salaryType == 'trip'
                      ? 'Reys stavkasi (0 bo‘lsa buyurtmadagi yo‘l haqi)'
                      : 'Maosh stavkasi (so‘m)',
                  hintText: _salaryType == 'trip' ? '0' : '5000000',
                  helperText: _salaryType == 'trip'
                      ? '0 bo‘lsa, yetkazilgan buyurtmalardagi yo‘l haqi summasi to‘lanadi'
                      : null,
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // 6. Maosh hisoblash turi
              DropdownButtonFormField<String>(
                value: _salaryType,
                decoration: const InputDecoration(
                  labelText: 'Maosh hisoblash turi',
                  prefixIcon: Icon(Icons.calendar_month_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('Oylik (oybay fixed)')),
                  DropdownMenuItem(value: 'daily', child: Text('Kunlik (kunbay stavka)')),
                  DropdownMenuItem(value: 'hourly', child: Text('Soatlik (soatbay stavka)')),
                  DropdownMenuItem(value: 'trip', child: Text('Reysbay (yetkazilgan buyurtmalardan)')),
                ],
                onChanged: (v) {
                  setState(() {
                    _salaryType = v ?? 'monthly';
                    if (_salaryType == 'trip' && _salaryCtrl.text == '5000000') {
                      _salaryCtrl.text = '0';
                    }
                  });
                },
              ),
              if (_isEditing) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.pillColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Xodim holati', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(
                              _isActive ? 'Faol xodim' : 'Hisob bloklangan',
                              style: TextStyle(
                                fontSize: 11,
                                color: _isActive ? AppColors.green : AppColors.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isActive,
                        activeColor: AppColors.green,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.isDark ? const Color(0xFF331616) : const Color(0xFFFFECEB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Bekor'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
            foregroundColor: context.isDark ? AppColors.ink : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEditing ? 'Saqlash' : 'Qo‘shish', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Davomatni tahrirlash dialogi
// ---------------------------------------------------------------------------

class AttendanceDialog extends StatefulWidget {
  const AttendanceDialog({
    super.key,
    required this.repo,
    required this.user,
    required this.date,
    this.record,
  });

  final AttendanceRepository repo;
  final AppUser user;
  final String date;
  final AttendanceRecord? record;

  @override
  State<AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<AttendanceDialog> {
  late TimeOfDay _checkInTime;
  late TimeOfDay _checkOutTime;
  late String _status = widget.record?.status ?? 'present';
  late final _noteCtrl = TextEditingController(text: widget.record?.note ?? '');
  bool _hasCheckIn = false;
  bool _hasCheckOut = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.record?.checkIn != null) {
      _hasCheckIn = true;
      _checkInTime = TimeOfDay.fromDateTime(widget.record!.checkIn!);
    } else {
      _checkInTime = const TimeOfDay(hour: 8, minute: 30);
    }

    if (widget.record?.checkOut != null) {
      _hasCheckOut = true;
      _checkOutTime = TimeOfDay.fromDateTime(widget.record!.checkOut!);
    } else {
      _checkOutTime = const TimeOfDay(hour: 18, minute: 0);
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);

    DateTime? inDt;
    DateTime? outDt;
    final parts = widget.date.split('-');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);

    if (_hasCheckIn) {
      inDt = DateTime(y, m, d, _checkInTime.hour, _checkInTime.minute);
    }
    if (_hasCheckOut) {
      outDt = DateTime(y, m, d, _checkOutTime.hour, _checkOutTime.minute);
    }

    double worked = 0;
    if (inDt != null && outDt != null) {
      worked = double.parse((outDt.difference(inDt).inMinutes / 60.0).clamp(0.0, 24.0).toStringAsFixed(1));
    }

    final rec = AttendanceRecord(
      id: widget.record?.id ?? 0,
      userId: widget.user.id,
      userName: widget.user.fullName,
      date: widget.date,
      checkIn: inDt,
      checkOut: outDt,
      workedHours: worked,
      status: _status,
      note: _noteCtrl.text.trim(),
    );

    try {
      await widget.repo.saveRecord(rec);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, 'Xatolik: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.access_time_rounded, color: AppColors.darkCard, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.user.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${widget.date} davomati', style: TextStyle(fontSize: 12, color: context.mutedColor)),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kelish vaqti
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Kelgan vaqti: ${_checkInTime.format(context)}'),
                value: _hasCheckIn,
                onChanged: (v) => setState(() => _hasCheckIn = v ?? false),
                secondary: IconButton(
                  icon: const Icon(Icons.schedule_rounded),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _checkInTime);
                    if (t != null) setState(() => _checkInTime = t);
                  },
                ),
              ),
              // Ketish vaqti
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Ketgan vaqti: ${_checkOutTime.format(context)}'),
                value: _hasCheckOut,
                onChanged: (v) => setState(() => _hasCheckOut = v ?? false),
                secondary: IconButton(
                  icon: const Icon(Icons.schedule_rounded),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _checkOutTime);
                    if (t != null) setState(() => _checkOutTime = t);
                  },
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Davomat holati'),
                items: const [
                  DropdownMenuItem(value: 'present', child: Text('✓ Kelgan (Vaqtida)')),
                  DropdownMenuItem(value: 'late', child: Text('⚠ Kechikkan')),
                  DropdownMenuItem(value: 'half_day', child: Text('⏱ Yarim kun')),
                  DropdownMenuItem(value: 'absent', child: Text('✕ Kelmagan')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'present'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Izoh / Sababi',
                  hintText: 'masalan: Navbatchilikda bo‘ldi, ruxsat olgan...',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bekor')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.neonLime,
            foregroundColor: AppColors.ink,
          ),
          child: const Text('Saqlash', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}


// ---------------------------------------------------------------------------
// Ish vaqti va Davomat sozlamalari dialogi (ShiftConfigDialog)
// ---------------------------------------------------------------------------

class ShiftConfigDialog extends StatefulWidget {
  final AttendanceRepository repo;
  const ShiftConfigDialog({super.key, required this.repo});

  static Future<bool?> show(BuildContext context, AttendanceRepository repo) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ShiftConfigDialog(repo: repo),
    );
  }

  @override
  State<ShiftConfigDialog> createState() => _ShiftConfigDialogState();
}

class _ShiftConfigDialogState extends State<ShiftConfigDialog> {
  bool _loading = true;
  bool _saving = false;

  String _startTime = '09:00';
  String _endTime = '18:00';
  int _dailyHours = 8;
  int _graceMinutes = 10;
  bool _minutePenalty = true;
  bool _overtimeEnabled = true;
  bool _autoCheckout = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await widget.repo.getShiftConfig();
      if (mounted) {
        setState(() {
          _startTime = (cfg['start_time'] ?? '09:00').toString();
          _endTime = (cfg['end_time'] ?? '18:00').toString();
          _dailyHours = (cfg['daily_hours'] as num?)?.toInt() ?? 8;
          _graceMinutes = (cfg['grace_minutes'] as num?)?.toInt() ?? 10;
          _minutePenalty = cfg['minute_penalty'] as bool? ?? true;
          _overtimeEnabled = cfg['overtime_enabled'] as bool? ?? true;
          _autoCheckout = cfg['auto_checkout'] as bool? ?? true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final curParts = (isStart ? _startTime : _endTime).split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(curParts[0]) ?? (isStart ? 9 : 18),
      minute: int.tryParse(curParts[1]) ?? 0,
    );

    final res = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? 'Smena boshlanish vaqti' : 'Smena tugash vaqti',
      cancelText: 'Bekor',
      confirmText: 'Tanlash',
    );
    if (res != null) {
      final h = res.hour.toString().padLeft(2, '0');
      final m = res.minute.toString().padLeft(2, '0');
      setState(() {
        if (isStart) {
          _startTime = '$h:$m';
        } else {
          _endTime = '$h:$m';
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repo.updateShiftConfig({
        'start_time': _startTime,
        'end_time': _endTime,
        'daily_hours': _dailyHours,
        'grace_minutes': _graceMinutes,
        'minute_penalty': _minutePenalty,
        'overtime_enabled': _overtimeEnabled,
        'auto_checkout': _autoCheckout,
      });
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Xatolik: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Dialog(
      backgroundColor: context.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: _loading
              ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sarlavha
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.neonLime.withValues(alpha: 0.15) : const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.more_time_rounded,
                            size: 20,
                            color: isDark ? AppColors.neonLime : const Color(0xFF0284C7),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ish vaqti sozlamalari',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color: context.inkColor,
                                ),
                              ),
                              Text(
                                'Smena vaqtlari, jarima va avtomatlashtirish',
                                style: TextStyle(fontSize: 11.5, color: context.mutedColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                          splashRadius: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Smena boshlanish va tugash vaqti
                            Text(
                              'Smena vaqtlari:',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.inkColor),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _pickTime(isStart: true),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: context.pillColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: context.borderColor),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.login_rounded, size: 16, color: isDark ? AppColors.neonLime : const Color(0xFF16A34A)),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Ish boshlanishi', style: TextStyle(fontSize: 10, color: context.mutedColor, fontWeight: FontWeight.w600)),
                                              Text(_startTime, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: context.inkColor)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _pickTime(isStart: false),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: context.pillColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: context.borderColor),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.logout_rounded, size: 16, color: isDark ? AppColors.neonLime : const Color(0xFFD97706)),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Ish tugashi', style: TextStyle(fontSize: 10, color: context.mutedColor, fontWeight: FontWeight.w600)),
                                              Text(_endTime, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: context.inkColor)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 2. Kunlik ish soati va Kechikish chegarasi
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: context.pillColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: context.borderColor),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Kunlik ish normasi', style: TextStyle(fontSize: 10, color: context.mutedColor, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text('$_dailyHours soat', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: context.inkColor)),
                                            const Spacer(),
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: _dailyHours > 4 ? () => setState(() => _dailyHours--) : null,
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: _dailyHours < 16 ? () => setState(() => _dailyHours++) : null,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: context.pillColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: context.borderColor),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Ruxsat etilgan kechikish', style: TextStyle(fontSize: 10, color: context.mutedColor, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text('$_graceMinutes daq', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: context.inkColor)),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: _graceMinutes > 0 ? () => setState(() => _graceMinutes -= 5) : null,
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: _graceMinutes < 60 ? () => setState(() => _graceMinutes += 5) : null,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 3. Qoidalar (Switches)
                            Text(
                              'Hisob-kitob va Avtomatlashtirish qoidalari:',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.inkColor),
                            ),
                            const SizedBox(height: 8),

                            // Switch 1: Minutbay jarima
                            _buildRuleSwitch(
                              icon: Icons.timer_off_rounded,
                              iconColor: AppColors.danger,
                              title: 'Kech qolsa minutiga qarab jarima',
                              subtitle: 'Har bir kechikkan minut uchun oylikdan minutlik stavka bo‘yicha chegiriladi',
                              value: _minutePenalty,
                              onChanged: (v) => setState(() => _minutePenalty = v),
                            ),
                            const SizedBox(height: 8),

                            // Switch 2: Overtime (ko'p ishlasa ish haqi qo'shiladi)
                            _buildRuleSwitch(
                              icon: Icons.more_time_rounded,
                              iconColor: const Color(0xFF10B981),
                              title: 'Ko‘p ishlasa ish haqi qo‘shilsin',
                              subtitle: 'Kunlik standart soatdan ($_dailyHours soat) ortiq ishlangan vaqt uchun qo‘shimcha oylik hisoblanadi',
                              value: _overtimeEnabled,
                              onChanged: (v) => setState(() => _overtimeEnabled = v),
                            ),
                            const SizedBox(height: 8),

                            // Switch 3: Avtomatik ketdi qilish (18:00)
                            _buildRuleSwitch(
                              icon: Icons.auto_mode_rounded,
                              iconColor: const Color(0xFF3B82F6),
                              title: 'Ketdi qilinmasa avtomatik ketdi qilish',
                              subtitle: 'Agar xodim ketishni belgilamasa, smena tugash vaqtida ($_endTime) avtomatik smena yopiladi',
                              value: _autoCheckout,
                              onChanged: (v) => setState(() => _autoCheckout = v),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Tugmalar
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text('Bekor qilish', style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
                              foregroundColor: isDark ? AppColors.ink : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Saqlash', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildRuleSwitch({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.pillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.inkColor)),
                const SizedBox(height: 1),
                Text(subtitle, style: TextStyle(fontSize: 10, color: context.mutedColor)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: context.isDark ? AppColors.neonLime : AppColors.darkCard,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}


/// Xodimga oylik hisobida Mukofot (Bonus / Premiya) berish dialogi
class EmployeeBonusDialog extends StatefulWidget {
  final SalaryReportItem item;
  final String month;
  final AppRepositories repos;

  const EmployeeBonusDialog({
    super.key,
    required this.item,
    required this.month,
    required this.repos,
  });

  static Future<bool?> show(
    BuildContext context, {
    required SalaryReportItem item,
    required String month,
    required AppRepositories repos,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmployeeBonusDialog(
        item: item,
        month: month,
        repos: repos,
      ),
    );
  }

  @override
  State<EmployeeBonusDialog> createState() => _EmployeeBonusDialogState();
}

class _EmployeeBonusDialogState extends State<EmployeeBonusDialog> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _amountCtrl.text.replaceAll(' ', '').trim();
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Iltimos, noldan katta to‘g‘ri summa kiriting');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final reason = _reasonCtrl.text.trim();
      final reasonPart = reason.isNotEmpty ? ' — $reason' : '';
      final note = 'Mukofot: ${widget.item.fullName} (${widget.month})$reasonPart';

      bool saved = false;
      try {
        await widget.repos.attendance.addBonus(
          widget.item.userId,
          widget.month,
          amount,
          reason: reason.isEmpty ? null : reason,
        );
        saved = true;
      } catch (_) {
        saved = false;
      }

      // Agar /attendance/add-bonus 404 bersa, jonli ishlaydigan moliya chiqimlari orqali 100% kafolatli saqlash
      if (!saved) {
        await widget.repos.finance.addTransaction(
          FinanceTransaction(
            id: 0,
            type: 'expense',
            category: 'Mukofot / Bonus',
            amount: amount,
            paymentMethod: 'cash',
            note: note,
            date: DateTime.now(),
          ),
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Saqlashda xatolik: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final r = widget.item;

    return Dialog(
      backgroundColor: context.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sarlavha
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.card_giftcard_rounded, size: 22, color: Color(0xFFD97706)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mukofot (Bonus) berish',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: context.inkColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${r.fullName} · ${widget.month} oyi uchun',
                          style: TextStyle(fontSize: 12, color: context.mutedColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Yopish',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Status paneli: Ishlagan qismi, Mavjud mukofot, To'lanadigan sof maosh
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.pillColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('Ishlagani', style: TextStyle(fontSize: 10.5, color: context.mutedColor, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(money(r.calculatedSalary), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.inkColor)),
                      ],
                    ),
                    Container(height: 24, width: 1, color: context.borderColor),
                    Column(
                      children: [
                        Text('Mukofoti', style: const TextStyle(fontSize: 10.5, color: Color(0xFFD97706), fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('+${money(r.bonus)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
                      ],
                    ),
                    Container(height: 24, width: 1, color: context.borderColor),
                    Column(
                      children: [
                        Text('Sof maosh', style: const TextStyle(fontSize: 10.5, color: Color(0xFF10B981), fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(money(r.remainingSalary > 0 ? r.remainingSalary : r.netSalary), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Mukofot summasi kiritish (Zero taxminiy narxlar!)
              Text(
                'Mukofot miqdori:',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.inkColor),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: context.inkColor),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.add_rounded, color: Color(0xFFD97706), size: 20),
                  suffixText: "so'm",
                  suffixStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor),
                  hintText: 'Summani kiriting',
                  filled: true,
                  fillColor: context.pillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.8)),
                ),
              ),
              const SizedBox(height: 14),

              // Sababi / Izoh
              Text(
                'Izoh yoki sababi (ixtiyoriy):',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.inkColor),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                style: TextStyle(fontSize: 13, color: context.inkColor),
                decoration: InputDecoration(
                  hintText: 'Masalan: Yaxshi ishlagani uchun, bayram mukofoti',
                  hintStyle: TextStyle(fontSize: 12, color: context.mutedColor),
                  filled: true,
                  fillColor: context.pillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.8)),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger),
                ),
              ],
              const SizedBox(height: 20),

              // Pastki amallar
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Bekor qilish', style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text(_saving ? 'Saqlanmoqda...' : 'Mukofotni saqlash', style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
