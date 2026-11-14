import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../core/qr_svg.dart';
import '../core/theme.dart';
import '../data/local_printer_store.dart';
import '../domain/models.dart';
import 'common.dart';
import 'receipt_html_printer.dart';
import 'return_product_dialog.dart';

String _cleanAscii(String? text) {
  if (text == null || text.isEmpty) return '';
  return text
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('`', "'")
      .replaceAll('ʻ', "'")
      .replaceAll('ʼ', "'")
      .replaceAll('′', "'")
      .replaceAll('‵', "'")
      .replaceAll('´', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('«', '"')
      .replaceAll('»', '"')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('•', ' | ')
      .replaceAll('·', ' | ')
      .replaceAll('∙', ' | ')
      .replaceAll('●', '-')
      .replaceAll('▪', '-')
      .replaceAll('№', 'No.')
      .replaceAll('²', '2')
      .replaceAll('³', '3')
      .replaceAll('€', 'EUR')
      .replaceAll('£', 'GBP')
      .replaceAll('¢', 'c')
      .replaceAll('Ў', "O'")
      .replaceAll('ў', "o'")
      .replaceAll('Ғ', "G'")
      .replaceAll('ғ', "g'")
      .replaceAll('Ш', "Sh")
      .replaceAll('ш', "sh")
      .replaceAll('Ч', "Ch")
      .replaceAll('ч', "ch")
      .replaceAll('Ю', "Yu")
      .replaceAll('ю', "yu")
      .replaceAll('Я', "Ya")
      .replaceAll('я', "ya")
      .replaceAll('Ё', "Yo")
      .replaceAll('ё', "yo")
      .replaceAll('Ц', "Ts")
      .replaceAll('ц', "ts")
      .replaceAll('А', "A")
      .replaceAll('а', "a")
      .replaceAll('Б', "B")
      .replaceAll('б', "b")
      .replaceAll('В', "V")
      .replaceAll('в', "v")
      .replaceAll('Г', "G")
      .replaceAll('г', "g")
      .replaceAll('Д', "D")
      .replaceAll('д', "d")
      .replaceAll('Е', "E")
      .replaceAll('е', "e")
      .replaceAll('Ж', "J")
      .replaceAll('ж', "j")
      .replaceAll('З', "Z")
      .replaceAll('з', "z")
      .replaceAll('И', "I")
      .replaceAll('и', "i")
      .replaceAll('Й', "Y")
      .replaceAll('й', "y")
      .replaceAll('К', "K")
      .replaceAll('к', "k")
      .replaceAll('Л', "L")
      .replaceAll('л', "l")
      .replaceAll('М', "M")
      .replaceAll('м', "m")
      .replaceAll('Н', "N")
      .replaceAll('н', "n")
      .replaceAll('О', "O")
      .replaceAll('о', "o")
      .replaceAll('П', "P")
      .replaceAll('п', "p")
      .replaceAll('Р', "R")
      .replaceAll('р', "r")
      .replaceAll('С', "S")
      .replaceAll('с', "s")
      .replaceAll('Т', "T")
      .replaceAll('т', "t")
      .replaceAll('У', "U")
      .replaceAll('у', "u")
      .replaceAll('Ф', "F")
      .replaceAll('ф', "f")
      .replaceAll('Х', "X")
      .replaceAll('х', "x")
      .replaceAll('Ҳ', "H")
      .replaceAll('ҳ', "h")
      .replaceAll('Ъ', "'")
      .replaceAll('ъ', "'")
      .replaceAll('Ь', "")
      .replaceAll('ь', "")
      .replaceAll('Э', "E")
      .replaceAll('э', "e")
      .replaceAll('Ы', "I")
      .replaceAll('ы', "i");
}

bool isReceiptQr(String code) {
  final c = code.trim().toUpperCase();
  return c.startsWith('NTJ-CHEK-') ||
      c.startsWith('NTJ-SALE-') ||
      c.startsWith('NTJ-') ||
      c.startsWith('NTM-CHEK-') ||
      c.startsWith('NTM-SALE-') ||
      c.startsWith('STONEX-CHEK-') ||
      c.startsWith('STONEX-SALE-') ||
      c.startsWith('CHEK-#') ||
      c.startsWith('CHEK-') ||
      c.startsWith('SALE-#') ||
      RegExp(r'#\d+').hasMatch(c);
}

int? extractSaleId(String code) {
  final reg = RegExp(r'#(\d+)');
  final match = reg.firstMatch(code);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }
  final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits);
}

class ReceiptDialog extends StatefulWidget {
  const ReceiptDialog({super.key, required this.sale});

  final SaleResult sale;

  static Future<void> show(BuildContext context, SaleResult sale) {
    return showDialog<void>(
      context: context,
      builder: (_) => ReceiptDialog(sale: sale),
    );
  }

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  final GlobalKey _receiptKey = GlobalKey();
  bool _isPrinting = false;
  bool _isCapturing = false;

  String _buildPlainText() {
    final sale = widget.sale;
    final is80 = LocalPrinterStore.getSavedPaperWidth() >= 80;
    final cols = is80 ? 48 : 32;
    final dividerDbl = '=' * cols;
    final dividerSgl = '-' * cols;

    String center(String text) {
      if (text.length >= cols) return text;
      final pad = (cols - text.length) ~/ 2;
      return ' ' * pad + text;
    }

    final sb = StringBuffer();
    sb.writeln(dividerDbl);
    sb.writeln(center(_cleanAscii(CompanyInfo.name)));
    sb.writeln(center(_cleanAscii(CompanyInfo.businessType)));
    sb.writeln(center(_cleanAscii('Manzil: ${CompanyInfo.address}')));
    for (final phone in CompanyInfo.phones) {
      sb.writeln(center(_cleanAscii('Tel: $phone')));
    }
    sb.writeln(dividerDbl);
    sb.writeln('Chek No   : #${sale.id.toString().padLeft(6, '0')}');
    sb.writeln('Sana      : ${formatDateTime(sale.createdAt ?? DateTime.now())}');
    sb.writeln('Sotuvchi  : ${_cleanAscii(sale.cashierName ?? 'Kassir')}');
    sb.writeln('To\'lov    : ${sale.paymentMethod == 'karta' ? 'Karta' : 'Naqd'}');
    sb.writeln(
        'Xaridor   : ${_cleanAscii(sale.customerName?.isNotEmpty == true ? sale.customerName : 'Chakana xaridor')}');
    if (sale.customerPhone?.isNotEmpty == true) {
      sb.writeln('Tel       : ${sale.customerPhone}');
    }
    sb.writeln(dividerSgl);
    if (is80) {
      sb.writeln('Nomi                          Miqdor       Summa');
    } else {
      sb.writeln('Nomi            Miqdor      Jami');
    }
    sb.writeln(dividerSgl);
    final nameMax = is80 ? 28 : 14;
    final qtyMax = is80 ? 7 : 6;
    for (final it in sale.items) {
      final cleanName = _cleanAscii(it.productName);
      final name = cleanName.length > nameMax
          ? '${cleanName.substring(0, nameMax - 2)}..'
          : cleanName.padRight(nameMax);
      final qStr = it.quantity.toStringAsFixed(1).padLeft(qtyMax);
      final total = money(it.lineTotal);
      if (is80) {
        final totalStr = total.padLeft(cols - nameMax - qtyMax - 2);
        sb.writeln('$name  $qStr$totalStr');
      } else {
        final totalStr = total.padLeft(cols - nameMax - qtyMax - 1);
        sb.writeln('$name $qStr$totalStr');
      }
    }
    sb.writeln(dividerDbl);
    if (sale.currencyRate != null && sale.currencyRate! > 0) {
      final rate = sale.currencyRate!;
      final totalUsd = sale.total / rate;
      sb.writeln('JAMI (So\'m)    : ${money(sale.total)}');
      sb.writeln('JAMI (\$ USD)   : ${moneyUsd(totalUsd)}');
      sb.writeln('Kurs (\$1 =)    : ${money(rate)}');
    } else {
      sb.writeln('JAMI SUMMA     : ${money(sale.total)}');
    }
    sb.writeln(
        'To\'landi       : ${money(sale.paid)} (${sale.paymentMethod == 'karta' ? 'Karta' : 'Naqd'})');
    if (sale.paidUsd != null && sale.paidUsd! > 0) {
      sb.writeln('To\'lov tafsili : ${money(sale.paidUzs ?? 0)} + ${moneyUsd(sale.paidUsd!)}');
    }
    if (sale.debt > 0.005) {
      sb.writeln('Qoldiq nasiya  : ${money(sale.debt)}');
    }
    sb.writeln(dividerSgl);
    sb.writeln('Qaytarish muddati: ${sale.returnDays} kun (${formatDate(sale.returnDeadline)} gacha)');
    sb.writeln('(Mahsulot butun va chek taqdim etilganda)');
    sb.writeln(dividerDbl);
    sb.writeln(center('Xaridingiz uchun tashakkur!'));
    sb.writeln(center('NTJ - Namuna Tosh Jilo'));
    sb.writeln(dividerDbl);
    return sb.toString();
  }

  Future<Uint8List?> _captureReceiptPng() async {
    try {
      final boundary =
          _receiptKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _viewReceiptImage(BuildContext context) async {
    setState(() => _isCapturing = true);
    final bytes = await _captureReceiptPng();
    if (!mounted) return;
    setState(() => _isCapturing = false);

    if (bytes == null) {
      showMessage(context, 'Chek rasmini hosil qilib bo‘lmadi', error: true);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SingleChildScrollView(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    _copyToClipboard(context);
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.neonLime,
                    foregroundColor: AppColors.ink,
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Matnni nusxalash'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white24,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Yopish'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildReceiptHtml(SaleResult sale, bool is58mm) {
    final companyName = _cleanAscii(CompanyInfo.name);
    final businessType = _cleanAscii(CompanyInfo.businessType);
    final address = _cleanAscii(CompanyInfo.address);
    final phones = _cleanAscii(CompanyInfo.phonesInline);
    final cashier = _cleanAscii(sale.cashierName ?? 'Kassir');
    final customer = _cleanAscii(sale.customerName?.isNotEmpty == true ? sale.customerName : 'Chakana xaridor');
    final customerPhone = _cleanAscii(sale.customerPhone);
    final widthCss = is58mm ? '54mm' : '72mm';
    final pageSize = is58mm ? '58mm auto' : '80mm auto';
    final fontSize = is58mm ? '11px' : '12.5px';
    final titleSize = is58mm ? '14px' : '16px';
    final qrData = 'NTJ-CHEK-#${sale.id}-${sale.total.round()}UZS';
    final qrSvgTag = generateQrSvg(qrData, size: is58mm ? 95 : 120);

    final itemsHtml = StringBuffer();
    for (final item in sale.items) {
      final name = _cleanAscii(item.productName);
      final qty = item.quantity.toStringAsFixed(1);
      final total = _cleanAscii(money(item.lineTotal));
      itemsHtml.writeln('''
        <tr>
          <td style="text-align: left; padding: 2px 0;">$name</td>
          <td style="text-align: center; padding: 2px 0;">$qty</td>
          <td style="text-align: right; padding: 2px 0;">$total</td>
        </tr>
      ''');
    }

    String usdHtml = '';
    if (sale.currencyRate != null && sale.currencyRate! > 0) {
      final totalUsd = _cleanAscii(moneyUsd(sale.total / sale.currencyRate!));
      final rate = _cleanAscii(money(sale.currencyRate!));
      usdHtml = '''
        <div style="display: flex; justify-content: space-between; font-size: ${is58mm ? '11px' : '12px'};">
          <span>USD (\$):</span>
          <span style="font-weight: bold;">$totalUsd</span>
        </div>
        <div style="display: flex; justify-content: space-between; font-size: ${is58mm ? '10px' : '11px'}; color: #333;">
          <span>Kurs (\$1 =):</span>
          <span>$rate</span>
        </div>
      ''';
    }

    String debtHtml = '';
    if (sale.debt > 0.005) {
      debtHtml = '''
        <div style="display: flex; justify-content: space-between; font-size: ${is58mm ? '11px' : '12px'}; font-weight: bold; color: #b91c1c;">
          <span>Qarz (Nasiya):</span>
          <span>${_cleanAscii(money(sale.debt))}</span>
        </div>
      ''';
    }

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Chek #${sale.id}</title>
  <style>
    @page {
      size: $pageSize;
      margin: 0;
    }
    @media print {
      html, body {
        width: $widthCss;
        margin: 0 auto;
        padding: 2mm 0;
      }
      .no-print { display: none !important; }
    }
    body {
      font-family: 'Courier New', Courier, 'Lucida Console', monospace;
      font-size: $fontSize;
      font-weight: 500;
      line-height: 1.32;
      letter-spacing: 0px;
      color: #000;
      background: #fff;
      width: $widthCss;
      margin: 0 auto;
      padding: 4px;
      box-sizing: border-box;
      -webkit-print-color-adjust: exact;
    }
    .text-center { text-align: center; }
    .text-left { text-align: left; }
    .text-right { text-align: right; }
    .bold { font-weight: bold; }
    .dashed { border-top: 1px dashed #000; margin: 5px 0; }
    .double-line { border-top: 1px solid #000; border-bottom: 1px solid #000; height: 2px; margin: 5px 0; }
    .flex-row { display: flex; justify-content: space-between; margin-bottom: 2px; }
    table { width: 100%; border-collapse: collapse; font-size: $fontSize; font-family: inherit; }
  </style>
</head>
<body>
  <div class="text-center bold" style="font-size: $titleSize; letter-spacing: 0.5px;">$companyName</div>
  <div class="text-center" style="font-size: ${is58mm ? '9px' : '10.5px'};">$businessType</div>
  <div class="text-center" style="font-size: ${is58mm ? '8.5px' : '10px'};">Manzil: $address</div>
  <div class="text-center" style="font-size: ${is58mm ? '8.5px' : '10px'};">Tel: $phones</div>

  <div class="double-line"></div>

  <div class="flex-row">
    <span class="bold">Chek No        : #${sale.id.toString().padLeft(6, '0')}</span>
    <span>${formatDateTime(sale.createdAt ?? DateTime.now())}</span>
  </div>
  <div class="flex-row">
    <span>Sotuvchi       : $cashier</span>
    <span>To'lov: ${sale.paymentMethod == 'karta' ? 'Karta' : 'Naqd'}</span>
  </div>
  <div class="text-left" style="margin-bottom: 2px;">
    <span class="bold">Xaridor       :</span> $customer ${customerPhone.isNotEmpty ? "($customerPhone)" : ''}
  </div>

  <div class="dashed"></div>

  <table>
    <thead>
      <tr style="border-bottom: 1px dashed #000;">
        <th style="text-align: left; padding-bottom: 3px;">Nomi</th>
        <th style="text-align: center; padding-bottom: 3px;">Miqdor</th>
        <th style="text-align: right; padding-bottom: 3px;">Summa</th>
      </tr>
    </thead>
    <tbody>
      $itemsHtml
    </tbody>
  </table>

  <div class="dashed"></div>

  <div class="flex-row bold" style="font-size: ${is58mm ? '13px' : '15px'};">
    <span>JAMI:</span>
    <span>${_cleanAscii(money(sale.total))}</span>
  </div>

  $usdHtml

  <div class="flex-row">
    <span>To'landi:</span>
    <span class="bold">${_cleanAscii(money(sale.paid))}</span>
  </div>

  $debtHtml

  <div class="dashed"></div>

  <div class="text-center bold" style="font-size: ${is58mm ? '9px' : '10.5px'}; margin-top: 4px;">
    Qaytarish muddati: ${sale.returnDays} kun (${formatDate(sale.returnDeadline)} gacha)
  </div>
  <div class="text-center" style="font-size: ${is58mm ? '8px' : '9.5px'}; color: #333;">
    (Mahsulot butun va chek taqdim etilganda)
  </div>

  <div class="text-center" style="margin-top: 6px;">
    $qrSvgTag
  </div>

  <div class="text-center" style="margin-top: 6px; font-size: ${is58mm ? '10px' : '11.5px'};">
    <div class="bold">Xaridingiz uchun tashakkur!</div>
    <div style="color: #444; font-size: ${is58mm ? '8.5px' : '10px'};">NTJ - Namuna Tosh Jilo</div>
  </div>

  <!-- Avto-kesgich (Cutter) uchun bo'sh joy -->
  <div style="height: 18mm;"></div>
</body>
</html>
''';
  }

  Future<void> _printPdf(BuildContext context, {bool forcePickPrinter = false, bool forcePdf = false}) async {
    final sale = widget.sale;
    setState(() => _isPrinting = true);

    try {
      final paperWidthMm = LocalPrinterStore.getSavedPaperWidth();
      final is58mm = paperWidthMm <= 58;

      // Web muhitida birinchi navbatda Brauzer HTML chop etish ishlatiladi (drayversiz ham toza monospaced chiqadi)
      if (kIsWeb && !forcePickPrinter && !forcePdf) {
        final ok = await printReceiptViaWebHtml(_buildReceiptHtml(sale, is58mm));
        if (ok) {
          if (mounted) {
            showMessage(context, '✓ Brauzer chop etish oynasi ochildi (Oddiy shrift)');
          }
          return;
        }
      }

      final doc = pw.Document();
      // "Oddiy shrift" (standart Courier monospaced) — hech qanday internet yuklashlarsiz,
      // baytlar chalkashmasdan, xitoycha iyerogliflarsiz toza chiqadi!
      final font = pw.Font.courier();
      final fontBold = pw.Font.courierBold();

      final pdfPageWidth = (is58mm ? 58.0 : 80.0) * PdfPageFormat.mm;
      final pdfMargin = (is58mm ? 2.0 : 4.0) * PdfPageFormat.mm;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            pdfPageWidth,
            double.infinity,
            marginAll: pdfMargin,
          ),
          build: (pw.Context ctx) {
            return pw.Container(
              padding: pw.EdgeInsets.all(is58mm ? 2 : 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    _cleanAscii(CompanyInfo.name),
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: is58mm ? 11 : 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    _cleanAscii(CompanyInfo.businessType),
                    style: pw.TextStyle(font: font, fontSize: is58mm ? 7.0 : 8.5),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    _cleanAscii('Manzil: ${CompanyInfo.address}'),
                    style: pw.TextStyle(font: font, fontSize: is58mm ? 6.5 : 8),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    _cleanAscii('Tel: ${CompanyInfo.phonesInline}'),
                    style: pw.TextStyle(font: font, fontSize: is58mm ? 6.5 : 8),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(_cleanAscii('Chek No: #${sale.id.toString().padLeft(6, '0')}'),
                          style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7.5 : 9)),
                      pw.Text(formatDateTime(sale.createdAt ?? DateTime.now()),
                          style: pw.TextStyle(font: font, fontSize: is58mm ? 6.8 : 8)),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(_cleanAscii('Sotuvchi: ${sale.cashierName ?? 'Kassir'}'),
                            style: pw.TextStyle(font: font, fontSize: is58mm ? 6.8 : 8)),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Text(_cleanAscii("To'lov: ${sale.paymentMethod == 'karta' ? 'Karta' : 'Naqd'}"),
                          style: pw.TextStyle(font: font, fontSize: is58mm ? 6.8 : 8)),
                    ],
                  ),
                  if (sale.customerName?.isNotEmpty == true) ...[
                    pw.SizedBox(height: 2),
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        _cleanAscii('Xaridor: ${sale.customerName} ${sale.customerPhone ?? ''}'),
                        style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 6.8 : 8),
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 4),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed),
                  pw.SizedBox(height: 3),
                  // Mahsulotlar ro'yxati
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text('Nomi',
                            style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8.5)),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text('Miqdor',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8.5)),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text('Summa',
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7 : 8.5)),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  for (final item in sale.items) ...[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          flex: 5,
                          child: pw.Text(_cleanAscii(item.productName),
                              style: pw.TextStyle(font: font, fontSize: is58mm ? 6.8 : 8)),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            item.quantity.toStringAsFixed(1),
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: font, fontSize: is58mm ? 6.8 : 8),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            _cleanAscii(money(item.lineTotal)),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(font: font, fontSize: is58mm ? 6.8 : 8),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                  ],
                  pw.SizedBox(height: 3),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('JAMI:',
                          style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 9.5 : 11.5)),
                      pw.Text(_cleanAscii(money(sale.total)),
                          style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 9.5 : 11.5)),
                    ],
                  ),
                  if (sale.currencyRate != null && sale.currencyRate! > 0) ...[
                    pw.SizedBox(height: 1),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('USD (\$):',
                            style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7.5 : 9)),
                        pw.Text(_cleanAscii(moneyUsd(sale.total / sale.currencyRate!)),
                            style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7.5 : 9)),
                      ],
                    ),
                    pw.SizedBox(height: 1),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Kurs (\$1 =):',
                            style: pw.TextStyle(font: font, fontSize: is58mm ? 6.5 : 8)),
                        pw.Text(_cleanAscii(money(sale.currencyRate!)),
                            style: pw.TextStyle(font: font, fontSize: is58mm ? 6.5 : 8)),
                      ],
                    ),
                  ],
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("To'landi:",
                          style: pw.TextStyle(font: font, fontSize: is58mm ? 7.5 : 9)),
                      pw.Text(_cleanAscii(money(sale.paid)),
                          style: pw.TextStyle(font: font, fontSize: is58mm ? 7.5 : 9)),
                    ],
                  ),
                  if (sale.debt > 0.005) ...[
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Qarz (Nasiya):',
                            style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7.5 : 9, color: PdfColors.red800)),
                        pw.Text(_cleanAscii(money(sale.debt)),
                            style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 7.5 : 9, color: PdfColors.red800)),
                      ],
                    ),
                  ],
                  pw.SizedBox(height: 5),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          _cleanAscii('Qaytarish muddati: ${sale.returnDays} kun (${formatDate(sale.returnDeadline)} gacha)'),
                          style: pw.TextStyle(font: fontBold, fontSize: is58mm ? 6.2 : 7.8),
                          textAlign: pw.TextAlign.center,
                        ),
                        pw.SizedBox(height: 1),
                        pw.Text(
                          _cleanAscii('(Mahsulot butun va chek taqdim etilganda)'),
                          style: pw.TextStyle(font: font, fontSize: is58mm ? 5.5 : 6.5, color: PdfColors.grey700),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.BarcodeWidget(
                    data: 'NTJ-CHEK-#${sale.id}-${sale.total.round()}UZS',
                    barcode: pw.Barcode.qrCode(),
                    width: is58mm ? 40 : 54,
                    height: is58mm ? 40 : 54,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Xaridingiz uchun tashakkur!',
                      style: pw.TextStyle(font: font, fontSize: is58mm ? 7 : 8.5),
                      textAlign: pw.TextAlign.center),
                  pw.Text('NTJ - Namuna Tosh Jilo',
                      style: pw.TextStyle(font: font, fontSize: is58mm ? 6 : 7.5, color: PdfColors.grey700),
                      textAlign: pw.TextAlign.center),
                  // Kesish pichog'i uchun bo'sh joy
                  pw.SizedBox(height: 20 * PdfPageFormat.mm),
                ],
              ),
            );
          },
        ),
      );

      // Web muhitida Printing.layoutPdf orqali chiqariladi (listPrinters chaqirilmaydi!)
      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (format) async => doc.save(),
          name: 'Chek_${sale.id}.pdf',
        );
        return;
      }

      // Windows desktop muhiti uchun:
      final savedUrl = LocalPrinterStore.getSavedPrinterUrl();
      Printer? targetPrinter;

      if (!forcePickPrinter && savedUrl != null && savedUrl.isNotEmpty) {
        try {
          final printers = await Printing.listPrinters();
          targetPrinter = printers.where((p) => p.url == savedUrl).firstOrNull;
        } catch (_) {}
      }

      // Agar majburiy almashtirish so'ralsa
      if (forcePickPrinter) {
        if (!mounted) return;
        targetPrinter = await _showPrinterPickerDialog(context);
        if (targetPrinter == null && mounted) {
          // Foydalanuvchi tizim dialogini tanlagan bo'lsa
          await Printing.layoutPdf(
            onLayout: (format) async => doc.save(),
            name: 'Chek_${sale.id}.pdf',
          );
          return;
        }
      }

      if (targetPrinter != null) {
        // Doimiy printerga to'g'ridan-to'g'ri (1-click, ortiqcha oynasiz) chiqarish!
        await Printing.directPrintPdf(
          printer: targetPrinter,
          onLayout: (format) async => doc.save(),
          name: 'Chek_${sale.id}.pdf',
        );
        if (mounted) {
          showMessage(context, '✓ "${targetPrinter.name}" printeriga yuborildi');
        }
      } else {
        // Birinchi marta tizimda printerlar bo'lsa, tanlashni taklif qilamiz
        final printers = await Printing.listPrinters();
        if (printers.isNotEmpty && savedUrl == null) {
          if (!mounted) return;
          final chosen = await _showPrinterPickerDialog(context);
          if (chosen != null) {
            await Printing.directPrintPdf(
              printer: chosen,
              onLayout: (format) async => doc.save(),
              name: 'Chek_${sale.id}.pdf',
            );
            if (mounted) {
              showMessage(context, '✓ "${chosen.name}" printeriga yuborildi');
            }
            return;
          }
        }

        await Printing.layoutPdf(
          onLayout: (format) async => doc.save(),
          name: 'Chek_${sale.id}.pdf',
        );
      }
    } on MissingPluginException {
      // Dastur hot-reload bo'lganda native plugin ulanmagan bo'lsa
      if (context.mounted) {
        _showPluginNotice(context);
      }
    } catch (e) {
      if (context.mounted) {
        if (e.toString().contains('MissingPluginException') ||
            e.toString().contains('net.nfet.printing')) {
          _showPluginNotice(context);
        } else {
          showMessage(context, 'Chop etishda xatolik: $e', error: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _showPluginNotice(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 24),
            SizedBox(width: 10),
            Text('Printer Ulanishi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Yangi "printing" moduli qo‘shilgani sababli, Windows/Android printer drayverini to‘liq ulash uchun ilovani bir marta o‘chirib qayta yoqish (restart) lozim.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 10),
            Text(
              'Hozir esa chek rasmini to‘liq ko‘rishingiz, nusxa olishingiz yoki mijozga Telegram orqali yuborishingiz mumkin!',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.green),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Yopish'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _viewReceiptImage(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.neonLime,
              foregroundColor: AppColors.ink,
            ),
            icon: const Icon(Icons.image_rounded, size: 16),
            label: const Text('Chek Rasmini Ko‘rish'),
          ),
        ],
      ),
    );
  }

  Future<Printer?> _showPrinterPickerDialog(BuildContext context) async {
    List<Printer> printers = [];
    if (!kIsWeb) {
      try {
        printers = await Printing.listPrinters();
      } catch (_) {}
    }

    if (!context.mounted) return null;

    bool remember = true;
    Printer? selected;
    int currentWidth = LocalPrinterStore.getSavedPaperWidth();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: context.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.print_rounded, color: Color(0xFF10B981), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Chek printerini tanlang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Qog'oz lentasi kengligini tanlash
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Qog‘oz lentasi o‘lchami:',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('58 mm (Xprinter)'),
                              selected: currentWidth == 58,
                              selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: currentWidth == 58 ? FontWeight.w800 : FontWeight.w500,
                                color: currentWidth == 58 ? const Color(0xFF047857) : Colors.black87,
                              ),
                              onSelected: (val) {
                                if (val) {
                                  setDlgState(() => currentWidth = 58);
                                  LocalPrinterStore.savePaperWidth(58);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('80 mm (Katta)'),
                              selected: currentWidth == 80,
                              selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: currentWidth == 80 ? FontWeight.w800 : FontWeight.w500,
                                color: currentWidth == 80 ? const Color(0xFF047857) : Colors.black87,
                              ),
                              onSelected: (val) {
                                if (val) {
                                  setDlgState(() => currentWidth = 80);
                                  LocalPrinterStore.savePaperWidth(80);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (printers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Tizimda ulangan printer topilmadi. Tizim oynasi orqali chop etishingiz mumkin.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: printers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final p = printers[idx];
                        final isSaved = p.url == LocalPrinterStore.getSavedPrinterUrl();
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          leading: Icon(
                            p.isDefault ? Icons.star_rounded : Icons.print_outlined,
                            color: isSaved ? const Color(0xFF10B981) : (p.isDefault ? const Color(0xFFF59E0B) : Colors.grey.shade700),
                          ),
                          title: Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSaved ? FontWeight.w800 : FontWeight.w600,
                              color: isSaved ? const Color(0xFF10B981) : null,
                            ),
                          ),
                          subtitle: Text(
                            p.isDefault ? 'Standart printer' : (p.model ?? 'Ulangan printer'),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: isSaved
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('Doimiy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
                                )
                              : null,
                          onTap: () {
                            selected = p;
                            if (remember) {
                              LocalPrinterStore.savePrinter(p.url, p.name, currentWidth);
                              if (mounted) setState(() {});
                            }
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: remember,
                  activeColor: const Color(0xFF10B981),
                  title: const Text(
                    'Har doim shu printerdan foydalanish (Eslab qolish)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onChanged: (v) => setDlgState(() => remember = v ?? true),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Tizim oynasi orqali chop etish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  onPressed: () {
                    selected = null;
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Bekor qilish'),
            ),
          ],
        ),
      ),
    );

    return selected;
  }

  void _copyToClipboard(BuildContext context) {
    final text = _buildPlainText();
    Clipboard.setData(ClipboardData(text: text));
    showMessage(context, 'Chek matni nusxalandi (Telegram yoki SMS uchun tayyor)');
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 750),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFBFBFB),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top header with close button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E242B),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.neonLime.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.receipt_long_rounded,
                                color: AppColors.neonLime, size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Kassa Cheki',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        tooltip: 'Yopish',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Printable paper receipt body wrapped in RepaintBoundary for image capture
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: RepaintBoundary(
                      key: _receiptKey,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Brand
                            Center(
                              child: Text(
                                CompanyInfo.name,
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111827),
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Center(
                              child: Text(
                                CompanyInfo.businessType,
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 11,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Center(
                              child: Text(
                                'Manzil: ${CompanyInfo.address}',
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 10,
                                  color: Color(0xFF6B7280),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Center(
                              child: Text(
                                'Tel: ${CompanyInfo.phonesFormatted}',
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 10,
                                  color: Color(0xFF6B7280),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _dashedLine(),
                            const SizedBox(height: 10),

                            // Chek no & date
                            _receiptRow(
                              'Chek raqami:',
                              '#${sale.id.toString().padLeft(6, '0')}',
                              isBold: true,
                            ),
                            const SizedBox(height: 4),
                            _receiptRow(
                              'Sana va vaqt:',
                              formatDateTime(sale.createdAt ?? DateTime.now()),
                            ),
                            const SizedBox(height: 4),
                            _receiptRow(
                              'Sotuvchi (Kassir):',
                              sale.cashierName ?? 'Kassir',
                            ),
                            const SizedBox(height: 4),
                            _receiptRow(
                              'Xaridor:',
                              sale.customerName?.isNotEmpty == true
                                  ? sale.customerName!
                                  : 'Chakana xaridor',
                              isBold: sale.customerName?.isNotEmpty == true,
                            ),
                            if (sale.customerPhone?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              _receiptRow('Telefon:', sale.customerPhone!),
                            ],
                            if (sale.customerPassport?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              _receiptRow('Pasport:', sale.customerPassport!),
                            ],

                            const SizedBox(height: 12),
                            _dashedLine(),
                            const SizedBox(height: 10),

                            // Table header
                            const Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text('Mahsulot',
                                      style: TextStyle(
                                          fontFamily: 'Courier',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF374151))),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('Miqdor',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontFamily: 'Courier',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF374151))),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text('Summa',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontFamily: 'Courier',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF374151))),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            const SizedBox(height: 6),

                            // Items
                            for (final item in sale.items) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.productName,
                                            style: const TextStyle(
                                              fontFamily: 'Courier',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                          Text(
                                            '${money(item.unitPrice)} / birlik',
                                            style: const TextStyle(
                                              fontFamily: 'Courier',
                                              fontSize: 10,
                                              color: Color(0xFF9CA3AF),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item.quantity.toStringAsFixed(1),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'Courier',
                                          fontSize: 12,
                                          color: Color(0xFF374151),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        money(item.lineTotal),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontFamily: 'Courier',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 10),
                            _dashedLine(),
                            const SizedBox(height: 10),

                            // Totals
                            _receiptRow(
                              'JAMI:',
                              money(sale.total),
                              isBold: true,
                              fontSize: 15,
                              valueColor: const Color(0xFF111827),
                            ),
                            if (sale.currencyRate != null && sale.currencyRate! > 0) ...[
                              const SizedBox(height: 3),
                              _receiptRow(
                                'AQSH DOLLARI:',
                                moneyUsd(sale.total / sale.currencyRate!),
                                isBold: true,
                                fontSize: 13,
                                valueColor: const Color(0xFF047857),
                              ),
                              const SizedBox(height: 2),
                              _receiptRow(
                                'Kurs (\$1 =):',
                                money(sale.currencyRate!),
                                fontSize: 11,
                                valueColor: const Color(0xFF6B7280),
                              ),
                            ],
                            const SizedBox(height: 5),
                            _receiptRow(
                              'To‘landi (${sale.paymentMethod == 'karta' ? 'Karta' : 'Naqd'}):',
                              money(sale.paid),
                              fontSize: 13,
                              valueColor: const Color(0xFF059669),
                            ),
                            if (sale.paidUsd != null && sale.paidUsd! > 0) ...[
                              const SizedBox(height: 2),
                              _receiptRow(
                                'To‘lov tafsili:',
                                '${money(sale.paidUzs ?? 0)} + ${moneyUsd(sale.paidUsd!)}',
                                fontSize: 11,
                                valueColor: const Color(0xFF4B5563),
                              ),
                            ],
                            if (sale.debt > 0.005) ...[
                              const SizedBox(height: 5),
                              _receiptRow(
                                'Qoldiq nasiya:',
                                money(sale.debt),
                                isBold: true,
                                fontSize: 13,
                                valueColor: const Color(0xFFDC2626),
                              ),
                            ],

                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.assignment_return_outlined, size: 13, color: Color(0xFF1E293B)),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          'Qaytarish muddati: ${sale.returnDays} kun (${formatDate(sale.returnDeadline)} gacha)',
                                          style: const TextStyle(
                                            fontFamily: 'Courier',
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    '(Mahsulot butun va chek taqdim etilganda)',
                                    style: TextStyle(
                                      fontFamily: 'Courier',
                                      fontSize: 8.5,
                                      color: Color(0xFF64748B),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),
                            Center(
                              child: SizedBox(
                                width: 85,
                                height: 85,
                                child: QrImageView(
                                  data: 'NTJ-CHEK-#${sale.id}-${sale.total.round()}UZS',
                                  version: QrVersions.auto,
                                  size: 85.0,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF1F2937),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Center(
                              child: Text(
                                'Xaridingiz uchun tashakkur!\nNTJ — Namuna Tosh Jilo',
                                style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 10,
                                  color: Color(0xFF6B7280),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom action buttons
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _copyToClipboard(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E293B),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        label: const Text(
                          'Nusxa olish',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isCapturing ? null : () => _viewReceiptImage(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E293B),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.image_rounded, size: 15),
                        label: const Text(
                          'Chek Rasmi',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                      if (widget.sale.status != 'cancelled')
                        FilledButton.icon(
                          onPressed: widget.sale.status == 'returned'
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  ReturnProductDialog.show(context, widget.sale);
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade400,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.assignment_return_rounded, size: 15),
                          label: Text(
                            widget.sale.status == 'returned' ? 'Qaytarilgan' : 'Qaytarish (10 kun)',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                      Builder(
                        builder: (ctx) {
                          final savedPrinterName = LocalPrinterStore.getSavedPrinterName();
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton.icon(
                                onPressed: _isPrinting ? null : () => _printPdf(context),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.horizontal(
                                      left: const Radius.circular(12),
                                      right: (savedPrinterName != null && !kIsWeb) ? Radius.zero : const Radius.circular(12),
                                    ),
                                  ),
                                ),
                                icon: _isPrinting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.print_rounded, size: 15),
                                label: Text(
                                  kIsWeb
                                      ? 'Chop etish (Brauzer / Oddiy shrift)'
                                      : (savedPrinterName != null
                                          ? 'Chop etish (${savedPrinterName.length > 14 ? "${savedPrinterName.substring(0, 12)}.." : savedPrinterName})'
                                          : 'Chop etish'),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                              ),
                              if (savedPrinterName != null && !kIsWeb)
                                Container(
                                  height: 38,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF059669),
                                    borderRadius: BorderRadius.horizontal(right: Radius.circular(12)),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.tune_rounded, size: 16, color: Colors.white),
                                    tooltip: 'Printerni almashtirish ($savedPrinterName)',
                                    onPressed: _isPrinting ? null : () => _printPdf(context, forcePickPrinter: true),
                                  ),
                                ),
                              if (kIsWeb) ...[
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  tooltip: 'Chop etish turi',
                                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                                  onSelected: (val) {
                                    if (val == 'html') {
                                      _printPdf(context, forcePdf: false);
                                    } else if (val == 'pdf') {
                                      _printPdf(context, forcePdf: true);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'html',
                                      child: Row(
                                        children: [
                                          Icon(Icons.print_rounded, size: 16, color: Color(0xFF10B981)),
                                          SizedBox(width: 8),
                                          Text('Brauzer orqali (Tavsiya / Oddiy)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'pdf',
                                      child: Row(
                                        children: [
                                          Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFEF4444)),
                                          SizedBox(width: 8),
                                          Text('PDF orqali chop etish', style: TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _dashedLine() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 7).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => const SizedBox(
              width: 4,
              height: 1.2,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFCBD5E1)),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _receiptRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 12,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: fontSize,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}
