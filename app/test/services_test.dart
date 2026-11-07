import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';

import 'package:stonex_erp/data/mock_repositories.dart';

import 'package:stonex_erp/data/repositories.dart';

import 'package:stonex_erp/domain/models.dart';

import 'package:stonex_erp/state/auth_controller.dart';

import 'package:stonex_erp/state/cart_controller.dart';

import 'package:stonex_erp/state/currency_controller.dart';

import 'package:stonex_erp/state/theme_controller.dart';

import 'package:stonex_erp/ui/stone_services_dialog.dart';
import 'package:stonex_erp/ui/production_screen.dart';



void main() {

  group('Xizmatlar (Eni-bo‘yi kesish, Granit va Keramogranit silliqlash)', () {

    late MockStore store;

    late AppRepositories repos;

    late CartController cart;



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

      cart = CartController(repos.sales);

    });



    test('4 ta xizmat mavjudligi va Silliqlash hamda Kesish alohida narxlari', () {

      expect(kStoneServices.length, 4);

      final names = kStoneServices.map((s) => s.name).toList();

      expect(names, containsAll(['Razmer kesish', 'Faska ochish', 'Silliqlash', 'Chizish']));



      expect(StoneServicesStore.getPrice('cut'), 25000);

      expect(StoneServicesStore.getAllPrices()['cut_m2'], 25000);

      expect(StoneServicesStore.getPrice('chamfer'), 20000);

      expect(StoneServicesStore.getPrice('polish_granite'), 30000);

      expect(StoneServicesStore.getPrice('polish_ceramics'), 20000);

      expect(StoneServicesStore.getPrice('groove'), 10000);

    });



    test('Kesish hisobi: Metr kvadratda (0.72 m²) maydon va narx hisobi', () {
      const lM = 1.2;
      const wM = 0.6;
      final area = lM * wM;
      expect(area, 0.72);

      final priceCutM2 = StoneServicesStore.getPrice('cut');
      expect(priceCutM2, 25000.0);
      expect(area * priceCutM2, 18000.0);
    });



    testWidgets('StoneServicesDialog: Eni va bo‘yiga kesish hamda Silliqlash (Granit vs Keramogranit)', (tester) async {

      tester.view.physicalSize = const Size(1280, 800);

      tester.view.devicePixelRatio = 1.0;

      addTearDown(tester.view.resetPhysicalSize);



      final adminUser = const AppUser(

        id: 1,

        username: 'admin',

        fullName: 'Admin Boshliq',

        role: Role.admin,

      );



      await tester.pumpWidget(

        MultiProvider(

          providers: [

            Provider<AppRepositories>.value(value: repos),

            ChangeNotifierProvider(create: (_) => AuthController(repos.auth)),

            ChangeNotifierProvider.value(value: cart),

            ChangeNotifierProvider(create: (_) => CurrencyController()),

            ChangeNotifierProvider(create: (_) => ThemeController()),

          ],

          child: MaterialApp(

            home: Scaffold(

              body: Builder(

                builder: (ctx) => Center(

                  child: ElevatedButton(

                    onPressed: () => StoneServicesDialog.show(ctx, user: adminUser),

                    child: const Text('Ochish'),

                  ),

                ),

              ),

            ),

          ),

        ),

      );



      await tester.tap(find.text('Ochish'));

      await tester.pumpAndSettle();



      // Dialog va Kesish o'lchovi (Metr kvadratda) render bo'lganini tekshiramiz

      expect(find.text('Xizmatlar (Toshga ishlov berish)'), findsOneWidget);

      expect(find.text('Kesish o‘lchovi:'), findsOneWidget);

      expect(find.text('m² (Kvadrat metr)'), findsWidgets);



      // Savatga qo'shish

      await tester.tap(find.text('Savatga qo‘shish'));

      await tester.pumpAndSettle();



      expect(cart.lines.isNotEmpty, true);

      expect(cart.lines.first.product.name, contains('Razmer kesish'));

      expect(cart.lines.first.cutLength, 1.2);

      expect(cart.lines.first.cutWidth, 0.6);

      expect(cart.lines.first.quantity, 0.72);



      // Endi Silliqlashni ochib, Keramogranitni tanlash

      await tester.tap(find.text('Ochish'));

      await tester.pumpAndSettle();



      await tester.tap(find.text('Silliqlash'));

      await tester.pumpAndSettle();



      // Granit va Keramogranit tanlovi borligini tekshiramiz

      expect(find.text('Silliqlash uchun materialni tanlang:'), findsOneWidget);

      expect(find.byIcon(Icons.terrain_rounded), findsWidgets);

      expect(find.byIcon(Icons.grid_view_rounded), findsWidgets);



      // Keramogranit chipini tanlaymiz

      await tester.ensureVisible(find.byIcon(Icons.grid_view_rounded).first);

      await tester.tap(find.byIcon(Icons.grid_view_rounded).first, warnIfMissed: false);

      await tester.pumpAndSettle();



      // Savatga qo'shish

      await tester.tap(find.text('Savatga qo‘shish'));

      await tester.pumpAndSettle();



      final silliqLine = cart.lines.firstWhere((l) => l.product.name.contains('Silliqlash'));

      expect(silliqLine.product.name, contains('Keramogranit'));

      expect(silliqLine.unitPrice, 20000);

    });



    testWidgets('ServicesPriceConfigDialog: Granit va Keramogranit alohida narx belgilash', (tester) async {

      tester.view.physicalSize = const Size(1280, 800);

      tester.view.devicePixelRatio = 1.0;

      addTearDown(tester.view.resetPhysicalSize);



      await tester.pumpWidget(

        MultiProvider(

          providers: [

            Provider<AppRepositories>.value(value: repos),

            ChangeNotifierProvider.value(value: cart),

            ChangeNotifierProvider(create: (_) => CurrencyController()),

            ChangeNotifierProvider(create: (_) => ThemeController()),

          ],

          child: const MaterialApp(

            home: Scaffold(

              body: ServicesPriceConfigDialog(),

            ),

          ),

        ),

      );



      await tester.pumpAndSettle();



      expect(find.text('Xizmatlar narxini belgilash'), findsOneWidget);

      expect(find.text('Razmer kesish (m²)'), findsOneWidget);

      expect(find.text('Silliqlash — Granit'), findsOneWidget);

      expect(find.text('Silliqlash — Keramogranit'), findsOneWidget);



      // Saqlash

      await tester.tap(find.text('Saqlash'));

      await tester.pumpAndSettle();

    });



    testWidgets('Kesish bilan birga silliqlash va faska ochish (combo) savatga to\'g\'ri qo\'shiladi', (tester) async {

      tester.view.physicalSize = const Size(1280, 900);

      tester.view.devicePixelRatio = 1.0;

      addTearDown(tester.view.resetPhysicalSize);



      final adminUser = const AppUser(

        id: 1,

        username: 'admin',

        fullName: 'Admin Boshliq',

        role: Role.admin,

      );



      await tester.pumpWidget(

        MultiProvider(

          providers: [

            Provider<AppRepositories>.value(value: repos),

            ChangeNotifierProvider(create: (_) => AuthController(repos.auth)),

            ChangeNotifierProvider.value(value: cart),

            ChangeNotifierProvider(create: (_) => CurrencyController()),

            ChangeNotifierProvider(create: (_) => ThemeController()),

          ],

          child: MaterialApp(

            home: Scaffold(

              body: Builder(

                builder: (ctx) => Center(

                  child: ElevatedButton(

                    onPressed: () => StoneServicesDialog.show(ctx, user: adminUser),

                    child: const Text('Ochish'),

                  ),

                ),

              ),

            ),

          ),

        ),

      );



      await tester.tap(find.text('Ochish'));

      await tester.pumpAndSettle();



      // Kesgandan so'ng qo'shimcha ishlov berish bo'limi ko'rinishi kerak

      expect(find.textContaining('Kesgandan so‘ng qo‘shimcha ishlov berish'), findsOneWidget);

      expect(find.textContaining('Silliqlash (Jilolash)'), findsOneWidget);

      expect(find.textContaining('Faska ochish (Qirra berish)'), findsOneWidget);

      expect(find.textContaining('Chizish (Sirpanishga qarshi yo‘llar)'), findsOneWidget);



      // Silliqlash checkboxini yoqamiz

      final silliqlashCheckbox = find.byWidgetPredicate(

        (w) => w is Checkbox && w.value == false,

      ).first;

      await tester.ensureVisible(silliqlashCheckbox);

      await tester.tap(silliqlashCheckbox);

      await tester.pumpAndSettle();



      // Savatga qo'shish tugmasi

      final addToCartBtn = find.text('Savatga qo‘shish');

      await tester.ensureVisible(addToCartBtn);

      await tester.tap(addToCartBtn);

      await tester.pumpAndSettle();



      // Savatda endi kamida 2 ta element (Kesish + Silliqlash) bo'lishi kerak

      expect(cart.lines.length, greaterThanOrEqualTo(2));

      final hasCut = cart.lines.any((item) => item.product.name.contains('Kesish') || item.product.name.contains('kesish'));

      final hasPolish = cart.lines.any((item) => item.product.name.contains('Silliqlash'));

      expect(hasCut, isTrue);

      expect(hasPolish, isTrue);

    });

     test('Ishchi topshiriqni bajara olmasdan qaytara oladi (reject) va status rejected boladi', () async {

      final store = MockStore();

      final prodRepo = MockProductionRepository(store);

      final tasksBefore = await prodRepo.list();

      expect(tasksBefore.isNotEmpty, isTrue);



      final t = tasksBefore.first;

      await prodRepo.reject(t.id, reason: 'Stanok band');



      final tasksAfter = await prodRepo.list();

      final updated = tasksAfter.firstWhere((item) => item.id == t.id);

      expect(updated.status, 'rejected');

      expect(updated.isRejected, isTrue);

      expect(updated.note, contains('Stanok band'));

    });



    testWidgets('Metr kvadratda (m2) bo‘yi ham metrda (m) bo‘ladi va o‘lchami to‘g‘ri hisoblanadi', (tester) async {

      tester.view.physicalSize = const Size(1280, 800);

      tester.view.devicePixelRatio = 1.0;

      addTearDown(tester.view.resetPhysicalSize);



      final adminUser = const AppUser(

        id: 1,

        username: 'admin',

        fullName: 'Admin Boshliq',

        role: Role.admin,

      );



      await tester.pumpWidget(

        MultiProvider(

          providers: [

            Provider<AppRepositories>.value(value: repos),

            ChangeNotifierProvider(create: (_) => AuthController(repos.auth)),

            ChangeNotifierProvider.value(value: cart),

            ChangeNotifierProvider(create: (_) => CurrencyController()),

            ChangeNotifierProvider(create: (_) => ThemeController()),

          ],

          child: MaterialApp(

            home: Scaffold(

              body: Builder(

                builder: (ctx) => Center(

                  child: ElevatedButton(

                    onPressed: () => StoneServicesDialog.show(ctx, user: adminUser),

                    child: const Text('Ochish'),

                  ),

                ),

              ),

            ),

          ),

        ),

      );



      await tester.tap(find.text('Ochish'));

      await tester.pumpAndSettle();



      // m2 tanlangan holatda Kvadrat metr (m²) ko'rinishi va maydon hisoblanishi kerak
      expect(find.text('Kvadrat metr (m²):'), findsOneWidget);
      expect(find.textContaining('0.72 m²'), findsWidgets);
      expect(find.text('m² (Kvadrat metr)'), findsOneWidget);
    });

    testWidgets('Kesish: Kenglik va Uzunlik proporsional hisobi va Kvadrat metr (m²)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final adminUser = const AppUser(
        id: 1,
        username: 'admin',
        fullName: 'Admin Boshliq',
        role: Role.admin,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppRepositories>.value(value: repos),
            ChangeNotifierProvider(create: (_) => AuthController(repos.auth)),
            ChangeNotifierProvider.value(value: cart),
            ChangeNotifierProvider(create: (_) => CurrencyController()),
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () => StoneServicesDialog.show(ctx, user: adminUser),
                    child: const Text('Ochish'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ochish'));
      await tester.pumpAndSettle();

      // Yangi inputlar mavjudligi: Kenglik, Uzunlik va Kvadrat metr (m²)
      expect(find.text('Kenglik (kesiladigan):'), findsOneWidget);
      expect(find.text('Uzunlik (kesiladigan):'), findsOneWidget);
      expect(find.text('Kvadrat metr (m²):'), findsOneWidget);
      expect(find.textContaining('0.72 m²'), findsWidgets);
    });

    testWidgets('TaskCreateDialog: Topshiriq berishda toshni kesish va silliqlash xizmatlarini qo‘shish', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppRepositories>.value(value: repos),
            ChangeNotifierProvider(create: (_) => AuthController(repos.auth)),
            ChangeNotifierProvider(create: (_) => CartController(repos.sales)),
            ChangeNotifierProvider(create: (_) => CurrencyController()),
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showDialog(
                    context: ctx,
                    builder: (_) => TaskCreateDialog(
                      productionRepo: repos.production,
                      productRepo: repos.products,
                    ),
                  ),
                  child: const Text('Topshiriq Oyna'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Topshiriq Oyna'));
      await tester.pumpAndSettle();

      // Dialog ochildi
      expect(find.text('Yangi Ishlab Chiqarish Topshirig‘i'), findsOneWidget);
      expect(find.text('Toshga ishlov berish xizmatlari'), findsOneWidget);

      // Xizmat chiplari mavjud
      expect(find.text('✂️ Razmer kesish'), findsOneWidget);
      expect(find.text('✨ Silliqlash'), findsOneWidget);
      expect(find.text('📐 Faska ochish'), findsOneWidget);
      expect(find.text('〰️ Chizish'), findsOneWidget);

      // 1. Kesish xizmatini tanlaymiz
      await tester.tap(find.text('✂️ Razmer kesish'));
      await tester.pumpAndSettle();

      expect(find.text('✂️ KESISH O‘LCHAMLARI'), findsOneWidget);
      expect(find.textContaining('Hisoblangan maydon:'), findsOneWidget);

      // 2. Silliqlash xizmatini tanlaymiz
      await tester.tap(find.text('✨ Silliqlash'));
      await tester.pumpAndSettle();

      expect(find.text('✨ SILLIQLASH (JILOLASH)'), findsOneWidget);
      expect(find.text('Granit'), findsOneWidget);
      expect(find.text('Keramogranit'), findsOneWidget);

      // Topshiriq berish tugmasini bosamiz
      expect(find.text('Topshiriq berish'), findsOneWidget);
      await tester.tap(find.text('Topshiriq berish'));
      await tester.pumpAndSettle();

      // Topshiriqlar ro'yxatida yangi xizmatli topshiriq paydo bo'ldi
      final tasks = await repos.production.list();
      expect(tasks.isNotEmpty, isTrue);
      // Oxirgi qo'shilgan topshiriq
      final newTask = tasks.firstWhere(
        (t) => (t.note ?? '').contains('✨ Silliqlash'),
        orElse: () => tasks.last,
      );
      expect(newTask.cutSpec, isNotNull);
      expect(newTask.note, contains('Silliqlash'));
    });

  });

}