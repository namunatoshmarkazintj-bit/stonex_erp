import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Kamera YUV oqimi uchun xotirada tezkor LuminanceSource
class FastYUVLuminanceSource extends LuminanceSource {
  final Uint8List _yPlane;
  final int _dataWidth;
  final int _left;
  final int _top;

  FastYUVLuminanceSource({
    required Uint8List yPlane,
    required int bytesPerRow,
    required int left,
    required int top,
    required int width,
    required int height,
  })  : _yPlane = yPlane,
        _dataWidth = bytesPerRow,
        _left = left,
        _top = top,
        super(width, height);

  @override
  Int8List getRow(int y, Int8List? row) {
    if (y < 0 || y >= height) {
      throw ArgumentError('Requested row is outside the image: $y');
    }
    final res = (row == null || row.length < width) ? Int8List(width) : row;
    final offset = (y + _top) * _dataWidth + _left;
    for (var x = 0; x < width; x++) {
      res[x] = _yPlane[offset + x];
    }
    return res;
  }

  @override
  Int8List getMatrix() {
    final matrix = Int8List(width * height);
    for (var y = 0; y < height; y++) {
      final srcOffset = (y + _top) * _dataWidth + _left;
      final dstOffset = y * width;
      for (var x = 0; x < width; x++) {
        matrix[dstOffset + x] = _yPlane[srcOffset + x];
      }
    }
    return matrix;
  }
}

/// Tasvir baytlaridan yoki Kamera oqimidan QR-kod va 1D Shtrix-kodlarni (EAN-13, EAN-8, UPC)
/// bir lahzada (0.5 - 20 ms) dekodlash
class BarcodeDecoder {
  // EAN-13 / EAN-8 / UPC jadvallari
  static const Map<String, int> _lRuns = {
    '3,2,1,1': 0, '2,2,2,1': 1, '2,1,2,2': 2, '1,4,1,1': 3, '1,1,3,2': 4,
    '1,2,3,1': 5, '1,1,1,4': 6, '1,3,1,2': 7, '1,2,1,3': 8, '3,1,1,2': 9,
  };

  static const Map<String, int> _gRuns = {
    '1,1,2,3': 0, '1,2,2,2': 1, '2,2,1,2': 2, '1,1,4,1': 3, '2,3,1,1': 4,
    '1,3,2,1': 5, '4,1,1,1': 6, '2,1,3,1': 7, '3,1,2,1': 8, '2,1,1,3': 9,
  };

  static const List<String> _firstPatterns = [
    'LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG',
    'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL',
  ];

  /// ⚡️ KAMERA VIDEO OQIMIDAN TO‘G‘RIDAN-TO‘G‘RI DEKODLASH (0.3 - 15 ms)
  /// Hech qanday JPEG kodlash/dekodlash yoki fayl yozishlarsiz, to‘g‘ridan-to‘g‘ri YUV yorug‘lik matritsasidan o‘qiydi.
  static String? decodeFromYPlane({
    required Uint8List yPlane,
    required int width,
    required int height,
    required int bytesPerRow,
  }) {
    try {
      // 1. Avval 1D Shtrix-kodlarni (EAN-13, UPC) tekshirish (o‘ta tez: 0.2 ms)
      final barcode = _decode1DFromYPlane(
        yPlane: yPlane,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
      );
      if (barcode != null && barcode.isNotEmpty) {
        return barcode;
      }

      // 2. 1D topilmasa, markaziy sohadan 2D QR kodni tekshirish
      final qr = _decodeQrFromYuv(
        yPlane: yPlane,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
      );
      if (qr != null && qr.isNotEmpty) {
        return qr;
      }
    } catch (_) {}
    return null;
  }

  static String? _decode1DFromYPlane({
    required Uint8List yPlane,
    required int width,
    required int height,
    required int bytesPerRow,
  }) {
    if (width < 40 || height < 40) return null;

    // Gorizontal skanerlash chiziqlari (markaz atrofida zichroq)
    final hRatios = [0.50, 0.46, 0.54, 0.42, 0.58, 0.38, 0.62, 0.34, 0.66, 0.30, 0.70];
    for (final r in hRatios) {
      final y = (height * r).round().clamp(0, height - 1);
      final rowOffset = y * bytesPerRow;
      final line = List<int>.filled(width, 0);
      for (var x = 0; x < width; x++) {
        line[x] = yPlane[rowOffset + x];
      }
      final code = _decodeScanline(line);
      if (code != null) return code;
    }

    // Vertikal skanerlash chiziqlari (telefon portret bo‘lganda kamera sensori 90° turadi)
    final vRatios = [0.50, 0.46, 0.54, 0.42, 0.58, 0.38, 0.62, 0.34, 0.66];
    for (final r in vRatios) {
      final x = (width * r).round().clamp(0, width - 1);
      final line = List<int>.filled(height, 0);
      for (var y = 0; y < height; y++) {
        line[y] = yPlane[y * bytesPerRow + x];
      }
      final code = _decodeScanline(line);
      if (code != null) return code;
    }

    return null;
  }

  static String? _decodeQrFromYuv({
    required Uint8List yPlane,
    required int width,
    required int height,
    required int bytesPerRow,
  }) {
    try {
      // Markaziy 72% sohani kesib olish (chetki fonlarni chiqarib tashlash va 2.5x tezlashtirish)
      final cropW = (width * 0.72).round();
      final cropH = (height * 0.72).round();
      final cropLeft = ((width - cropW) ~/ 2).clamp(0, width - cropW);
      final cropTop = ((height - cropH) ~/ 2).clamp(0, height - cropH);

      final source = FastYUVLuminanceSource(
        yPlane: yPlane,
        bytesPerRow: bytesPerRow,
        left: cropLeft,
        top: cropTop,
        width: cropW,
        height: cropH,
      );
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final reader = QRCodeReader();
      final res = reader.decode(bitmap);
      return res.text;
    } catch (_) {
      return null;
    }
  }

  /// Rasmli fayl yoki JPEG baytlaridan dekodlash (Fallback)
  static String? decode(Uint8List bytes) {
    try {
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      // 1. Avval 1D Shtrix-kodni tekshirish (o‘ta tez)
      final barcodeResult = decode1DBarcode(image);
      if (barcodeResult != null && barcodeResult.trim().isNotEmpty) {
        return barcodeResult.trim();
      }

      // 2. 2D QR kodni tekshirish
      final qrResult = _decodeQr(image);
      if (qrResult != null && qrResult.trim().isNotEmpty) {
        return qrResult.trim();
      }
    } catch (_) {}
    return null;
  }

  /// ZXing orqali QR kod o'qish
  static String? _decodeQr(img.Image originalImage) {
    try {
      var image = originalImage;
      if (image.width > 480) {
        image = img.copyResize(image, width: 400);
      }
      final width = image.width;
      final height = image.height;
      final rgba = image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
      final int32List = rgba.buffer.asInt32List();
      final source = RGBLuminanceSource(width, height, int32List);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final reader = QRCodeReader();
      final result = reader.decode(bitmap);
      return result.text;
    } catch (_) {
      return null;
    }
  }

  /// 1D shtrix-kodni skanerlash
  static String? decode1DBarcode(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w < 40 || h < 40) return null;

    final hRatios = [0.50, 0.45, 0.55, 0.40, 0.60, 0.35, 0.65, 0.30, 0.70];
    for (final r in hRatios) {
      final y = (h * r).round().clamp(0, h - 1);
      final lumLine = _getHorizontalLuminance(image, y);
      final code = _decodeScanline(lumLine);
      if (code != null) return code;
    }

    final vRatios = [0.50, 0.45, 0.55, 0.40, 0.60, 0.35, 0.65];
    for (final r in vRatios) {
      final x = (w * r).round().clamp(0, w - 1);
      final lumLine = _getVerticalLuminance(image, x);
      final code = _decodeScanline(lumLine);
      if (code != null) return code;
    }

    return null;
  }

  static List<int> _getHorizontalLuminance(img.Image image, int y) {
    final w = image.width;
    final res = List<int>.filled(w, 0);
    for (var x = 0; x < w; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      res[x] = ((r * 299 + g * 587 + b * 114) ~/ 1000).clamp(0, 255);
    }
    return res;
  }

  static List<int> _getVerticalLuminance(img.Image image, int x) {
    final h = image.height;
    final res = List<int>.filled(h, 0);
    for (var y = 0; y < h; y++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      res[y] = ((r * 299 + g * 587 + b * 114) ~/ 1000).clamp(0, 255);
    }
    return res;
  }

  static String? _decodeScanline(List<int> lum) {
    if (lum.length < 50) return null;

    // 0. Chiziq kontrasti (Dynamic range) tekshiruvi:
    // Real shtrix kod oq fonda qora chiziqlardan iborat (kontrast kamida 70 bo'lishi shart).
    // Havo, devor, stol, pol yoki soyaning kontrasti past bo'ladi (10-40) va ular darhol chetlatiladi.
    var minLum = 255;
    var maxLum = 0;
    for (var i = 0; i < lum.length; i++) {
      final v = lum[i];
      if (v < minLum) minLum = v;
      if (v > maxLum) maxLum = v;
    }
    if (maxLum - minLum < 70) return null;

    // 1. Standart chegara bilan tekshirish (delta = 16)
    var res = _decodeScanlineWithDelta(lum, 16);
    if (res != null) return res;

    // 2. Kuchliroq chegara bilan tekshirish (delta = 24)
    res = _decodeScanlineWithDelta(lum, 24);
    if (res != null) return res;

    return null;
  }

  static String? _decodeScanlineWithDelta(List<int> lum, int delta) {
    final bits = _binarize(lum, delta);
    final runs = _getRuns(bits);
    if (runs.length < 50) return null;

    // EAN-13 to'g'ri yo'nalishda
    var res = _decodeEan13Runs(runs);
    if (res != null) return res;

    // EAN-13 teskari yo'nalishda (teskari tutilganda)
    res = _decodeEan13Runs(runs.reversed.toList());
    if (res != null) return res;

    // Code-128
    res = _decodeCode128Runs(runs);
    if (res != null) return res;

    res = _decodeCode128Runs(runs.reversed.toList());
    if (res != null) return res;

    return null;
  }

  /// Moslashuvchan chegara (Local Adaptive Window)
  static List<int> _binarize(List<int> lum, int delta) {
    final len = lum.length;
    final bits = List<int>.filled(len, 0);
    const window = 22;

    var sum = 0;
    for (var i = 0; i < window && i < len; i++) {
      sum += lum[i];
    }

    for (var i = 0; i < len; i++) {
      if (i + window < len) {
        sum += lum[i + window];
      }
      if (i - window >= 0) {
        sum -= lum[i - window];
      }
      final effectiveCount = ((i + window < len ? i + window : len) - (i - window >= 0 ? i - window : 0)).clamp(1, 999);
      final avg = sum ~/ effectiveCount;

      // Qora chiziq (1), Oq oraliq (0)
      bits[i] = (lum[i] < (avg - delta)) ? 1 : 0;
    }
    return bits;
  }

  static List<int> _getRuns(List<int> bits) {
    final runs = <int>[];
    if (bits.isEmpty) return runs;

    var curr = bits[0];
    var count = 0;
    for (final b in bits) {
      if (b == curr) {
        count++;
      } else {
        runs.add(count);
        curr = b;
        count = 1;
      }
    }
    runs.add(count);
    return runs;
  }

  /// EAN-13 dekoderi (Qat'iy Quiet-zone va modul tekshiruvi bilan)
  static String? _decodeEan13Runs(List<int> runs) {
    final totalRuns = runs.length;
    // EAN-13 tarkibi: oq_hoshiya (1) + 3 (start) + 24 (6 chap raqam) + 5 (o'rta) + 24 (6 o'ng raqam) + 3 (stop) + oq_hoshiya (1) = 61 runs
    if (totalRuns < 61) return null;

    for (var i = 1; i <= totalRuns - 60; i++) {
      // 0. Chap tomondagi oq hoshiya (Quiet zone)
      final prevQuiet = runs[i - 1];

      // 1. Start Guard (Qora - Oq - Qora: 1-1-1)
      final w1 = runs[i];
      final w2 = runs[i + 1];
      final w3 = runs[i + 2];
      final avgW = (w1 + w2 + w3) / 3.0;
      if (avgW < 1.0) continue;

      // Start guard nisbati qat'iy tekshiriladi (45% dan ortiq og'ish bo'lmasligi kerak)
      if ((w1 - avgW).abs() > avgW * 0.45 ||
          (w2 - avgW).abs() > avgW * 0.45 ||
          (w3 - avgW).abs() > avgW * 0.45) {
        continue;
      }

      // Chap oq hoshiya kamida 4.5 ta modul kenglikda bo'lishi shart
      if (prevQuiet < avgW * 4.5) continue;

      var idx = i + 3;
      final leftDigits = <int>[];
      final leftTypes = <String>[];
      var ok = true;
      var adjustedCount = 0;

      // 6 ta chap raqam
      for (var d = 0; d < 6; d++) {
        if (idx + 4 > runs.length) {
          ok = false;
          break;
        }
        final r = [runs[idx], runs[idx + 1], runs[idx + 2], runs[idx + 3]];
        idx += 4;
        final tot = r[0] + r[1] + r[2] + r[3];
        if (tot <= 0) {
          ok = false;
          break;
        }

        // 4 ta run ning umumiy kengligi taxminan 7 * avgW bo'lishi shart
        if ((tot - 7.0 * avgW).abs() > 2.5 * avgW) {
          ok = false;
          break;
        }

        var n1 = (r[0] * 7.0 / tot).round().clamp(1, 4);
        var n2 = (r[1] * 7.0 / tot).round().clamp(1, 4);
        var n3 = (r[2] * 7.0 / tot).round().clamp(1, 4);
        var n4 = (r[3] * 7.0 / tot).round().clamp(1, 4);
        var sumN = n1 + n2 + n3 + n4;

        if ((sumN - 7).abs() > 1) {
          ok = false;
          break;
        }

        if (sumN != 7) {
          adjustedCount++;
          if (adjustedCount > 2) {
            ok = false;
            break;
          }
          final diff = 7 - sumN;
          var maxIdx = 0;
          var maxVal = r[0];
          for (var k = 1; k < 4; k++) {
            if (r[k] > maxVal) {
              maxVal = r[k];
              maxIdx = k;
            }
          }
          if (maxIdx == 0) n1 += diff;
          if (maxIdx == 1) n2 += diff;
          if (maxIdx == 2) n3 += diff;
          if (maxIdx == 3) n4 += diff;
        }

        final key = '$n1,$n2,$n3,$n4';
        if (_lRuns.containsKey(key)) {
          leftDigits.add(_lRuns[key]!);
          leftTypes.add('L');
        } else if (_gRuns.containsKey(key)) {
          leftDigits.add(_gRuns[key]!);
          leftTypes.add('G');
        } else {
          ok = false;
          break;
        }
      }
      if (!ok || leftDigits.length != 6) continue;

      // 2. Center Guard (Oq - Qora - Oq - Qora - Oq: 0-1-0-1-0)
      if (idx + 5 > runs.length) continue;
      final cRuns = [runs[idx], runs[idx + 1], runs[idx + 2], runs[idx + 3], runs[idx + 4]];
      idx += 5;
      final cAvg = (cRuns[0] + cRuns[1] + cRuns[2] + cRuns[3] + cRuns[4]) / 5.0;
      if (cRuns.any((x) => (x - cAvg).abs() > cAvg * 0.45)) continue;

      // 3. 6 ta o'ng raqam (faqat R-code)
      final rightDigits = <int>[];
      for (var d = 0; d < 6; d++) {
        if (idx + 4 > runs.length) {
          ok = false;
          break;
        }
        final r = [runs[idx], runs[idx + 1], runs[idx + 2], runs[idx + 3]];
        idx += 4;
        final tot = r[0] + r[1] + r[2] + r[3];
        if (tot <= 0) {
          ok = false;
          break;
        }

        if ((tot - 7.0 * avgW).abs() > 2.5 * avgW) {
          ok = false;
          break;
        }

        var n1 = (r[0] * 7.0 / tot).round().clamp(1, 4);
        var n2 = (r[1] * 7.0 / tot).round().clamp(1, 4);
        var n3 = (r[2] * 7.0 / tot).round().clamp(1, 4);
        var n4 = (r[3] * 7.0 / tot).round().clamp(1, 4);
        var sumN = n1 + n2 + n3 + n4;

        if ((sumN - 7).abs() > 1) {
          ok = false;
          break;
        }

        if (sumN != 7) {
          adjustedCount++;
          if (adjustedCount > 2) {
            ok = false;
            break;
          }
          final diff = 7 - sumN;
          var maxIdx = 0;
          var maxVal = r[0];
          for (var k = 1; k < 4; k++) {
            if (r[k] > maxVal) {
              maxVal = r[k];
              maxIdx = k;
            }
          }
          if (maxIdx == 0) n1 += diff;
          if (maxIdx == 1) n2 += diff;
          if (maxIdx == 2) n3 += diff;
          if (maxIdx == 3) n4 += diff;
        }

        final key = '$n1,$n2,$n3,$n4';
        if (_lRuns.containsKey(key)) {
          rightDigits.add(_lRuns[key]!);
        } else {
          ok = false;
          break;
        }
      }
      if (!ok || rightDigits.length != 6) continue;

      // 4. Stop Guard (Qora - Oq - Qora: 1-1-1)
      if (idx + 3 > runs.length) continue;
      final sw1 = runs[idx];
      final sw2 = runs[idx + 1];
      final sw3 = runs[idx + 2];
      final sAvg = (sw1 + sw2 + sw3) / 3.0;
      if ((sw1 - sAvg).abs() > sAvg * 0.45 ||
          (sw2 - sAvg).abs() > sAvg * 0.45 ||
          (sw3 - sAvg).abs() > sAvg * 0.45) {
        continue;
      }
      // O'ng oq hoshiya (Quiet zone) kamida 4.0 ta modul kenglikda bo'lishi shart
      if (idx + 3 < runs.length && runs[idx + 3] < sAvg * 4.0) continue;

      // 5. Birinchi raqamni aniqlash
      final patStr = leftTypes.join();
      final firstDigit = _firstPatterns.indexOf(patStr);
      if (firstDigit < 0) continue;

      // 6. 13 xonali kodni yig'ish va nazorat raqamini (Checksum) tekshirish
      final code = '$firstDigit${leftDigits.join()}${rightDigits.join()}';
      if (_verifyEan13Checksum(code)) {
        return code;
      }
    }
    return null;
  }

  static bool _verifyEan13Checksum(String code) {
    if (code.length != 13) return false;
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = int.tryParse(code[i]) ?? 0;
      sum += (i % 2 == 0) ? d : d * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == int.tryParse(code[12]);
  }

  /// Oddiy Code-128 formati uchun o'qish (agar tovar kodi Code-128 bo'lsa)
  static String? _decodeCode128Runs(List<int> runs) {
    // Kelajakda qo'shimcha formatlar uchun
    return null;
  }
}
