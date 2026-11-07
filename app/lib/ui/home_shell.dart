import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import '../state/app_lock_controller.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import 'common.dart';
import 'currency_badge.dart';
import 'pin_lock_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'debts_screen.dart';
import 'deliveries_screen.dart';
import 'finance_screen.dart';
import 'orders_screen.dart';
import 'pos_screen.dart';
import 'production_screen.dart';
import 'products_screen.dart';
import 'purchases_screen.dart';
import 'sales_history_screen.dart';
import 'stock_screen.dart';
import 'stone_services_dialog.dart';
import 'users_screen.dart';

class _Dest {
  final String label;
  final IconData icon;
  final Widget Function() build;
  final bool isGeneral;
  final String actionLabel;
  const _Dest(this.label, this.icon, this.build,
      {this.isGeneral = false, this.actionLabel = 'Qo‘shish'});
}

List<_Dest> _destinationsFor(Role role,
    {void Function(int index)? onNavigate, AppUser? currentUser}) {
  final dash = _Dest('Asosiy oyna', Icons.grid_view_rounded,
      () => DashboardScreen(onNavigate: onNavigate),
      actionLabel: '+ Yangi Savdo');
  const pos = _Dest('Savdo (POS)', Icons.point_of_sale_rounded, PosScreen.new,
      actionLabel: 'Savdoga o‘tish');
  final orders = _Dest(
    'Buyurtmalar',
    Icons.assignment_rounded,
    () => OrdersScreen(onNewOrder: () {
      final posIdx = role == Role.admin ? 1 : 0;
      onNavigate?.call(posIdx);
    }),
    actionLabel: '+ Yangi Buyurtma',
  );
  final deliveries = _Dest(
    role == Role.haydovchi ? 'Mening Yetkazmalarim' : 'Yetkazib berish',
    Icons.local_shipping_rounded,
    () => DeliveriesScreen(currentUser: currentUser),
    actionLabel: role == Role.haydovchi ? 'Mening yetkazmalarim' : '+ Yangi Yetkazish',
  );
  const salesHistory = _Dest(
    'Savdolar',
    Icons.receipt_long_rounded,
    SalesHistoryScreen.new,
    actionLabel: 'Savdolar jurnali',
  );
  const customers = _Dest(
    'Mijozlar',
    Icons.people_alt_rounded,
    CustomersScreen.new,
    actionLabel: '+ Yangi Mijoz',
  );
  const debts = _Dest(
      'Nasiyalar', Icons.pending_actions_rounded, DebtsScreen.new,
      actionLabel: 'Qarz undirish');
  const purchases = _Dest(
    'Xaridlar',
    Icons.shopping_bag_rounded,
    PurchasesScreen.new,
    actionLabel: '+ Yangi Xarid',
  );
  const finance = _Dest(
    'Moliya',
    Icons.account_balance_wallet_rounded,
    FinanceScreen.new,
    actionLabel: '+ Chiqim / Kirim',
  );
  const products = _Dest(
      'Mahsulotlar', Icons.inventory_2_rounded, ProductsScreen.new,
      actionLabel: '+ Mahsulot');
  const stock = _Dest('Ombor', Icons.warehouse_rounded, StockScreen.new,
      actionLabel: '+ Xarid kirimi');
  final isManager = role == Role.admin || role == Role.ishBoshqaruvchi;
  final prod = _Dest(
    'Ishlab chiqarish',
    Icons.precision_manufacturing_rounded,
    ProductionScreen.new,
    actionLabel: isManager ? '+ Topshiriq' : '',
  );
  const staff = _Dest('Xodimlar', Icons.badge_rounded, UsersScreen.new,
      isGeneral: true, actionLabel: '+ Xodim');
  final cams = _Dest(
      'Kameralar',
      Icons.videocam_rounded,
      () => const NotImplementedView(
          title: 'Kameralar',
          note: 'IP-kamera / DVR oqimlari keyingi bosqichda ulanadi.'),
      isGeneral: true,
      actionLabel: 'Sozlash');

  switch (role) {
    case Role.admin:
      return [
        dash,
        pos,
        orders,
        deliveries,
        salesHistory,
        customers,
        debts,
        purchases,
        finance,
        products,
        stock,
        prod,
        staff,
        cams
      ];
    case Role.kassir:
      return [pos, orders, deliveries, salesHistory, customers, debts, purchases, finance, products];
    case Role.ishBoshqaruvchi:
      return [prod, stock];
    case Role.ishchi:
      return [prod];
    case Role.haydovchi:
      return [deliveries, orders];
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.user});
  final AppUser user;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _refreshKey = 0;
  final _searchCtrl = TextEditingController();
  List<AppNotification> _notifications = [];
  Timer? _notifTimer;
  bool _isSearchOpen = false;
  bool _sidebarOpen = true;

  void _toggleSidebar() {
    setState(() {
      _sidebarOpen = !_sidebarOpen;
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotifications();
      _checkPinSetup();
    });
    _notifTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadNotifications();
    });
  }

  void _checkPinSetup() {
    AppLockController? appLock;
    try {
      appLock = Provider.of<AppLockController>(context, listen: false);
    } catch (_) {}
    if (appLock == null) return;
    if (!appLock.hasPin && mounted) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.isDark ? const Color(0xFF161F2E) : const Color(0xFF1E293B),
            content: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.neonLime, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Xavfsizlik: Har gal kirganda so‘raladigan shaxsiy PIN kod (ilova qulfi) o‘rnating',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'O‘rnatish',
              textColor: AppColors.neonLime,
              onPressed: () => PinSetupDialog.show(context, widget.user),
            ),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      });
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isMeta = HardwareKeyboard.instance.isMetaPressed;
      final isCtrl = HardwareKeyboard.instance.isControlPressed;
      if (isMeta || isCtrl) {
        if (event.logicalKey == LogicalKeyboardKey.keyK) {
          if (!_isSearchOpen && mounted) {
            _openGlobalSearch();
          }
          return true;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyB) {
          if (mounted) {
            _toggleSidebar();
          }
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _loadNotifications() async {
    try {
      final repos = context.read<AppRepositories>();
      final list = await repos.notifications.list(limit: 50);
      if (mounted) {
        setState(() {
          _notifications = list;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _notifTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onAction(String label) async {
    final dests = _destinationsFor(widget.user.role, onNavigate: (i) {
      setState(() {
        _index = i;
      });
    }, currentUser: widget.user);
    final cur = dests[_index];
    final repos = context.read<AppRepositories>();

    if (cur.label == 'Asosiy oyna' || cur.label == 'Dashboard') {
      // Savdo (POS) ga o'tish
      final posIndex = dests.indexWhere((d) => d.label.startsWith('Savdo'));
      if (posIndex >= 0) {
        setState(() {
          _index = posIndex;
        });
      }
    } else if (cur.label.startsWith('Savdo')) {
      showMessage(
          context, 'Kassa faol. Mahsulotni tanlang yoki kodini skaner qiling.');
    } else if (cur.label == 'Buyurtmalar') {
      final posIndex = dests.indexWhere((d) => d.label.startsWith('Savdo'));
      if (posIndex >= 0) {
        setState(() => _index = posIndex);
        showMessage(context,
            'Yangi buyurtma uchun mahsulotlarni tanlang va to‘lov oynasida "Buyurtma"ni belgilang.');
      }
    } else if (cur.label == 'Mijozlar') {
      final updated = await showDialog<bool>(
        context: context,
        builder: (_) => const CustomerDialog(),
      );
      if (updated == true && mounted) {
        setState(() => _refreshKey++);
      }
    } else if (cur.label == 'Nasiyalar') {
      final debts = await repos.sales.listDebts();
      if (!mounted) return;
      if (debts.isEmpty) {
        showMessage(
            context, 'Hozircha undirilishi kerak bo‘lgan qarzdorliklar yo‘q');
        return;
      }

      final selected = debts.length == 1
          ? debts.first
          : await showDialog<SaleResult>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: context.dialogBg,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
                title: const Text('Qarz undirish: Mijozni tanlang',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                content: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final d in debts)
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            leading: CircleAvatar(
                              backgroundColor: context.isDark
                                  ? const Color(0xFF2C2210)
                                  : const Color(0xFFFFF1DC),
                              child: Text(
                                d.customerName?.isNotEmpty == true
                                    ? d.customerName![0].toUpperCase()
                                    : '#',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: context.isDark
                                      ? const Color(0xFFFFB03A)
                                      : const Color(0xFFC77700),
                                ),
                              ),
                            ),
                            title: Text(d.customerName ?? 'Mijoz #${d.id}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: context.inkColor)),
                            subtitle: Text('Qarz: ${money(d.debt)}'),
                            trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14),
                            onTap: () => Navigator.pop(ctx, d),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Bekor')),
                ],
              ),
            );

      if (selected != null && mounted) {
        final ctrl =
            TextEditingController(text: selected.debt.round().toString());
        String method = 'cash';
        String? error;
        bool busy = false;

        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              backgroundColor: context.dialogBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22)),
              title: Text(
                'Qarz to‘lovi: ${selected.customerName ?? 'Savdo #${selected.id}'}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? const Color(0xFF2C2210)
                            : const Color(0xFFFFF1DC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: [
                        Icon(Icons.pending_actions_rounded,
                            color: context.isDark
                                ? const Color(0xFFFFB03A)
                                : const Color(0xFFC77700)),
                        const SizedBox(width: 10),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Qoldiq qarz',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.muted)),
                              Text(
                                money(selected.debt),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: context.isDark
                                      ? const Color(0xFFFFB03A)
                                      : const Color(0xFFC77700),
                                ),
                              ),
                            ]),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'To‘lanayotgan summa'),
                      onChanged: (_) {
                        setS(() {
                          error = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: method,
                      decoration:
                          const InputDecoration(labelText: 'To‘lov usuli'),
                      items: const [
                        DropdownMenuItem(
                            value: 'cash', child: Text('Naqd pul')),
                        DropdownMenuItem(
                            value: 'card', child: Text('Bank kartasi')),
                        DropdownMenuItem(
                            value: 'transfer', child: Text('O‘tkazma')),
                      ],
                      onChanged: (v) {
                        setS(() {
                          method = v ?? 'cash';
                        });
                      },
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error!,
                            style: const TextStyle(
                                color: AppColors.danger, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: busy ? null : () => Navigator.pop(ctx, false),
                    child: const Text('Bekor')),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final val = parseInput(ctrl.text);
                          if (val == null || val <= 0) {
                            setS(() {
                              error = 'To‘lov summasini to‘g‘ri kiriting';
                            });
                            return;
                          }
                          if (val > selected.debt + 0.01) {
                            setS(() {
                              error =
                                  'To‘lov qarzdan ko‘p bo‘lishi mumkin emas';
                            });
                            return;
                          }
                          setS(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await repos.sales
                                .payDebt(selected.id, val, method: method);
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setS(() {
                              busy = false;
                              error = e.toString();
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: context.isDark
                        ? AppColors.neonLime
                        : AppColors.darkCard,
                    foregroundColor:
                        context.isDark ? AppColors.ink : Colors.white,
                  ),
                  child: busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.isDark
                                  ? AppColors.ink
                                  : Colors.white))
                      : const Text('Qabul qilish'),
                ),
              ],
            ),
          ),
        );
        ctrl.dispose();
        if (ok == true && mounted) {
          showMessage(context, 'Qarz to‘lovi muvaffaqiyatli saqlandi');
          setState(() {
            _refreshKey++;
          });
        }
      }
    } else if (cur.label == 'Moliya') {
      final saved = await FinanceTransactionDialog.show(context);
      if (saved == true && mounted) {
        showMessage(context, 'Moliya operatsiyasi muvaffaqiyatli saqlandi');
        setState(() {
          _refreshKey++;
        });
      }
    } else if (cur.label == 'Mahsulotlar') {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => ProductDialog(repo: repos.products),
      );
      if (saved == true && mounted) {
        showMessage(context, 'Yangi mahsulot saqlandi');
        setState(() {
          _refreshKey++;
        });
      }
    } else if (cur.label == 'Ombor') {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => StockPurchaseDialog(
          stockRepo: repos.stock,
          productRepo: repos.products,
        ),
      );
      if (saved == true && mounted) {
        showMessage(context, 'Yangi xarid kirimi saqlandi');
        setState(() {
          _refreshKey++;
        });
      }
    } else if (cur.label == 'Ishlab chiqarish') {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => TaskCreateDialog(
          productionRepo: repos.production,
          productRepo: repos.products,
        ),
      );
      if (saved == true && mounted) {
        showMessage(context, 'Yangi topshiriq biriktirildi');
        setState(() {
          _refreshKey++;
        });
      }
    } else if (cur.label == 'Xodimlar') {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => UserDialog(repo: repos.users),
      );
      if (saved == true && mounted) {
        showMessage(context, 'Yangi xodim qo‘shildi');
        setState(() {
          _refreshKey++;
        });
      }
    } else if (cur.label == 'Kameralar') {
      showMessage(
          context, 'IP-kamera / DVR oqimlari keyingi bosqichda ulanadi.');
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Hozirgina';
    if (diff.inMinutes < 60) return '${diff.inMinutes} daqiqa oldin';
    if (diff.inHours < 24) return '${diff.inHours} soat oldin';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showNotifications() async {
    await _loadNotifications();
    if (!mounted) return;
    final repos = context.read<AppRepositories>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final unreadList = _notifications.where((n) => !n.isRead).toList();

          return AlertDialog(
            backgroundColor: context.dialogBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active_rounded,
                        color: context.isDark
                            ? AppColors.neonLime
                            : AppColors.ink),
                    const SizedBox(width: 10),
                    Text('Bildirishnomalar',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: context.inkColor)),
                  ],
                ),
                if (unreadList.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      await repos.notifications.markAllRead();
                      await _loadNotifications();
                      setDialogState(() {});
                    },
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Barchasini o‘qish',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            content: SizedBox(
              width: 420,
              height: 380,
              child: _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_off_outlined,
                              size: 40, color: context.mutedColor),
                          const SizedBox(height: 12),
                          Text('Hozircha bildirishnomalar yo‘q',
                              style: TextStyle(
                                  color: context.mutedColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 12, color: context.borderColor),
                      itemBuilder: (ctx, i) {
                        final n = _notifications[i];
                        Color color = AppColors.green;
                        IconData icon = Icons.info_outline_rounded;
                        if (n.kind == 'warning') {
                          color = const Color(0xFFC77700);
                          icon = Icons.inventory_2_outlined;
                        } else if (n.kind == 'payment') {
                          color = AppColors.green;
                          icon = Icons.payments_outlined;
                        } else if (n.kind == 'production') {
                          color = const Color(0xFF245580);
                          icon = Icons.precision_manufacturing_rounded;
                        } else if (n.kind == 'sale') {
                          color = const Color(0xFF10B981);
                          icon = Icons.shopping_bag_outlined;
                        }

                        return InkWell(
                          onTap: n.isRead
                              ? null
                              : () async {
                                  await repos.notifications.markRead(n.id);
                                  await _loadNotifications();
                                  setDialogState(() {});
                                },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: n.isRead
                                  ? Colors.transparent
                                  : (context.isDark
                                      ? AppColors.neonLime
                                          .withValues(alpha: 0.12)
                                      : AppColors.neonLimeSoft
                                          .withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: n.isRead
                                    ? Colors.transparent
                                    : AppColors.neonLime.withValues(
                                        alpha: context.isDark ? 0.35 : 0.45),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(icon, color: color, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              n.title,
                                              style: TextStyle(
                                                fontWeight: n.isRead
                                                    ? FontWeight.w600
                                                    : FontWeight.w800,
                                                fontSize: 13,
                                                color: context.inkColor,
                                              ),
                                            ),
                                          ),
                                          if (!n.isRead)
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: const BoxDecoration(
                                                color: AppColors.green,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        n.message,
                                        style: TextStyle(
                                            color: context.mutedColor,
                                            fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatTimeAgo(n.createdAt),
                                        style: TextStyle(
                                            color: context.mutedColor,
                                            fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      context.isDark ? AppColors.neonLime : AppColors.darkCard,
                  foregroundColor:
                      context.isDark ? AppColors.ink : Colors.white,
                ),
                child: const Text('Yopish'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openGlobalSearch() {
    if (_isSearchOpen) return;
    _isSearchOpen = true;

    final dests = _destinationsFor(widget.user.role, onNavigate: (i) {
      setState(() {
        _index = i;
      });
    }, currentUser: widget.user);

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _GlobalSearchDialog(
        dests: dests,
        userRole: widget.user.role,
        onNavigate: (destLabel, {String? filterQuery}) {
          final idx = dests.indexWhere(
              (d) => d.label.toLowerCase().startsWith(destLabel.toLowerCase()));
          if (idx >= 0) {
            setState(() {
              _index = idx;
              if (filterQuery != null && filterQuery.isNotEmpty) {
                _searchCtrl.text = filterQuery;
              }
            });
          }
        },
      ),
    ).whenComplete(() {
      _isSearchOpen = false;
    });
  }

  void _openSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _SettingsBottomSheet(user: widget.user),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dests = _destinationsFor(widget.user.role, onNavigate: (i) {
      setState(() {
        _index = i;
      });
    }, currentUser: widget.user);
    if (_index >= dests.length) _index = 0;

    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 940;
    final body = KeyedSubtree(
      key: ValueKey('${dests[_index].label}_$_refreshKey'),
      child: dests[_index].build(),
    );

    void logout() => context.read<AuthController>().logout();
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppColors.sidebar,
        body: Row(
          children: [
            // Chap Tomondagi "Vault" uslubidagi qora panel (ochib-yopiladigan)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              width: _sidebarOpen ? 250 : 0,
              child: ClipRect(
                child: OverflowBox(
                  minWidth: 250,
                  maxWidth: 250,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 250,
                    child: _VaultSidebar(
                      dests: dests,
                      index: _index,
                      user: widget.user,
                      onSelect: (i) {
                        setState(() {
                          _index = i;
                        });
                      },
                      onLogout: logout,
                      onOpenSettings: _openSettingsBottomSheet,
                    ),
                  ),
                ),
              ),
            ),

            // Asosiy och rangli boshqaruv paneli
            Expanded(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                padding: EdgeInsets.fromLTRB(_sidebarOpen ? 0 : 10, 10, 10, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Column(
                      children: [
                        _VaultHeader(
                          title: dests[_index].label,
                          user: widget.user,
                          searchCtrl: _searchCtrl,
                          actionLabel: dests[_index].actionLabel,
                          unreadCount: unreadCount,
                          sidebarOpen: _sidebarOpen,
                          onToggleSidebar: _toggleSidebar,
                          onActionPressed: () =>
                              _onAction(dests[_index].actionLabel),
                          onNotificationPressed: _showNotifications,
                          onSearchPressed: _openGlobalSearch,
                          onSettingsPressed: _openSettingsBottomSheet,
                        ),
                        Expanded(child: body),
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

    final isDashboard = dests[_index].label == 'Asosiy oyna' ||
        dests[_index].label == 'Dashboard';

    // Mobil va planshet ekrani
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: isDashboard
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.neonLime,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.token_rounded,
                        color: AppColors.ink, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      dests[_index].label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              )
            : Text(
                dests[_index].label,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
        actions: [
          const Center(child: CurrencyBadge(isCompact: true)),
          const SizedBox(width: 4),
          if (dests[_index].label.startsWith('Savdo')) ...[
            IconButton(
              tooltip: 'Xizmatlar (kesish, faska, silliqlash, chizish)',
              icon: const Icon(Icons.design_services_rounded, size: 22),
              onPressed: () =>
                  StoneServicesDialog.show(context, user: widget.user),
            ),
          ],
          if (isDashboard) ...[
            IconButton(
              tooltip: 'Tizim bo‘yicha qidiruv',
              icon: const Icon(Icons.search_rounded, size: 22),
              onPressed: _openGlobalSearch,
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Bildirishnomalar',
                  icon: const Icon(Icons.notifications_none_rounded, size: 22),
                  onPressed: _showNotifications,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppColors.sidebar,
        child: SafeArea(
          child: _VaultSidebar(
            dests: dests,
            index: _index,
            user: widget.user,
            onSelect: (i) {
              setState(() {
                _index = i;
              });
              Navigator.pop(context);
            },
            onLogout: logout,
            onOpenSettings: () {
              Navigator.pop(context);
              _openSettingsBottomSheet();
            },
          ),
        ),
      ),
      bottomNavigationBar: dests.length > 1 && dests.length <= 5
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) {
                setState(() {
                  _index = i;
                });
              },
              backgroundColor: context.cardColor,
              indicatorColor: context.isDark
                  ? AppColors.neonLime.withValues(alpha: 0.25)
                  : AppColors.neonLimeSoft,
              destinations: [
                for (final d in dests)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    label: d.label,
                  ),
              ],
            )
          : null,
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Vault Yuqori Header Bar
// ---------------------------------------------------------------------------

class _VaultHeader extends StatelessWidget {
  const _VaultHeader({
    required this.title,
    required this.user,
    required this.searchCtrl,
    required this.actionLabel,
    required this.unreadCount,
    required this.onActionPressed,
    required this.onNotificationPressed,
    required this.onSearchPressed,
    required this.onSettingsPressed,
    this.sidebarOpen = true,
    this.onToggleSidebar,
  });

  final String title;
  final AppUser user;
  final TextEditingController searchCtrl;
  final String actionLabel;
  final int unreadCount;
  final VoidCallback onActionPressed;
  final VoidCallback onNotificationPressed;
  final VoidCallback onSearchPressed;
  final VoidCallback onSettingsPressed;
  final bool sidebarOpen;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    final isDashboard = title == 'Asosiy oyna' || title == 'Dashboard';
    final isPos = title.startsWith('Savdo');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 14),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Chap tomon: Menyuni ochish/yopish, Sahifa nomi va Valyuta kursi
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onToggleSidebar != null) ...[
                  _HeaderIconBtn(
                    icon: sidebarOpen
                        ? Icons.menu_open_rounded
                        : Icons.menu_rounded,
                    tooltip: sidebarOpen
                        ? 'Menyuni yopish (Ctrl+B)'
                        : 'Menyuni ochish (Ctrl+B)',
                    onTap: onToggleSidebar!,
                  ),
                  const SizedBox(width: 14),
                ],
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : AppColors.ink,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const CurrencyBadge(),
              ],
            ),
          ),

          if (isDashboard) ...[
            const SizedBox(width: 16),
            // O'ng tomon: Qidiruv paneli, Bildirishnoma va Sozlamalar
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Qidiruv paneli (Vault oval shape)
                SizedBox(
                  width: 220,
                  child: InkWell(
                    onTap: onSearchPressed,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: isDark
                                ? const Color(0xFF282D34)
                                : AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.search_rounded,
                              size: 18, color: AppColors.muted),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Qidirish...',
                              style: TextStyle(
                                  fontSize: 12.5, color: AppColors.muted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _SearchKeyBadge(),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Bildirishnoma (qo'ng'iroqcha)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _HeaderIconBtn(
                      icon: Icons.notifications_none_rounded,
                      onTap: onNotificationPressed,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                width: 1.5),
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 10),

                // Sozlamalar tugmasi
                _HeaderIconBtn(
                  icon: Icons.settings_outlined,
                  onTap: onSettingsPressed,
                ),
              ],
            ),
          ],

          if (isPos) ...[
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () => StoneServicesDialog.show(context, user: user),
              icon: const Icon(Icons.design_services_rounded, size: 18),
              label: const Text(
                'Xizmatlar',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    isDark ? const Color(0xFF232832) : const Color(0xFFF1F5F9),
                foregroundColor: isDark ? AppColors.neonLime : AppColors.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF282D34) : AppColors.border,
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  const _HeaderIconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        shape: BoxShape.circle,
        border: Border.all(
            color: isDark ? const Color(0xFF282D34) : AppColors.border),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon:
            Icon(icon, size: 19, color: isDark ? Colors.white : AppColors.ink),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vault Yon Sidebar Paneli
// ---------------------------------------------------------------------------

class _VaultSidebar extends StatelessWidget {
  const _VaultSidebar({
    required this.dests,
    required this.index,
    required this.user,
    required this.onSelect,
    required this.onLogout,
    required this.onOpenSettings,
  });

  final List<_Dest> dests;
  final int index;
  final AppUser user;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final menuItems = <int>[];
    final generalItems = <int>[];

    for (int i = 0; i < dests.length; i++) {
      if (dests[i].isGeneral) {
        generalItems.add(i);
      } else {
        menuItems.add(i);
      }
    }

    final initial =
        user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & Brend
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.neonLime,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.token_rounded,
                        color: AppColors.ink, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NTJ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    Text(
                      'Namuna Tosh Jilo',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF8E959E),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Scrollable nav items so it NEVER overflows on any desktop screen height
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 10, bottom: 8),
                    child: Text(
                      'MENU',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  for (final i in menuItems)
                    _VaultNavItem(
                      dest: dests[i],
                      selected: i == index,
                      onTap: () => onSelect(i),
                    ),
                  if (generalItems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.only(left: 10, bottom: 8),
                      child: Text(
                        'GENERAL',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    for (final i in generalItems)
                      _VaultNavItem(
                        dest: dests[i],
                        selected: i == index,
                        onTap: () => onSelect(i),
                      ),
                    _VaultNavItem(
                      dest: const _Dest(
                          'Sozlamalar', Icons.settings_rounded, SizedBox.shrink,
                          isGeneral: true),
                      selected: false,
                      onTap: onOpenSettings,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Status / Pro Karta
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2125),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2B3037)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.neonLime,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded,
                      color: AppColors.ink, size: 17),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NTM PRO',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Tizim barqaror faol',
                        style:
                            TextStyle(color: Color(0xFF8E959E), fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Foydalanuvchi profili qatori
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF191C1F),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.neonLime,
                  child: Text(
                    initial,
                    style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        user.role.label,
                        style: const TextStyle(
                            color: Color(0xFF8E959E), fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ilovani qulflash',
                  icon: const Icon(Icons.lock_outline_rounded,
                      color: Color(0xFF8E959E), size: 18),
                  onPressed: () {
                    AppLockController? appLock;
                    try {
                      appLock = Provider.of<AppLockController>(context, listen: false);
                    } catch (_) {}
                    if (appLock == null) return;
                    if (!appLock.hasPin) {
                      PinSetupDialog.show(context, user);
                    } else {
                      appLock.lockNow();
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Sozlamalar',
                  icon: const Icon(Icons.settings_outlined,
                      color: Color(0xFF8E959E), size: 18),
                  onPressed: onOpenSettings,
                ),
                IconButton(
                  tooltip: 'Chiqish',
                  icon: const Icon(Icons.logout_rounded,
                      color: Color(0xFF8E959E), size: 18),
                  onPressed: onLogout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vault Nav Item (Left neon-lime vertical indicator pill)
// ---------------------------------------------------------------------------

class _VaultNavItem extends StatelessWidget {
  const _VaultNavItem({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? const Color(0xFF1E2125) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          mouseCursor: SystemMouseCursors.click,
          onTap: onTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.neonLime : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  dest.icon,
                  size: 19,
                  color:
                      selected ? AppColors.neonLime : const Color(0xFF8E959E),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dest.label,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF8E959E),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
// Tizim bo'yicha global qidiruv komponentlari
// ---------------------------------------------------------------------------

class _SearchKeyBadge extends StatelessWidget {
  const _SearchKeyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color:
            context.isDark ? const Color(0xFF282828) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: context.isDark
              ? const Color(0xFF383838)
              : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.window_rounded, size: 11, color: context.mutedColor),
          const SizedBox(width: 3),
          Text('Win + K',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: context.mutedColor)),
        ],
      ),
    );
  }
}

class _GlobalItem {
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String destLabel;
  final String? filterQuery;

  const _GlobalItem({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.destLabel,
    this.filterQuery,
  });
}

class _GlobalSearchDialog extends StatefulWidget {
  final List<_Dest> dests;
  final Role userRole;
  final void Function(String destLabel, {String? filterQuery}) onNavigate;

  const _GlobalSearchDialog({
    required this.dests,
    required this.userRole,
    required this.onNavigate,
  });

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  String _selectedCategory = 'Barchasi';

  List<Product> _products = [];
  List<SaleResult> _debts = [];
  List<SaleResult> _sales = [];
  List<ProductionTask> _tasks = [];
  List<AppUser> _users = [];
  List<_GlobalItem> _allItems = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_filter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _fetchData();
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_filter);
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      final repos = context.read<AppRepositories>();
      final fProducts = repos.products.list().catchError((_) => <Product>[]);
      final fDebts = repos.sales.listDebts().catchError((_) => <SaleResult>[]);
      final fSales =
          repos.sales.listSales(limit: 50).catchError((_) => <SaleResult>[]);
      final fTasks =
          repos.production.list().catchError((_) => <ProductionTask>[]);
      final fUsers = (widget.userRole == Role.admin)
          ? repos.users.list().catchError((_) => <AppUser>[])
          : Future.value(<AppUser>[]);

      final results =
          await Future.wait([fProducts, fDebts, fSales, fTasks, fUsers]);
      if (!mounted) return;
      _products = results[0] as List<Product>;
      _debts = results[1] as List<SaleResult>;
      _sales = results[2] as List<SaleResult>;
      _tasks = results[3] as List<ProductionTask>;
      _users = results[4] as List<AppUser>;
      _filter();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final items = <_GlobalItem>[];

    // 1. Bo'limlar
    for (final d in widget.dests) {
      final labelLower = d.label.toLowerCase();
      if (q.isEmpty ||
          labelLower.contains(q) ||
          (labelLower.startsWith('savdo') &&
              (q.contains('pos') || q.contains('kassa'))) ||
          (labelLower.startsWith('nasiya') && q.contains('qarz')) ||
          (labelLower.startsWith('ishlab') && q.contains('ish'))) {
        items.add(_GlobalItem(
          title: d.label,
          subtitle: 'Tizim bo‘limiga o‘tish',
          category: 'Bo‘lim',
          icon: d.icon,
          iconColor: AppColors.ink,
          iconBg: AppColors.neonLimeSoft,
          destLabel: d.label,
        ));
      }
    }

    // 2. Mahsulotlar
    for (final p in _products) {
      if (p.isService) continue;
      if (q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.qrCode.toLowerCase().contains(q)) {
        items.add(_GlobalItem(
          title: p.name,
          subtitle: 'Qoldiq: ${p.stock} ${p.unit} • Narxi: ${money(p.price)}',
          category: 'Mahsulot',
          icon: Icons.inventory_2_rounded,
          iconColor: const Color(0xFF2563EB),
          iconBg: const Color(0xFFEFF6FF),
          destLabel: 'Mahsulotlar',
          filterQuery: p.name,
        ));
      }
    }

    // 3. Nasiyalar
    for (final s in _debts) {
      final name = (s.customerName ?? '').toLowerCase();
      final phone = (s.customerPhone ?? '').toLowerCase();
      if (q.isEmpty ||
          name.contains(q) ||
          phone.contains(q) ||
          s.id.toString() == q) {
        items.add(_GlobalItem(
          title: s.customerName ?? 'Mijoz #${s.id}',
          subtitle:
              'Qarz: ${money(s.debt)}${s.customerPhone?.isNotEmpty == true ? ' • ${s.customerPhone}' : ''}',
          category: 'Nasiya',
          icon: Icons.pending_actions_rounded,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFFFBEB),
          destLabel: 'Nasiyalar',
          filterQuery: s.customerName,
        ));
      }
    }

    // 4. Savdolar
    for (final s in _sales) {
      final name = (s.customerName ?? '').toLowerCase();
      if (q.isEmpty ||
          name.contains(q) ||
          s.id.toString() == q ||
          'savdo #${s.id}'.contains(q)) {
        items.add(_GlobalItem(
          title:
              'Savdo #${s.id} ${s.customerName?.isNotEmpty == true ? '(${s.customerName})' : ''}',
          subtitle: 'Jami: ${money(s.total)} • To‘langan: ${money(s.paid)}',
          category: 'Savdo',
          icon: Icons.point_of_sale_rounded,
          iconColor: const Color(0xFF059669),
          iconBg: const Color(0xFFECFDF5),
          destLabel: 'Savdo (POS)',
          filterQuery: s.customerName,
        ));
      }
    }

    // 5. Ishlab chiqarish
    for (final t in _tasks) {
      if (q.isEmpty ||
          t.productName.toLowerCase().contains(q) ||
          t.workerName.toLowerCase().contains(q) ||
          t.id.toString() == q) {
        items.add(_GlobalItem(
          title: '${t.productName} (${t.planned} ${t.unit})',
          subtitle:
              'Ishchi: ${t.workerName} • Tayyor: ${t.produced} • Holat: ${t.status == 'done' ? 'Bajarildi' : 'Jarayonda'}',
          category: 'Topshiriq',
          icon: Icons.precision_manufacturing_rounded,
          iconColor: const Color(0xFF7C3AED),
          iconBg: const Color(0xFFF5F3FF),
          destLabel: 'Ishlab chiqarish',
          filterQuery: t.productName,
        ));
      }
    }

    // 6. Xodimlar
    for (final u in _users) {
      if (q.isEmpty ||
          u.fullName.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q) ||
          u.role.label.toLowerCase().contains(q)) {
        items.add(_GlobalItem(
          title: u.fullName,
          subtitle: '@${u.username} • ${u.role.label}',
          category: 'Xodim',
          icon: Icons.badge_rounded,
          iconColor: const Color(0xFFDB2777),
          iconBg: const Color(0xFFFDF2F8),
          destLabel: 'Xodimlar',
          filterQuery: u.fullName,
        ));
      }
    }

    setState(() {
      _allItems = items;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      'Barchasi',
      'Bo‘lim',
      'Mahsulot',
      'Nasiya',
      'Savdo',
      'Topshiriq',
      if (widget.userRole == Role.admin) 'Xodim',
    ];

    final displayItems = _selectedCategory == 'Barchasi'
        ? _allItems
        : _allItems.where((i) => i.category == _selectedCategory).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: context.dialogBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          children: [
            // Qidiruv maydoni
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.search_rounded,
                      size: 24,
                      color:
                          context.isDark ? AppColors.neonLime : AppColors.ink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _focusNode,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.inkColor),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText:
                            'Tizim bo‘yicha qidirish (Mahsulot, Mijoz, Savdo, Xodim)...',
                        hintStyle: TextStyle(
                            color: context.mutedColor,
                            fontSize: 14,
                            fontWeight: FontWeight.normal),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear_rounded,
                          size: 20, color: context.mutedColor),
                      onPressed: () {
                        _searchCtrl.clear();
                        _filter();
                      },
                    ),
                  IconButton(
                    tooltip: 'Yopish',
                    icon: Icon(Icons.close_rounded,
                        size: 22, color: context.inkColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (_loading)
              const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: AppColors.neonLime)
            else
              Divider(height: 1, color: context.borderColor),

            // Kategoriya chipslari
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final cat = categories[i];
                  final isSel = _selectedCategory == cat;
                  final count = cat == 'Barchasi'
                      ? _allItems.length
                      : _allItems.where((x) => x.category == cat).length;

                  return InkWell(
                    onTap: () => setState(() => _selectedCategory = cat),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSel
                            ? (context.isDark
                                ? AppColors.neonLime
                                : AppColors.ink)
                            : context.pillColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            cat,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isSel ? FontWeight.w700 : FontWeight.w600,
                              color: isSel
                                  ? (context.isDark
                                      ? AppColors.ink
                                      : Colors.white)
                                  : context.inkColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? (context.isDark
                                      ? AppColors.ink.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.25))
                                  : (context.isDark
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : Colors.black.withValues(alpha: 0.08)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isSel
                                    ? (context.isDark
                                        ? AppColors.ink
                                        : Colors.white)
                                    : context.mutedColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: context.borderColor),

            // Natijalar ro'yxati
            Expanded(
              child: displayItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48, color: context.mutedColor),
                          const SizedBox(height: 12),
                          Text(
                            _searchCtrl.text.isEmpty
                                ? 'Qidiruv so‘zini kiriting'
                                : 'Hech qanday natija topilmadi',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: context.inkColor),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Mahsulot nomi, kodi, mijoz ismi yoki xodim loginini qidiring',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      itemCount: displayItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (ctx, i) {
                        final item = displayItems[i];
                        return InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onNavigate(item.destLabel,
                                filterQuery: item.filterQuery);
                          },
                          borderRadius: BorderRadius.circular(14),
                          hoverColor: context.isDark
                              ? const Color(0xFF222832)
                              : const Color(0xFFF8FAFC),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: item.iconBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(item.icon,
                                      color: item.iconColor, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: context.inkColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.subtitle,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.mutedColor),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: context.pillColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    item.category,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: context.inkColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.arrow_forward_ios_rounded,
                                    size: 12, color: context.mutedColor),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Pastki footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: context.cardSubtle,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Jami: ${displayItems.length} ta natija',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.mutedColor),
                  ),
                  Text(
                    'Tanlash uchun ustiga bosing',
                    style: TextStyle(fontSize: 11, color: context.mutedColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tizim Sozlamalari (Pastdan ochiluvchi ixcham Modal va Day/Night Mavzu)
// ---------------------------------------------------------------------------

class _SettingsBottomSheet extends StatelessWidget {
  const _SettingsBottomSheet({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final themeCtrl = context.watch<ThemeController>();
    final isDark = themeCtrl.isDark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: context.dialogBg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 36,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Sarlavha
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.neonLime,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: AppColors.ink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tizim Sozlamalari',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.inkColor,
                      ),
                    ),
                    Text(
                      'NTM ERP ko‘rinishi va parametrlari',
                      style:
                          TextStyle(fontSize: 11.5, color: context.mutedColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Yopish',
                icon: Icon(Icons.close_rounded,
                    color: context.inkColor, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Day / Night Theme bo'limi
          Text(
            'INTERFEYS MAVZUSI (DAY / NIGHT)',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: context.mutedColor,
            ),
          ),
          const SizedBox(height: 10),

          // Segmented controller
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: context.pillColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                // ☀️ Kunduzgi (Day) tab
                Expanded(
                  child: _ThemeTabButton(
                    title: 'Kunduzgi (Day)',
                    icon: Icons.wb_sunny_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    isSelected: !isDark,
                    onTap: () => themeCtrl.setMode(ThemeMode.light),
                  ),
                ),
                const SizedBox(width: 6),

                // 🌙 Tungi (Night) tab
                Expanded(
                  child: _ThemeTabButton(
                    title: 'Tungi (Night)',
                    icon: Icons.nightlight_round,
                    iconColor: AppColors.neonLime,
                    isSelected: isDark,
                    onTap: () => themeCtrl.setMode(ThemeMode.dark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Faol rejim haqida qisqa izoh
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(
                  isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  size: 15,
                  color: isDark ? AppColors.neonLime : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isDark
                        ? 'Tungi rejim faol: ko‘zga qulay chuqur qorong‘i interfeys'
                        : 'Kunduzgi rejim faol: klassik yorug‘ Vault ERP interfeysi',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: context.mutedColor,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Xavfsizlik va Ilova qulfi (PIN kod)
          Text(
            'XAVFSIZLIK VA ILOVA QULFI (PIN)',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: context.mutedColor,
            ),
          ),
          const SizedBox(height: 10),

          Builder(
            builder: (ctx) {
              AppLockController? appLock;
              try {
                appLock = Provider.of<AppLockController>(ctx);
              } catch (_) {}
              if (appLock == null) return const SizedBox.shrink();
              final lockCtrl = appLock;

              final hasPin = lockCtrl.hasPin;
              final isEnabled = lockCtrl.isLockEnabled;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.cardSubtle,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: (hasPin && isEnabled)
                                ? AppColors.green.withValues(alpha: 0.15)
                                : AppColors.muted.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            hasPin && isEnabled ? Icons.lock_rounded : Icons.lock_open_rounded,
                            color: hasPin && isEnabled ? AppColors.green : context.mutedColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ilova qulfi (PIN kod)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: context.inkColor,
                                ),
                              ),
                              Text(
                                !hasPin
                                    ? 'Hali o‘rnatilmagan'
                                    : (isEnabled ? 'Faol (Har safar kirganda so‘raladi)' : 'O‘chirilgan'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: hasPin && isEnabled ? AppColors.green : context.mutedColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasPin)
                          Switch(
                            value: isEnabled,
                            activeColor: AppColors.neonLime,
                            onChanged: (val) => lockCtrl.setLockEnabled(val),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: Icon(hasPin ? Icons.edit_rounded : Icons.add_moderator_rounded, size: 16),
                            label: Text(
                              hasPin ? 'PIN kodni tahrirlash' : 'PIN kod o‘rnatish',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              PinSetupDialog.show(context, user);
                            },
                          ),
                        ),
                        if (hasPin) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.neonLime,
                              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.lock_clock_rounded, size: 16),
                            label: const Text('Qulflash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              lockCtrl.lockNow();
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Tizim ma'lumotlari (ixcham qatorlar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.cardSubtle,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                _SettingsCompactRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Foydalanuvchi',
                  value: '${user.fullName} (${user.role.label})',
                ),
                const SizedBox(height: 8),
                const _SettingsCompactRow(
                  icon: Icons.cloud_done_outlined,
                  label: 'Server holati',
                  value: 'Onlayn (Bulutli API)',
                  valueColor: AppColors.green,
                ),
                const SizedBox(height: 8),
                const _SettingsCompactRow(
                  icon: Icons.verified_outlined,
                  label: 'ERP versiyasi',
                  value: 'v2.4 Vault Pro',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? AppColors.neonLime : AppColors.darkCard,
              foregroundColor: isDark ? AppColors.ink : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text('Tayyor / Yopish',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _ThemeTabButton extends StatelessWidget {
  const _ThemeTabButton({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF282F39) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(
                  color: isDark
                      ? AppColors.neonLime.withValues(alpha: 0.7)
                      : AppColors.border,
                  width: 1.2)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? context.inkColor : context.mutedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCompactRow extends StatelessWidget {
  const _SettingsCompactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.mutedColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.mutedColor),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: valueColor ?? context.inkColor,
          ),
        ),
      ],
    );
  }
}
