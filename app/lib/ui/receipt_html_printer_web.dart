// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

Future<bool> printReceiptHtmlWeb(String receiptHtml) async {
  try {
    js.context.callMethod('printReceiptHtml', [receiptHtml]);
    return true;
  } catch (_) {
    return false;
  }
}
