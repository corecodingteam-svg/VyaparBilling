import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'escpos.dart';

/// Turns a picture (PNG, JPEG, …) into the one-bit raster a receipt printer prints: scaled down to at most
/// [maxWidth] dots, dark pixels black, light and transparent ones left as paper. Null when it cannot be read.
MonoImage? toMonoImage(Uint8List bytes, {int maxWidth = 240, int maxHeight = 160}) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  var picture = decoded;
  final scale = [maxWidth / picture.width, maxHeight / picture.height, 1.0].reduce((a, b) => a < b ? a : b);
  if (scale < 1) picture = img.copyResize(picture, width: (picture.width * scale).round().clamp(1, maxWidth), interpolation: img.Interpolation.average);
  final widthBytes = (picture.width + 7) ~/ 8;
  final data = Uint8List(widthBytes * picture.height);
  for (var y = 0; y < picture.height; y++) {
    for (var x = 0; x < picture.width; x++) {
      final p = picture.getPixel(x, y);
      final alpha = p.a / p.maxChannelValue;
      // Luminance of the pixel as it would look on white paper.
      final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / p.maxChannelValue * alpha + (1 - alpha);
      if (lum < 0.5) data[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return MonoImage(widthBytes, picture.height, data);
}
