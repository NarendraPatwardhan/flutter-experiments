// Kitty graphics protocol embedder glue: PNG sys hook + placement snapshot.

import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../agent_os/bindings.dart' show freePtr, mallocBytes;
import 'bindings.dart';
import 'png.dart';

/// One placed Kitty image layer with owned Dart pixel data (RGBA).
class VtImageLayer {
  const VtImageLayer({
    required this.imageId,
    required this.placementId,
    required this.cellX,
    required this.cellY,
    required this.cols,
    required this.rows,
    required this.xOffset,
    required this.yOffset,
    required this.widthPx,
    required this.heightPx,
    required this.rgba,
    required this.z,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.sourceX = 0,
    this.sourceY = 0,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.generation = 0,
    this.viewportVisible = true,
  });

  final int imageId;
  final int placementId;

  /// Viewport-relative column of the placement origin (may be negative).
  final int cellX;

  /// Viewport-relative row of the placement origin (may be negative).
  final int cellY;

  final int cols;
  final int rows;
  final int xOffset;
  final int yOffset;

  /// Rendered destination size in pixels.
  final int widthPx;
  final int heightPx;

  /// Full-image tightly packed 8-bit RGBA (`imageWidth * imageHeight * 4`).
  /// When [imageWidth]/[imageHeight] are 0, dimensions are taken from
  /// [widthPx]/[heightPx].
  final Uint8List rgba;
  final int z;

  /// Native stored image dimensions (for pixel buffer decode).
  final int imageWidth;
  final int imageHeight;

  final int sourceX;
  final int sourceY;
  final int sourceWidth;
  final int sourceHeight;
  final int generation;
  final bool viewportVisible;

  int get bufferWidth => imageWidth > 0 ? imageWidth : widthPx;
  int get bufferHeight => imageHeight > 0 ? imageHeight : heightPx;

  /// Destination rect in surface pixels given grid origin + cell size.
  Rect destRect(double originX, double originY, double cellW, double cellH) {
    final w = widthPx > 0 ? widthPx.toDouble() : cols * cellW;
    final h = heightPx > 0 ? heightPx.toDouble() : rows * cellH;
    return Rect.fromLTWH(
      originX + cellX * cellW + xOffset,
      originY + cellY * cellH + yOffset,
      w,
      h,
    );
  }

  Rect get sourceRect {
    final bw = bufferWidth;
    final bh = bufferHeight;
    return Rect.fromLTWH(
      sourceX.toDouble(),
      sourceY.toDouble(),
      sourceWidth > 0 ? sourceWidth.toDouble() : bw.toDouble(),
      sourceHeight > 0 ? sourceHeight.toDouble() : bh.toDouble(),
    );
  }
}

/// Pre-decoded paint entry for [CustomPainter] (sync path).
class VtPaintImage {
  const VtPaintImage({
    required this.image,
    required this.dest,
    required this.z,
    this.src,
  });

  final Object image; // ui.Image — loose type avoids paint import cycles
  final Rect dest;
  final Rect? src;
  final int z;
}

const int kKittyImageStorageLimitDefault = 64 * 1024 * 1024; // 64 MiB

bool _pngDecoderInstalled = false;
NativeCallable<DecodePngNative>? _decodePngCallable;

/// Install a process-global PNG decoder via [ghostty_sys_set] once.
///
/// Safe to call repeatedly. The [NativeCallable] is kept for process lifetime.
void installPngDecoderOnce(GhosttyVtNative native) {
  if (_pngDecoderInstalled) return;

  // Bool-returning native callbacks require exceptionalReturn on Dart 3.
  _decodePngCallable = NativeCallable<DecodePngNative>.isolateLocal(
    (userdata, allocator, data, dataLen, out) {
      return _decodePngTrampoline(native, allocator, data, dataLen, out);
    },
    exceptionalReturn: false,
  );

  // Value is the function pointer itself (see sys.h / c-vt-kitty-graphics).
  final rc = native.sysSet(
    kSysOptDecodePng,
    _decodePngCallable!.nativeFunction.cast(),
  );
  if (rc != kGhosttySuccess) {
    _decodePngCallable?.close();
    _decodePngCallable = null;
    throw StateError('ghostty_sys_set(DECODE_PNG) failed: $rc');
  }
  _pngDecoderInstalled = true;
}

/// Alias kept for older call sites.
void installKittyPngDecoder(GhosttyVtNative native) =>
    installPngDecoderOnce(native);

bool _decodePngTrampoline(
  GhosttyVtNative native,
  Pointer<GhosttyAllocator> allocator,
  Pointer<Uint8> data,
  int dataLen,
  Pointer<GhosttySysImage> out,
) {
  try {
    if (data == nullptr || dataLen <= 0 || out == nullptr) return false;
    final bytes = Uint8List.fromList(data.asTypedList(dataLen));
    final image = decodePng(bytes);
    final pixelLen = image.rgba.length;
    if (pixelLen != image.width * image.height * 4) return false;

    final pixels = native.ghosttyAlloc(allocator, pixelLen);
    if (pixels == nullptr) return false;
    pixels.asTypedList(pixelLen).setAll(0, image.rgba);

    out.ref
      ..width = image.width
      ..height = image.height
      ..data = pixels
      ..dataLen = pixelLen;
    return true;
  } catch (_) {
    return false;
  }
}

/// Enable Kitty graphics storage on [term] with a non-zero byte limit.
void enableKittyGraphics(
  GhosttyVtNative native,
  Pointer<Void> term, {
  int storageLimit = kKittyImageStorageLimitDefault,
}) {
  if (storageLimit <= 0) {
    throw ArgumentError.value(storageLimit, 'storageLimit', 'must be > 0');
  }
  final p = mallocBytes<Uint64>(1, sizeOf<Uint64>());
  try {
    p.value = storageLimit;
    final rc = native.terminalSet(
      term,
      kTerminalOptKittyImageStorageLimit,
      p.cast(),
    );
    if (rc != kGhosttySuccess) {
      throw StateError(
        'ghostty_terminal_set(KITTY_IMAGE_STORAGE_LIMIT) failed: $rc',
      );
    }
  } finally {
    freePtr(p);
  }
}

/// Snapshot all non-virtual, visible Kitty placements into owned [VtImageLayer]s.
///
/// Returns an empty list when graphics are disabled, empty, or unavailable.
/// Pixel buffers are copied out of Ghostty so they remain valid after the call.
List<VtImageLayer> snapshotKittyGraphics(
  GhosttyVtNative n,
  Pointer term,
) {
  return collectImageLayers(n, term);
}

/// Collect visible Kitty graphics placements into owned [VtImageLayer]s.
///
/// Must run while the terminal is not mutated (e.g. right after text snapshot).
List<VtImageLayer> collectImageLayers(
  GhosttyVtNative n,
  Pointer term,
) {
  final graphicsOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
  final iterOut = mallocBytes<Pointer<Void>>(1, sizeOf<Pointer<Void>>());
  final u32a = mallocBytes<Uint32>(1, sizeOf<Uint32>());
  final u32b = mallocBytes<Uint32>(1, sizeOf<Uint32>());
  final i32a = mallocBytes<Int32>(1, sizeOf<Int32>());
  final i32b = mallocBytes<Int32>(1, sizeOf<Int32>());
  final boolSlot = mallocBytes<Uint8>(1, sizeOf<Uint8>());
  final sizeSlot = mallocBytes<Size>(1, sizeOf<Size>());
  final u64 = mallocBytes<Uint64>(1, sizeOf<Uint64>());
  final dataPtrOut =
      mallocBytes<Pointer<Uint8>>(1, sizeOf<Pointer<Uint8>>());
  final renderInfo = mallocBytes<GhosttyKittyPlacementRenderInfoNative>(
    1,
    sizeOf<GhosttyKittyPlacementRenderInfoNative>(),
  );

  final layers = <VtImageLayer>[];
  Pointer<Void> iter = nullptr;
  final imageCache = <int, _CachedImage>{};

  try {
    graphicsOut.value = nullptr;
    final grc = n.terminalGet(
      term.cast(),
      kTerminalDataKittyGraphics,
      graphicsOut.cast(),
    );
    if (grc != kGhosttySuccess || graphicsOut.value == nullptr) {
      return layers;
    }
    final graphics = graphicsOut.value;

    var rc = n.kittyPlacementIteratorNew(nullptr, iterOut);
    if (rc != kGhosttySuccess || iterOut.value == nullptr) {
      return layers;
    }
    iter = iterOut.value;

    // Populate iterator from storage (same handle slot as new).
    iterOut.value = iter;
    rc = n.kittyGraphicsGet(
      graphics,
      kKittyGraphicsDataPlacementIterator,
      iterOut.cast(),
    );
    if (rc != kGhosttySuccess) {
      return layers;
    }
    iter = iterOut.value;

    while (n.kittyPlacementNext(iter)) {
      boolSlot.value = 0;
      n.kittyPlacementGet(
        iter,
        kKittyPlacementDataIsVirtual,
        boolSlot.cast(),
      );
      if (boolSlot.value != 0) continue;

      u32a.value = 0;
      n.kittyPlacementGet(iter, kKittyPlacementDataImageId, u32a.cast());
      final imageId = u32a.value;

      u32b.value = 0;
      n.kittyPlacementGet(
        iter,
        kKittyPlacementDataPlacementId,
        u32b.cast(),
      );
      final placementId = u32b.value;

      i32a.value = 0;
      n.kittyPlacementGet(iter, kKittyPlacementDataZ, i32a.cast());
      final z = i32a.value;

      u32a.value = 0;
      n.kittyPlacementGet(iter, kKittyPlacementDataXOffset, u32a.cast());
      final xOffset = u32a.value;

      u32a.value = 0;
      n.kittyPlacementGet(iter, kKittyPlacementDataYOffset, u32a.cast());
      final yOffset = u32a.value;

      final image = n.kittyGraphicsImage(graphics, imageId);
      if (image == nullptr) continue;

      var cellX = 0;
      var cellY = 0;
      var cols = 0;
      var rows = 0;
      var widthPx = 0;
      var heightPx = 0;
      var sourceX = 0;
      var sourceY = 0;
      var sourceWidth = 0;
      var sourceHeight = 0;
      var visible = true;

      renderInfo.ref.size = sizeOf<GhosttyKittyPlacementRenderInfoNative>();
      rc = n.kittyPlacementRenderInfo(
        iter,
        image,
        term.cast(),
        renderInfo,
      );
      if (rc == kGhosttySuccess) {
        final info = renderInfo.ref;
        widthPx = info.pixelWidth;
        heightPx = info.pixelHeight;
        cols = info.gridCols;
        rows = info.gridRows;
        cellX = info.viewportCol;
        cellY = info.viewportRow;
        visible = info.viewportVisible;
        sourceX = info.sourceX;
        sourceY = info.sourceY;
        sourceWidth = info.sourceWidth;
        sourceHeight = info.sourceHeight;
      } else {
        if (n.kittyPlacementPixelSize(
              iter,
              image,
              term.cast(),
              u32a,
              u32b,
            ) ==
            kGhosttySuccess) {
          widthPx = u32a.value;
          heightPx = u32b.value;
        }
        if (n.kittyPlacementGridSize(
              iter,
              image,
              term.cast(),
              u32a,
              u32b,
            ) ==
            kGhosttySuccess) {
          cols = u32a.value;
          rows = u32b.value;
        }
        final vrc = n.kittyPlacementViewportPos(
          iter,
          image,
          term.cast(),
          i32a,
          i32b,
        );
        if (vrc == kGhosttySuccess) {
          cellX = i32a.value;
          cellY = i32b.value;
        } else if (vrc == kGhosttyNoValue) {
          visible = false;
        }
        if (cols == 0 &&
            n.kittyPlacementGet(
                  iter,
                  kKittyPlacementDataColumns,
                  u32a.cast(),
                ) ==
                kGhosttySuccess) {
          cols = u32a.value;
        }
        if (rows == 0 &&
            n.kittyPlacementGet(iter, kKittyPlacementDataRows, u32a.cast()) ==
                kGhosttySuccess) {
          rows = u32a.value;
        }
      }

      if (!visible) continue;

      var cached = imageCache[imageId];
      if (cached == null) {
        cached = _loadImageRgba(n, image);
        if (cached == null) continue;
        imageCache[imageId] = cached;
      }

      if (widthPx <= 0) widthPx = cached.width;
      if (heightPx <= 0) heightPx = cached.height;

      layers.add(
        VtImageLayer(
          imageId: imageId,
          placementId: placementId,
          cellX: cellX,
          cellY: cellY,
          cols: cols,
          rows: rows,
          xOffset: xOffset,
          yOffset: yOffset,
          widthPx: widthPx,
          heightPx: heightPx,
          rgba: cached.rgba,
          z: z,
          imageWidth: cached.width,
          imageHeight: cached.height,
          sourceX: sourceX,
          sourceY: sourceY,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          generation: cached.generation,
          viewportVisible: visible,
        ),
      );
    }

    return layers;
  } finally {
    if (iter != nullptr) {
      n.kittyPlacementIteratorFree(iter);
    }
    freePtr(graphicsOut);
    freePtr(iterOut);
    freePtr(u32a);
    freePtr(u32b);
    freePtr(i32a);
    freePtr(i32b);
    freePtr(boolSlot);
    freePtr(sizeSlot);
    freePtr(u64);
    freePtr(dataPtrOut);
    freePtr(renderInfo);
  }
}

class _CachedImage {
  _CachedImage({
    required this.width,
    required this.height,
    required this.rgba,
    required this.generation,
  });
  final int width;
  final int height;
  final Uint8List rgba;
  final int generation;
}

_CachedImage? _loadImageRgba(GhosttyVtNative n, Pointer<Void> image) {
  final u32 = mallocBytes<Uint32>(1, sizeOf<Uint32>());
  final sizeSlot = mallocBytes<Size>(1, sizeOf<Size>());
  final u64 = mallocBytes<Uint64>(1, sizeOf<Uint64>());
  final dataPtrOut =
      mallocBytes<Pointer<Uint8>>(1, sizeOf<Pointer<Uint8>>());
  try {
    var rc = n.kittyGraphicsImageGet(image, kKittyImageDataWidth, u32.cast());
    if (rc != kGhosttySuccess) return null;
    final width = u32.value;

    rc = n.kittyGraphicsImageGet(image, kKittyImageDataHeight, u32.cast());
    if (rc != kGhosttySuccess) return null;
    final height = u32.value;

    rc = n.kittyGraphicsImageGet(image, kKittyImageDataFormat, u32.cast());
    if (rc != kGhosttySuccess) return null;
    final format = u32.value;

    u64.value = 0;
    n.kittyGraphicsImageGet(image, kKittyImageDataGeneration, u64.cast());
    final generation = u64.value;

    rc = n.kittyGraphicsImageGet(
      image,
      kKittyImageDataDataLen,
      sizeSlot.cast(),
    );
    if (rc != kGhosttySuccess) return null;
    final dataLen = sizeSlot.value;

    dataPtrOut.value = nullptr;
    rc = n.kittyGraphicsImageGet(
      image,
      kKittyImageDataDataPtr,
      dataPtrOut.cast(),
    );
    // NO_VALUE → payload pending; skip this image.
    if (rc == kGhosttyNoValue || rc != kGhosttySuccess) return null;
    final dataPtr = dataPtrOut.value;
    if (dataPtr == nullptr || dataLen <= 0 || width <= 0 || height <= 0) {
      return null;
    }

    final rgba = _pixelsToRgba(
      dataPtr.asTypedList(dataLen),
      width,
      height,
      format,
    );
    return _CachedImage(
      width: width,
      height: height,
      rgba: rgba,
      generation: generation,
    );
  } finally {
    freePtr(u32);
    freePtr(sizeSlot);
    freePtr(u64);
    freePtr(dataPtrOut);
  }
}

Uint8List _pixelsToRgba(Uint8List src, int width, int height, int format) {
  final n = width * height;
  switch (format) {
    case kKittyImageFormatRgba:
      return Uint8List.fromList(src.sublist(0, n * 4));
    case kKittyImageFormatRgb:
      final out = Uint8List(n * 4);
      var si = 0;
      var di = 0;
      for (var i = 0; i < n; i++) {
        out[di++] = src[si++];
        out[di++] = src[si++];
        out[di++] = src[si++];
        out[di++] = 255;
      }
      return out;
    case kKittyImageFormatGray:
      final out = Uint8List(n * 4);
      var di = 0;
      for (var i = 0; i < n; i++) {
        final g = src[i];
        out[di++] = g;
        out[di++] = g;
        out[di++] = g;
        out[di++] = 255;
      }
      return out;
    case kKittyImageFormatGrayAlpha:
      final out = Uint8List(n * 4);
      var si = 0;
      var di = 0;
      for (var i = 0; i < n; i++) {
        final g = src[si++];
        final a = src[si++];
        out[di++] = g;
        out[di++] = g;
        out[di++] = g;
        out[di++] = a;
      }
      return out;
    default:
      if (src.length >= n * 4) {
        return Uint8List.fromList(src.sublist(0, n * 4));
      }
      return Uint8List(n * 4);
  }
}
