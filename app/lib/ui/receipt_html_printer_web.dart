// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

Future<bool> printReceiptHtmlWeb(String html) async {
  try {
    js.context.callMethod('printReceiptHtml', [html]);
    return true;
  } catch (_) {
    return false;
  }
}
