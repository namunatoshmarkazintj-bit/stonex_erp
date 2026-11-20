import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:stonex_erp/domain/models.dart';
import 'package:stonex_erp/ui/receipt_dialog.dart';

void main() {
  group('Xprinter XP-80 va drayver parametrlari asosida chek chop etish testi', () {
    final testSale = SaleResult(
      id: 63,
      items: const [
        SaleItemRecord(
          productId: 1,
          productName: 'TAMRANO1 [1-sort]',
          quantity: 36.0,
          unitPrice: 125000,
          lineTotal: 4500000,
        ),
        SaleItemRecord(
          productId: 2,
          productName: 'benfix kley (bezsvet) [bezsvet-sort]',
          quantity: 2.0,
          unitPrice: 50000,
          lineTotal: 100000,
        ),
        SaleItemRecord(
          productId: 3,
          productName: 'ANGREN 1906 [1-sort]',
          quantity: 3.1,
          unitPrice: 76000,
          lineTotal: 235620,
        ),
        SaleItemRecord(
          productId: 4,
          productName: 'angola xitoy (1) [1-sort]',
          quantity: 17.3,
          unitPrice: 195000,
          lineTotal: 3369600,
        ),
      ],
      total: 8205220,
      paid: 8205220,
      debt: 0,
      paymentMethod: 'cash',
      cashierName: 'Jamoldinov Zoyirjon',
      customerName: 'Chakana xaridor',
      currencyRate: 11972,
      createdAt: DateTime(2026, 11, 20, 11, 11),
    );

    test('1. Drayver 78.0 mm qog\'oz qaytarganda (New paper 78.0 x 296.9 mm)', () async {
      final driverFormat = const PdfPageFormat(
        78.0 * PdfPageFormat.mm,
        296.9 * PdfPageFormat.mm,
        marginLeft: 0,
        marginRight: 0,
      );

      final bytes = await ReceiptDialogTestHelper.buildPdfBytes(testSale, driverFormat);
      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(1000));
    });

    test('2. Drayver 80.0 mm qog\'oz qaytarganda (Standart 80mm roll)', () async {
      final driverFormat = const PdfPageFormat(
        80.0 * PdfPageFormat.mm,
        297.0 * PdfPageFormat.mm,
        marginLeft: 0,
        marginRight: 0,
      );

      final bytes = await ReceiptDialogTestHelper.buildPdfBytes(testSale, driverFormat);
      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(1000));
    });

    test('3. Drayver 58.0 mm qog\'oz qaytarganda', () async {
      final driverFormat = const PdfPageFormat(
        58.0 * PdfPageFormat.mm,
        210.0 * PdfPageFormat.mm,
        marginLeft: 0,
        marginRight: 0,
      );

      final bytes = await ReceiptDialogTestHelper.buildPdfBytes(testSale, driverFormat);
      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(1000));
    });
  });
}
