import 'receipt_html_printer_stub.dart'
    if (dart.library.html) 'receipt_html_printer_web.dart';

Future<bool> printReceiptViaWebHtml(String html) => printReceiptHtmlWeb(html);
