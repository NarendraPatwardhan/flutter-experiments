// Minimal synchronous PNG decoder for 8-bit RGB/RGBA (and gray / gray+alpha).
// Uses zlib inflate from dart:io. No palette (color type 3), no interlacing.

import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// Decoded PNG as tightly packed 8-bit RGBA (row-major, top-to-bottom).
class PngImage {
  const PngImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;

  /// Length is always `width * height * 4`.
  final Uint8List rgba;
}

/// Decode a complete PNG buffer into RGBA pixels.
///
/// Supports IHDR + IDAT (+ ancillary ignored) + IEND, bit depth 8, non-interlaced,
/// filter types 0–4, color types 0 (gray), 2 (RGB), 4 (gray+alpha), 6 (RGBA).
///
/// Throws [FormatException] on invalid or unsupported input.
PngImage decodePng(Uint8List data) {
  if (data.length < 8) {
    throw const FormatException('PNG too short for signature');
  }
  // Signature: 89 50 4E 47 0D 0A 1A 0A
  if (data[0] != 0x89 ||
      data[1] != 0x50 ||
      data[2] != 0x4e ||
      data[3] != 0x47 ||
      data[4] != 0x0d ||
      data[5] != 0x0a ||
      data[6] != 0x1a ||
      data[7] != 0x0a) {
    throw const FormatException('Invalid PNG signature');
  }

  var offset = 8;
  int? width;
  int? height;
  var bitDepth = 0;
  var colorType = -1;
  final idat = BytesBuilder(copy: false);
  var sawIhdr = false;
  var sawIend = false;

  while (offset + 12 <= data.length && !sawIend) {
    final length = _readU32(data, offset);
    final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    if (dataEnd + 4 > data.length) {
      throw const FormatException('PNG chunk truncated');
    }
    final chunk = data.sublist(dataStart, dataEnd);
    // Skip CRC at dataEnd..dataEnd+4
    offset = dataEnd + 4;

    switch (type) {
      case 'IHDR':
        if (sawIhdr || length < 13) {
          throw const FormatException('Invalid IHDR');
        }
        sawIhdr = true;
        width = _readU32(chunk, 0);
        height = _readU32(chunk, 4);
        bitDepth = chunk[8];
        colorType = chunk[9];
        final compression = chunk[10];
        final filter = chunk[11];
        final interlace = chunk[12];
        if (bitDepth != 8) {
          throw FormatException('Unsupported PNG bit depth: $bitDepth');
        }
        if (compression != 0 || filter != 0) {
          throw const FormatException('Unsupported PNG compression/filter method');
        }
        if (interlace != 0) {
          throw const FormatException('Interlaced PNG not supported');
        }
        if (width! == 0 || height! == 0 || width > 65536 || height > 65536) {
          throw FormatException('Invalid PNG dimensions ${width}x$height');
        }
        if (colorType != 0 &&
            colorType != 2 &&
            colorType != 4 &&
            colorType != 6) {
          throw FormatException('Unsupported PNG color type: $colorType');
        }
      case 'IDAT':
        if (!sawIhdr) {
          throw const FormatException('IDAT before IHDR');
        }
        idat.add(chunk);
      case 'IEND':
        sawIend = true;
      default:
        // Ancillary / unknown — ignore
        break;
    }
  }

  if (!sawIhdr || width == null || height == null) {
    throw const FormatException('PNG missing IHDR');
  }
  if (!sawIend) {
    throw const FormatException('PNG missing IEND');
  }
  final compressed = idat.toBytes();
  if (compressed.isEmpty) {
    throw const FormatException('PNG has no IDAT');
  }

  final inflated = Uint8List.fromList(ZLibDecoder().convert(compressed));
  final bpp = _bytesPerPixel(colorType);
  final stride = width * bpp;
  final expected = (stride + 1) * height;
  if (inflated.length < expected) {
    throw FormatException(
      'PNG inflated data short: ${inflated.length} < $expected',
    );
  }

  final raw = _unfilter(inflated, width, height, bpp);
  final rgba = _toRgba(raw, width, height, colorType);
  return PngImage(width: width, height: height, rgba: rgba);
}

int _readU32(Uint8List data, int offset) {
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}

int _bytesPerPixel(int colorType) {
  switch (colorType) {
    case 0:
      return 1; // gray
    case 2:
      return 3; // RGB
    case 4:
      return 2; // gray + alpha
    case 6:
      return 4; // RGBA
    default:
      throw FormatException('Unsupported color type $colorType');
  }
}

Uint8List _unfilter(Uint8List inflated, int width, int height, int bpp) {
  final stride = width * bpp;
  final out = Uint8List(stride * height);
  final prev = Uint8List(stride);
  var inOff = 0;
  var outOff = 0;

  for (var y = 0; y < height; y++) {
    final filter = inflated[inOff++];
    final row = inflated.sublist(inOff, inOff + stride);
    inOff += stride;
    final recon = Uint8List(stride);

    switch (filter) {
      case 0: // None
        recon.setAll(0, row);
      case 1: // Sub
        for (var i = 0; i < stride; i++) {
          final left = i >= bpp ? recon[i - bpp] : 0;
          recon[i] = (row[i] + left) & 0xff;
        }
      case 2: // Up
        for (var i = 0; i < stride; i++) {
          recon[i] = (row[i] + prev[i]) & 0xff;
        }
      case 3: // Average
        for (var i = 0; i < stride; i++) {
          final left = i >= bpp ? recon[i - bpp] : 0;
          recon[i] = (row[i] + ((left + prev[i]) >> 1)) & 0xff;
        }
      case 4: // Paeth
        for (var i = 0; i < stride; i++) {
          final left = i >= bpp ? recon[i - bpp] : 0;
          final up = prev[i];
          final upLeft = i >= bpp ? prev[i - bpp] : 0;
          recon[i] = (row[i] + _paeth(left, up, upLeft)) & 0xff;
        }
      default:
        throw FormatException('Unknown PNG filter type: $filter');
    }

    out.setRange(outOff, outOff + stride, recon);
    outOff += stride;
    prev.setAll(0, recon);
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

Uint8List _toRgba(Uint8List raw, int width, int height, int colorType) {
  final n = width * height;
  final out = Uint8List(n * 4);
  var si = 0;
  var di = 0;
  switch (colorType) {
    case 0: // gray
      for (var i = 0; i < n; i++) {
        final g = raw[si++];
        out[di++] = g;
        out[di++] = g;
        out[di++] = g;
        out[di++] = 255;
      }
    case 2: // RGB
      for (var i = 0; i < n; i++) {
        out[di++] = raw[si++];
        out[di++] = raw[si++];
        out[di++] = raw[si++];
        out[di++] = 255;
      }
    case 4: // gray + alpha
      for (var i = 0; i < n; i++) {
        final g = raw[si++];
        final a = raw[si++];
        out[di++] = g;
        out[di++] = g;
        out[di++] = g;
        out[di++] = a;
      }
    case 6: // RGBA
      out.setAll(0, raw.sublist(0, n * 4));
    default:
      throw FormatException('Unsupported color type $colorType');
  }
  return out;
}
