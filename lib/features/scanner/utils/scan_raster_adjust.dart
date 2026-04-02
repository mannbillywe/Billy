import 'dart:typed_data';

import 'package:image/image.dart' as img;

bool isAdjustableRasterMime(String mime) {
  final m = mime.toLowerCase();
  return m == 'image/jpeg' || m == 'image/jpg' || m == 'image/png' || m == 'image/webp';
}

/// Rotates a raster image 90°; re-encodes as JPEG for size consistency.
Uint8List? rotateRaster90(Uint8List bytes, {required bool clockwise}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final rotated = img.copyRotate(decoded, angle: clockwise ? 90 : -90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 88));
}

String jpegFileName(String original) {
  final base = original.replaceAll(RegExp(r'\.[^.]+$'), '');
  final safe = base.isEmpty ? 'scan' : base;
  return '$safe.jpg';
}
