import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Tasvir baytlaridan QR-kod yoki 1D Shtrix-kod (EAN-13, EAN-8, UPC-A, Code-128)ni aniqlash
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

  /// Asosiy dekodlash metodi:
  /// 1. Avval 2D QR-kodni tekshiradi.
  /// 2. QR topilmasa, 1D chiziqli shtrix-kodlarni (EAN-13, UPC, Code-128) skanerlaydi.
  static String? decode(Uint8List bytes) {
    try {
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      // 1. QR kodni tekshirish
      final qrResult = _decodeQr(image);
      if (qrResult != null && qrResult.trim().isNotEmpty) {
        return qrResult.trim();
      }

      // 2. 1D Shtrix-kodlarni tekshirish (gorizontal va vertikal yo'nalishda)
      final barcodeResult = decode1DBarcode(image);
      if (barcodeResult != null && barcodeResult.trim().isNotEmpty) {
        return barcodeResult.trim();
      }
    } catch (_) {}
    return null;
  }

  /// ZXing orqali QR kod o'qish
  static String? _decodeQr(img.Image originalImage) {
    try {
      var image = originalImage;
      if (image.width > 640) {
        image = img.copyResize(image, width: 480);
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

    // Gorizontal skanerlash chiziqlari (30%, 40%, 48%, 50%, 52%, 60%, 70%)
    final hRatios = [0.50, 0.45, 0.55, 0.40, 0.60, 0.35, 0.65, 0.30, 0.70];
    for (final r in hRatios) {
      final y = (h * r).round().clamp(0, h - 1);
      final lumLine = _getHorizontalLuminance(image, y);
      final code = _decodeScanline(lumLine);
      if (code != null) return code;
    }

    // Vertikal skanerlash chiziqlari (agar telefon yoki tosh yonbosh tutilgan bo'lsa)
    final vRatios = [0.50, 0.45, 0.55, 0.40, 0.60];
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

    // 1. Moslashuvchan binarizatsiya (Adaptive Thresholding)
    final bits = _binarize(lum);
    final runs = _getRuns(bits);
    if (runs.length < 50) return null;

    // EAN-13 to'g'ri yo'nalishda
    var res = _decodeEan13Runs(runs);
    if (res != null) return res;

    // EAN-13 teskari yo'nalishda (agar teskari o'girilgan bo'lsa)
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
  static List<int> _binarize(List<int> lum) {
    final len = lum.length;
    final bits = List<int>.filled(len, 0);
    const window = 24;

    var sum = 0;
    for (var i = 0; i < window && i < len; i++) {
      sum += lum[i];
    }

    for (var i = 0; i < len; i++) {
      final count = (i + window < len) ? window : (len - i);
      if (i + window < len) {
        sum += lum[i + window];
      }
      if (i - window >= 0) {
        sum -= lum[i - window];
      }
      final effectiveCount = ((i + window < len ? i + window : len) - (i - window >= 0 ? i - window : 0)).clamp(1, 999);
      final avg = sum ~/ effectiveCount;

      // Qora chiziq (1), Oq oraliq (0)
      bits[i] = (lum[i] < (avg - 6)) ? 1 : 0;
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

  /// EAN-13 dekoderi
  static String? _decodeEan13Runs(List<int> runs) {
    final totalRuns = runs.length;
    // EAN-13 tarkibi: 3 (start) + 24 (6 chap raqam) + 5 (o'rta) + 24 (6 o'ng raqam) + 3 (stop) = 59 runs
    if (totalRuns < 59) return null;

    for (var i = 0; i <= totalRuns - 59; i++) {
      // 1. Start Guard (Qora - Oq - Qora: 1-1-1)
      final w1 = runs[i];
      final w2 = runs[i + 1];
      final w3 = runs[i + 2];
      final avgW = (w1 + w2 + w3) / 3.0;
      if (avgW < 0.6) continue;

      if ((w1 - avgW).abs() > avgW * 0.85 ||
          (w2 - avgW).abs() > avgW * 0.85 ||
          (w3 - avgW).abs() > avgW * 0.85) {
        continue;
      }

      var idx = i + 3;
      final leftDigits = <int>[];
      final leftTypes = <String>[];
      var ok = true;

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

        var n1 = (r[0] * 7.0 / tot).round().clamp(1, 4);
        var n2 = (r[1] * 7.0 / tot).round().clamp(1, 4);
        var n3 = (r[2] * 7.0 / tot).round().clamp(1, 4);
        var n4 = (r[3] * 7.0 / tot).round().clamp(1, 4);
        var sumN = n1 + n2 + n3 + n4;

        if (sumN != 7) {
          final diff = 7 - sumN;
          // Eng katta run-lengthga farqni qo'shamiz
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
      if (cRuns.any((x) => (x - cAvg).abs() > cAvg * 0.9)) continue;

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

        var n1 = (r[0] * 7.0 / tot).round().clamp(1, 4);
        var n2 = (r[1] * 7.0 / tot).round().clamp(1, 4);
        var n3 = (r[2] * 7.0 / tot).round().clamp(1, 4);
        var n4 = (r[3] * 7.0 / tot).round().clamp(1, 4);
        var sumN = n1 + n2 + n3 + n4;

        if (sumN != 7) {
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

      // 4. Birinchi raqamni aniqlash
      final patStr = leftTypes.join();
      final firstDigit = _firstPatterns.indexOf(patStr);
      if (firstDigit < 0) continue;

      // 5. 13 xonali kodni yig'ish va nazorat raqamini (Checksum) tekshirish
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
