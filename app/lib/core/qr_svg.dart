import 'package:qr/qr.dart';

/// Generates an inline, crisp, 100% offline SVG QR code tag.
/// Perfect for browser HTML printing and instant thermal printing with zero network delay.
String generateQrSvg(String data, {int size = 110}) {
  try {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);
    final count = qrImage.moduleCount;
    final sb = StringBuffer();
    sb.write(
      '<svg class="qr-svg" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $count $count" '
      'width="${size}px" height="${size}px" shape-rendering="crispEdges" '
      'style="margin: 2px auto; display: block;">',
    );
    sb.write('<rect width="100%" height="100%" fill="#ffffff"/>');
    for (var r = 0; r < count; r++) {
      for (var c = 0; c < count; c++) {
        if (qrImage.isDark(r, c)) {
          sb.write('<rect x="$c" y="$r" width="1" height="1" fill="#000000"/>');
        }
      }
    }
    sb.write('</svg>');
    return sb.toString();
  } catch (_) {
    return '';
  }
}
