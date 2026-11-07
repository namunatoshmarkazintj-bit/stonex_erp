import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stonex_erp/core/barcode_decoder.dart';

img.Image createEan13Image(String code, {int moduleWidth = 3, bool reverse = false}) {
  const lPatterns = [
    '0001101', '0011001', '0010011', '0111101', '0100011',
    '0110001', '0101111', '0111011', '0110111', '0001011',
  ];
  const gPatterns = [
    '0100111', '0110011', '0011011', '0100001', '0011101',
    '0111001', '0000101', '0010001', '0001001', '0010111',
  ];
  const rPatterns = [
    '1110010', '1100110', '1101100', '1000010', '1011100',
    '1001110', '1010000', '1000100', '1001000', '1110100',
  ];
  const firstPatterns = [
    'LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG',
    'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL',
  ];

  final firstDigit = int.parse(code[0]);
  final pattern = firstPatterns[firstDigit];

  final sb = StringBuffer();
  sb.write('00000000000000000000'); // Quiet zone
  sb.write('101'); // Start guard

  for (var i = 1; i <= 6; i++) {
    final d = int.parse(code[i]);
    if (pattern[i - 1] == 'L') {
      sb.write(lPatterns[d]);
    } else {
      sb.write(gPatterns[d]);
    }
  }

  sb.write('01010'); // Center guard

  for (var i = 7; i <= 12; i++) {
    final d = int.parse(code[i]);
    sb.write(rPatterns[d]);
  }

  sb.write('101'); // End guard
  sb.write('00000000000000000000'); // Quiet zone

  var bitString = sb.toString();
  if (reverse) {
    bitString = bitString.split('').reversed.join();
  }

  final imgWidth = bitString.length * moduleWidth;
  final imgHeight = 80;
  final image = img.Image(width: imgWidth, height: imgHeight);
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));

  for (var i = 0; i < bitString.length; i++) {
    if (bitString[i] == '1') {
      for (var mx = 0; mx < moduleWidth; mx++) {
        final px = i * moduleWidth + mx;
        for (var py = 10; py < imgHeight - 10; py++) {
          image.setPixel(px, py, img.ColorRgba8(0, 0, 0, 255));
        }
      }
    }
  }
  return image;
}

void main() {
  test('EAN-13 BarcodeDecoder decodes 4760173910440 accurately', () {
    final image = createEan13Image('4760173910440', moduleWidth: 3);
    final decoded = BarcodeDecoder.decode1DBarcode(image);
    expect(decoded, equals('4760173910440'));
  });

  test('EAN-13 BarcodeDecoder decodes reversed (upside-down) 4760173910440', () {
    final image = createEan13Image('4760173910440', moduleWidth: 3, reverse: true);
    final decoded = BarcodeDecoder.decode1DBarcode(image);
    expect(decoded, equals('4760173910440'));
  });

  test('BarcodeDecoder.decode parses JPEG encoded bytes', () {
    final image = createEan13Image('4760173910440', moduleWidth: 2);
    final jpgBytes = img.encodeJpg(image);
    final decoded = BarcodeDecoder.decode(jpgBytes);
    expect(decoded, equals('4760173910440'));
  });
}
