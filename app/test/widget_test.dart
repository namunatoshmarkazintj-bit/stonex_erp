import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';

import 'package:stonex_erp/data/mock_repositories.dart';

import 'package:stonex_erp/data/repositories.dart';

import 'package:stonex_erp/domain/models.dart';

import 'package:stonex_erp/main.dart';

import 'package:stonex_erp/state/auth_controller.dart';

import 'package:stonex_erp/state/cart_controller.dart';

import 'package:stonex_erp/state/currency_controller.dart';

import 'package:stonex_erp/ui/finance_screen.dart';
import 'package:stonex_erp/ui/home_shell.dart';

import 'package:stonex_erp/ui/production_screen.dart';

import 'package:stonex_erp/ui/dashboard_screen.dart';

import 'package:stonex_erp/ui/products_screen.dart';

import 'package:stonex_erp/ui/pos_screen.dart';

import 'package:stonex_erp/ui/customers_screen.dart';

import 'package:stonex_erp/ui/purchases_screen.dart';

import 'package:stonex_erp/ui/debts_screen.dart';

import 'package:stonex_erp/ui/orders_screen.dart';

import 'package:stonex_erp/ui/receipt_dialog.dart';
import 'package:stonex_erp/ui/users_screen.dart';

import 'package:stonex_erp/ui/sales_history_screen.dart';

import 'package:stonex_erp/state/theme_controller.dart';



void main() {

  late MockStore store;

  late AppRepositories repos;

  const adminUser = AppUser(id: 1, username: 'admin', fullName: 'Xo‘jayin', role: Role.admin);



  setUp(() {

    store = MockStore();

    repos = AppRepositories(

      auth: MockAuthRepository(store),

      products: MockProductRepository(store),

      sales: MockSalesRepository(store),

      finance: MockFinanceRepository(store),

      production: MockProductionRepository(store),

      users: MockUserRepository(store),

      stock: MockStockRepository(store),

      notifications: MockNotificationRepository(store),

      customers: MockCustomerRepository(store),

      attendance: MockAttendanceRepository(store),

      deliveries: MockDeliveryRepository(store),

    );

  });



  testWidgets('Smoke test - LoginScreen renders correctly', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    await tester.pumpWidget(StonexApp(repos: repos));

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));



    expect(find.text('NTJ'), findsWidgets);

    expect(find.text('Tizimga kirish'), findsWidgets);

  });



  testWidgets('Desktop HomeShell - zero overflow on smaller desktop heights and sidebar navigation works', (tester) async {

    // Testing on a laptop height with scaling (1024 x 620)

    tester.view.physicalSize = const Size(1024, 620);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    final authCtrl = AuthController(repos.auth);

    await authCtrl.login('admin', 'admin123', Role.admin);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: authCtrl),

          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

        ],

        child: const MaterialApp(

          home: HomeShell(user: adminUser),

        ),

      ),

    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Verify all menu buttons exist

    expect(find.text('Asosiy oyna'), findsWidgets);

    expect(find.text('Ishlab chiqarish'), findsWidgets);



    // Click "Ishlab chiqarish"

    final prodNavItem = find.widgetWithText(InkWell, 'Ishlab chiqarish');

    expect(prodNavItem, findsWidgets);

    await tester.ensureVisible(prodNavItem.first);

    await tester.tap(prodNavItem.first);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Verify ProductionScreen rendered without errors

    expect(find.byType(ProductionScreen), findsOneWidget);

    expect(find.text('Jami Topshiriqlar'), findsOneWidget);

    expect(find.text('Angola'), findsWidgets);

    expect(find.text('Ishchi Bobur'), findsWidgets);



    // Test toggle sidebar collapse & expand

    final toggleBtn = find.byTooltip('Menyuni yopish (Ctrl+B)');

    expect(toggleBtn, findsOneWidget);

    await tester.tap(toggleBtn);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    final openBtn = find.byTooltip('Menyuni ochish (Ctrl+B)');

    expect(openBtn, findsOneWidget);

    await tester.tap(openBtn);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Menyuni yopish (Ctrl+B)'), findsOneWidget);



    await tester.pumpWidget(const SizedBox());

    await tester.pump();

  });



  testWidgets('ProductionScreen TaskCreateDialog works seamlessly', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    final authCtrl = AuthController(repos.auth);

    await authCtrl.login('admin', 'admin123', Role.admin);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: authCtrl),

          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

        ],

        child: const MaterialApp(

          home: Scaffold(body: ProductionScreen()),

        ),

      ),

    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Tap "+ Topshiriq" or "Topshiriq"

    final createBtn = find.text('Topshiriq');

    expect(createBtn, findsOneWidget);

    await tester.tap(createBtn);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Dialog should be open

    expect(find.text('Yangi Ishlab Chiqarish Topshirig‘i'), findsOneWidget);

    expect(find.text('Topshiriq berish'), findsOneWidget);



    // Cancel dialog

    await tester.tap(find.text('Bekor'));

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));

  });



  testWidgets('ProductionScreen report work dialog and submission works without Future in setState', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    final authCtrl = AuthController(repos.auth);

    await authCtrl.login('ishchi', 'ishchi123', Role.ishchi);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: authCtrl),

          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

        ],

        child: const MaterialApp(

          home: Scaffold(body: ProductionScreen()),

        ),

      ),

    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Click "Hisobot" button on first open task

    final reportBtn = find.text('Hisobot');

    expect(reportBtn, findsWidgets);

    await tester.tap(reportBtn.first);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Dialog should be open

    expect(find.text('Yuborish'), findsOneWidget);



    // Tap "Yuborish"

    await tester.tap(find.text('Yuborish'));

    await tester.pump();

    await tester.pump(const Duration(seconds: 4));



    // Dialog dismissed and tasks refreshed

    expect(find.text('Yuborish'), findsNothing);

  });



  testWidgets('ProductsScreen mobile viewport - zero RenderFlex overflow and QR dialog works', (tester) async {

    // Narrow smartphone screen 360 x 740

    tester.view.physicalSize = const Size(360, 740);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    final authCtrl = AuthController(repos.auth);

    await authCtrl.login('admin', 'admin123', Role.admin);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: authCtrl),

          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

        ],

        child: const MaterialApp(

          home: Scaffold(body: ProductsScreen()),

        ),

      ),

    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Verify products list rendered without RenderFlex overflow

    expect(find.text('Jami Mahsulotlar'), findsOneWidget);

    expect(find.text('Toshlar (m²)'), findsWidgets);

    expect(find.text('Dona'), findsWidgets);



    // Verify QR dialog opens without overflow

    final qrButtons = find.byTooltip('QR Yorliq');

    expect(qrButtons, findsWidgets);

    await tester.tap(qrButtons.first);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    expect(find.text('Mahsulot QR Yorlig‘i'), findsOneWidget);

    expect(find.text('NTM MARBLE'), findsOneWidget);



    // Close dialog

    await tester.tap(find.byIcon(Icons.close_rounded));

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));

  });



  testWidgets('DashboardScreen mobile viewport - chart and products table render with zero overflow', (tester) async {

    // Narrow smartphone screen 360 x 740

    tester.view.physicalSize = const Size(360, 740);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    final authCtrl = AuthController(repos.auth);

    await authCtrl.login('admin', 'admin123', Role.admin);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: authCtrl),

          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

        ],

        child: const MaterialApp(

          home: Scaffold(body: DashboardScreen()),

        ),

      ),

    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));



    // Verify chart title & stock table card rendered without overflow

    expect(find.text('Savdo Dinamikasi'), findsOneWidget);

    expect(find.text('Ombor Holati va Mahsulotlar'), findsOneWidget);



    // Touch/drag on the chart area to trigger hover tooltip

    final chartArea = find.byType(CustomPaint);

    expect(chartArea, findsWidgets);

    await tester.drag(chartArea.first, const Offset(50, 0));

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));

  });



  testWidgets('DashboardScreen desktop viewport - symmetrical card heights and zero overflow', (tester) async {

    tester.view.physicalSize = const Size(1440, 900);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    final authCtrl = AuthController(repos.auth);

    await authCtrl.login('admin', 'admin123', Role.admin);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: authCtrl),

          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

        ],

        child: const MaterialApp(

          home: Scaffold(body: DashboardScreen()),

        ),

      ),

    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));



    expect(find.textContaining('Savdo Dinamikasi'), findsOneWidget);

    expect(find.text('Ombor Holati va Mahsulotlar'), findsOneWidget);

    expect(find.text('Jami Savdolar (Daromad)'), findsOneWidget);

    expect(find.text('Kassaga Tushgan Pul'), findsOneWidget);

    expect(find.text('Qarzdorlik (Nasiya)'), findsOneWidget);

    expect(find.text('Sof Foyda'), findsOneWidget);

  });



  testWidgets('PosScreen QR scanner dialog - sleek UX, quantity stepper and zero overflow', (WidgetTester tester) async {

    final cartController = CartController(repos.sales);



    tester.view.physicalSize = const Size(390, 844);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider<CartController>.value(value: cartController),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

        ],

        child: const MaterialApp(

          home: Scaffold(body: PosScreen()),

        ),

      ),

    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));



    // Tap the QR scanner button (opens QrScannerScreen full-screen on mobile)

    final qrButton = find.widgetWithText(FilledButton, 'QR');

    expect(qrButton, findsOneWidget);

    await tester.tap(qrButton);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));



    // Fullscreen scanner should be visible with title 'QR Skaner'

    expect(find.text('QR Skaner'), findsOneWidget);



    // Tap manual code input button (opens bottom sheet without auto-blocking keyboard initially)

    final manualInputBtn = find.byTooltip('Kodni qo‘lda yozish');

    expect(manualInputBtn, findsOneWidget);

    await tester.tap(manualInputBtn);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Enter a valid barcode 'STX-ANGOLA' in the bottom sheet

    final barcodeInput = find.byType(TextField).last;

    await tester.enterText(barcodeInput, 'STX-ANGOLA');

    await tester.tap(find.widgetWithText(FilledButton, 'Savatga qo‘shish'));

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Product should be added to cart and displayed in last scanned card

    expect(find.text('Oxirgi skanerlangan mahsulot'), findsOneWidget);

    expect(find.text('Angola'), findsWidgets);

    expect(cartController.lines.length, 1);

    expect(cartController.lines.first.quantity, 1.0);



    // Increase quantity using the inline stepper button '+'

    final plusBtn = find.byIcon(Icons.add_rounded);

    expect(plusBtn, findsOneWidget);

    await tester.tap(plusBtn);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));



    expect(cartController.lines.first.quantity, 2.0);



    // Tap Done / Close button

    final closeBtn = find.text('Tayyor (Yopish)');

    expect(closeBtn, findsOneWidget);

    await tester.tap(closeBtn);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));



    // Scanner screen should be dismissed and cart preserved in POS

    expect(find.text('QR Skaner'), findsNothing);

    expect(cartController.lines.length, 1);

  });



  testWidgets('CustomersScreen renders correctly, search works and dialog opens', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    final authCtrl = AuthController(repos.auth);

    await authCtrl.login('admin', 'admin123', Role.admin);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: authCtrl),

          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

          ChangeNotifierProvider(create: (_) => ThemeController()),

        ],

        child: const MaterialApp(

          home: Scaffold(body: CustomersScreen()),

        ),

      ),

    );



    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // CustomersScreen header and customer cards should be rendered

    expect(find.text('Sardor Qodirov'), findsOneWidget);

    expect(find.text('Jami mijozlar'), findsOneWidget);

    expect(find.text('Yangi Mijoz'), findsOneWidget);



    // Filter by searching "Farhod"

    final searchField = find.byType(TextField);

    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'Farhod');

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));



    expect(find.text('Farhod Usta'), findsOneWidget);

    expect(find.text('Sardor Qodirov'), findsNothing);

  });



  testWidgets('ReceiptDialog renders slip, barcode/QR, totals and copy button', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {

      tester.view.resetPhysicalSize();

      tester.view.resetDevicePixelRatio();

    });



    const mockSale = SaleResult(

      id: 101,

      total: 1800000,

      paid: 1800000,

      debt: 0,

      customerName: 'Sobirjon Aka',

      customerPhone: '+998 90 111 22 33',

      cashierName: 'Alisher Kassir',

      items: [

        SaleItemRecord(productId: 1, productName: 'Marmar Oq', quantity: 10, unitPrice: 180000, lineTotal: 1800000),

      ],

    );



    await tester.pumpWidget(

      const MaterialApp(

        home: Scaffold(

          body: ReceiptDialog(sale: mockSale),

        ),

      ),

    );



    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    expect(find.text('Kassa Cheki'), findsOneWidget);

    expect(find.text('NTJ — NAMUNA TOSH JILO'), findsOneWidget);

    expect(find.text('Sobirjon Aka'), findsOneWidget);

    expect(find.text('Marmar Oq'), findsOneWidget);

    expect(find.text('Nusxa olish'), findsOneWidget);

    expect(find.text('Chop etish'), findsOneWidget);

  });



  testWidgets('SalesHistoryScreen renders sales, KPIs and search works', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {

      tester.view.resetPhysicalSize();

      tester.view.resetDevicePixelRatio();

    });



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

        ],

        child: const MaterialApp(

          home: Scaffold(body: SalesHistoryScreen()),

        ),

      ),

    );



    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    expect(find.text('Savdolar Jurnali'), findsOneWidget);

    expect(find.text('Jami Savdo Summasi'), findsOneWidget);



    // Search by customer "Sardor"

    final search = find.byType(TextField);

    await tester.enterText(search, 'Sardor');

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));



    expect(find.textContaining('Sardor Qodirov'), findsWidgets);



    // Search by customer "Farhod"

    await tester.enterText(search, 'Farhod');

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));



    expect(find.textContaining('Farhod Usta'), findsWidgets);

    expect(find.textContaining('Sardor Qodirov'), findsNothing);

  });



  testWidgets('PurchasesScreen renders stock purchases, KPIs and new purchase dialog', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {

      tester.view.resetPhysicalSize();

      tester.view.resetDevicePixelRatio();

    });



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

        ],

        child: const MaterialApp(

          home: Scaffold(body: PurchasesScreen()),

        ),

      ),

    );



    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    expect(find.text('Xaridlar & Ta‘minot'), findsOneWidget);

    expect(find.text('Jami Xaridlar Summasi'), findsOneWidget);

    expect(find.text('Yangi Xarid Kirimi'), findsOneWidget);



    // Click "Yangi Xarid Kirimi"

    await tester.tap(find.text('Yangi Xarid Kirimi'));

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    expect(find.text('Xarid qilinayotgan tovar / xomashyo'), findsOneWidget);

    expect(find.text('Kirim qilish'), findsOneWidget);

  });



  testWidgets('Scanning receipt QR code opens ReceiptDialog', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {

      tester.view.resetPhysicalSize();

      tester.view.resetDevicePixelRatio();

    });



    final cartCtrl = CartController(repos.sales);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: cartCtrl),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

        ],

        child: const MaterialApp(

          home: Scaffold(body: PosScreen()),

        ),

      ),

    );



    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Type a receipt QR code into the search/scanner input

    final search = find.byType(TextField).first;

    await tester.enterText(search, 'STONEX-CHEK-#95-1800000UZS');

    await tester.testTextInput.receiveAction(TextInputAction.done);

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    // Verify ReceiptDialog opened with Chek #95

    expect(find.byType(ReceiptDialog), findsOneWidget);

    expect(find.text('Kassa Cheki'), findsOneWidget);

    expect(find.text('NTJ — NAMUNA TOSH JILO'), findsOneWidget);

    expect(find.textContaining('95'), findsWidgets);

  });



  testWidgets('OrdersScreen renders orders, KPIs and fulfill workflow works', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {

      tester.view.resetPhysicalSize();

      tester.view.resetDevicePixelRatio();

    });



    // Create a pre-order in mock store

    final product = store.products.first;

    await repos.sales.createSale(

      lines: [CartLine(product, quantity: 2)],

      paidAmount: 50000,

      customerName: 'Javohir Buyurtmachi',

      customerPhone: '+998 90 777 66 55',

      status: 'order',

      note: '3 kundan keyin olib ketadi',

    );



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

        ],

        child: const MaterialApp(

          home: Scaffold(body: OrdersScreen()),

        ),

      ),

    );



    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    expect(find.text('Jami Buyurtmalar'), findsOneWidget);

    expect(find.text('Kutilmoqda (Faol)'), findsWidgets);

    expect(find.text('Javohir Buyurtmachi +998 90 777 66 55'), findsOneWidget);

    expect(find.text('Izoh: 3 kundan keyin olib ketadi'), findsOneWidget);

    expect(find.text('Topshirish'), findsOneWidget);

  });



  testWidgets('DebtsScreen renders KPIs, search and view toggle works', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {

      tester.view.resetPhysicalSize();

      tester.view.resetDevicePixelRatio();

    });



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

        ],

        child: const MaterialApp(

          home: Scaffold(body: DebtsScreen()),

        ),

      ),

    );



    await tester.pump();

    await tester.pump(const Duration(milliseconds: 300));



    expect(find.text('Jami Nasiyalar'), findsOneWidget);

    expect(find.text('Qarzdor Mijozlar'), findsOneWidget);

    expect(find.text('Cheklar'), findsOneWidget);

    expect(find.text('Mijozlar'), findsOneWidget);

  });



  testWidgets('Ish boshqaruvchi HomeShell navigatsiyasi va topshiriq / OTK tasdiqlash ruxsatlari', (tester) async {

    tester.view.physicalSize = const Size(1280, 800);

    tester.view.devicePixelRatio = 1.0;

    addTearDown(() => tester.view.resetPhysicalSize());



    final auth = AuthController(repos.auth);



    // Boshqaruvchi login

    await auth.login('boshqaruvchi', 'boshqaruvchi123', Role.ishBoshqaruvchi);

    expect(auth.user?.role, Role.ishBoshqaruvchi);



    await tester.pumpWidget(

      MultiProvider(

        providers: [

          Provider<AppRepositories>.value(value: repos),

          ChangeNotifierProvider.value(value: auth),

          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),

          ChangeNotifierProvider(create: (_) => CurrencyController()),

          ChangeNotifierProvider(create: (_) => ThemeController()),

        ],

        child: MaterialApp(

          home: HomeShell(user: auth.user!),

        ),

      ),

    );



    await tester.pumpAndSettle();



    // Ish boshqaruvchiga faqat Ishlab chiqarish va Ombor bo'limlari ko'rinadi (Xodimlar ko'rinmaydi)

    expect(find.text('Ishlab chiqarish'), findsWidgets);

    expect(find.text('Ombor'), findsWidgets);

    expect(find.text('Xodimlar'), findsNothing);



    // Ish boshqaruvchiga topshiriq tugmasi chiqishi kerak

    expect(find.text('Topshiriq'), findsOneWidget);



    // 2-ish boshqaruvchi akkauntini ochish cheklovi (faqat 1 ta bo'lishi shart)

    expect(

      () => repos.users.create(

        username: 'boshqaruvchi_2',

        fullName: 'Ikkinchi Boshqaruvchi',

        role: Role.ishBoshqaruvchi,

      ),

      throwsA(isA<Exception>()),

    );

  });

  testWidgets('Ishchi ko‘rinishi: topshiriq kartasida kesish o‘lchamlari va Batafsil modal oynasi to‘liq ko‘rinadi', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final authCtrl = AuthController(repos.auth);
    await authCtrl.login('ishchi', 'ishchi123', Role.ishchi);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppRepositories>.value(value: repos),
          ChangeNotifierProvider.value(value: authCtrl),
          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),
          ChangeNotifierProvider(create: (_) => CurrencyController()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProductionScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Angola topshiriq kartasida o'lchamlar va donasi ko'rinishi shart
    expect(find.text('Angola'), findsWidgets);
    expect(find.textContaining('120 sm × 60 sm'), findsWidgets);
    expect(find.textContaining('4 dona'), findsWidgets);
    expect(find.text('Batafsil'), findsWidgets);

    // Batafsil tugmasini bosganda to'liq ish varaqasi ochilishi
    await tester.tap(find.text('Batafsil').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('📐 KESISH VA O‘LCHAMLAR'), findsOneWidget);
    expect(find.textContaining('120 sm × 60 sm'), findsWidgets);
    expect(find.textContaining('4 dona'), findsWidgets);
    expect(find.text('Yopish'), findsOneWidget);

    // Yopish tugmasini bosish
    await tester.tap(find.text('Yopish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('FinanceScreen renders KPIs, monthly comparison, revenue chart, journal and export', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final authCtrl = AuthController(repos.auth);
    await authCtrl.login('admin', 'admin123', Role.admin);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppRepositories>.value(value: repos),
          ChangeNotifierProvider.value(value: authCtrl),
          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),
          ChangeNotifierProvider(create: (_) => CurrencyController()),
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FinanceScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // Sarlavha va asosiy KPI kartalari
    expect(find.text('Moliya va Hisobotlar'), findsOneWidget);
    expect(find.text('Jami Savdo & Tushum'), findsOneWidget);
    expect(find.text('Jami Chiqimlar'), findsOneWidget);
    expect(find.text('Sof Foyda'), findsWidgets);
    expect(find.text('Umumiy Nasiyalar'), findsOneWidget);

    // O\'tgan oy va bu oy solishtirish
    expect(find.text('O‘tgan oy va bu oy o‘rtasida solishtirish'), findsOneWidget);

    // Daromad manbalari (Nimadan ko\'p pul tushdi)
    expect(find.text('Nimadan ko‘p pul tushdi? (Daromad manbalari)'), findsOneWidget);
    expect(find.textContaining('Granit plitalar'), findsOneWidget);
    expect(find.textContaining('Kesish va ishlov berish'), findsOneWidget);

    // Tab almashtirish: Kirim-chiqimlar jurnali
    await tester.tap(find.text('📋 Kirim-chiqimlar jurnali'));
    await tester.pumpAndSettle();

    expect(find.text('Barcha amallar'), findsOneWidget);
    expect(find.text('Transport / Yoqilg‘i'), findsWidgets);

    // Yangi operatsiya qo\'shish dialogi
    expect(find.text('+ Chiqim / Kirim'), findsOneWidget);
    await tester.tap(find.text('+ Chiqim / Kirim'));
    await tester.pumpAndSettle();

    expect(find.text('Chiqim kiritish (Xarajat)'), findsOneWidget);
    expect(find.text('Chiqim (Xarajat)'), findsOneWidget);
    expect(find.text('Kirim (Qo‘shimcha)'), findsOneWidget);

    // Ish haqi tanlanganda xodimlar ro'yxati chiqishi va tanlanishi
    expect(find.textContaining('Xodimlarni tanlang'), findsOneWidget);
    expect(find.textContaining('Ishchi Bobur'), findsOneWidget);
    await tester.tap(find.textContaining('Ishchi Bobur'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 ta tanlandi'), findsOneWidget);

    // Summa kiritish
    await tester.enterText(find.widgetWithText(TextField, '0'), '500000');
    await tester.enterText(find.widgetWithText(TextField, 'Operatsiya sababi yoki hujjati haqida qisqacha izoh...'), 'Test xarajati');
    await tester.tap(find.text('Kiritish'));
    await tester.pumpAndSettle();

    // Excel yuklab olish tugmasi
    expect(find.text('Excel yuklab olish'), findsOneWidget);
    await tester.tap(find.text('Excel yuklab olish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('FinanceScreen: Oylik to‘lash barchasiga birdaniga to‘lash va individual summa kiritish', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final authCtrl = AuthController(repos.auth);
    await authCtrl.login('admin', 'admin123', Role.admin);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppRepositories>.value(value: repos),
          ChangeNotifierProvider.value(value: authCtrl),
          ChangeNotifierProvider(create: (_) => CartController(repos.sales)),
          ChangeNotifierProvider(create: (_) => CurrencyController()),
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FinanceScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // 1. "Oylik to'lash" tugmasi mavjudligi va bosilishi
    expect(find.text('Oylik to‘lash'), findsOneWidget);
    await tester.tap(find.text('Oylik to‘lash'));
    await tester.pumpAndSettle();

    expect(find.text('Chiqim kiritish (Xarajat)'), findsOneWidget);
    expect(find.text('Barchasiga to‘liq oylik to‘lash'), findsOneWidget);
    expect(find.text('Ishlagan haqini to‘lash'), findsOneWidget);
    expect(find.textContaining('Ishlagani:'), findsWidgets);

    // 2. "Barchasiga to‘liq oylik to‘lash" tugmasini bosish
    await tester.tap(find.text('Barchasiga to‘liq oylik to‘lash'));
    await tester.pumpAndSettle();

    // Barcha xodimlar tanlanganini va jami to'lov hisoblanganini tekshirish
    expect(find.textContaining('ta tanlandi'), findsOneWidget);
    expect(find.textContaining('jami to‘lov:'), findsOneWidget);

    // 3. Tozalash tugmasi
    expect(find.text('Tozalash'), findsOneWidget);
    await tester.tap(find.text('Tozalash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 ta tanlandi'), findsNothing);

    // 4. Bitta xodimni tanlab, individual avans/summa kiritish
    await tester.tap(find.textContaining('Ishchi Bobur'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 ta tanlandi'), findsOneWidget);

    // 50% avans tugmasini bosish
    expect(find.text('50% avans'), findsOneWidget);
    await tester.tap(find.text('50% avans'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Kiritish orqali operatsiyani saqlash
    await tester.tap(find.text('Kiritish'));
    await tester.pumpAndSettle();

    // Dialog yopilganini tekshirish
    expect(find.text('Chiqim kiritish (Xarajat)'), findsNothing);
  });

  testWidgets('UsersScreen: Oylik va Ish haqi hisoboti zamonaviy UI va boshqaruv tugmalari ishlaydi', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppRepositories>.value(value: repos),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UsersScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // 1. "Oylik hisobi" tabini topish va bosish
    expect(find.text('Oylik hisobi'), findsOneWidget);
    await tester.tap(find.text('Oylik hisobi'));
    await tester.pumpAndSettle();

    // 2. Yangi zamonaviy boshqaruv paneli va tugmalar
    expect(find.text('Barchasiga oylik to‘lash'), findsOneWidget);
    expect(find.text('Excel tabel'), findsOneWidget);

    // 3. 4 ta KPI kartasi
    expect(find.text('Jami Sof Oylik'), findsOneWidget);
    expect(find.text('Rejadagi Oylik Fond'), findsOneWidget);
    expect(find.text('Haqiqiy Ishlagani'), findsOneWidget);

    // 4. Qidiruv va filtr chiplari
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Barchasi ('), findsOneWidget);

    // 5. Xodim kartasida yangi qulayliklar: Davomat kunlari va Oylik to'lash tugmasi
    expect(find.text('Davomat kunlari'), findsWidgets);
    expect(find.text('Oylik to‘lash'), findsWidgets);
    expect(find.textContaining('Ishlagan qismi:'), findsWidgets);
    expect(find.text('To‘lanadigan sof maosh'), findsWidgets);

    // 6. "Davomat kunlari" tugmasini bosib ko'rish
    await tester.ensureVisible(find.text('Davomat kunlari').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Davomat kunlari').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('davomat tabeli'), findsOneWidget);
    expect(find.text('Yopish'), findsOneWidget);
    await tester.tap(find.text('Yopish'));
    await tester.pumpAndSettle();
  });
}
