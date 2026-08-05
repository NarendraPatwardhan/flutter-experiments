// Async ui.Image cache for Kitty graphics layers (G4).

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'graphics.dart';

/// Converts [VtImageLayer] pixel buffers into [ui.Image] for sync paint.
class VtImageCache {
  final Map<String, ui.Image> _images = {};
  final Map<String, int> _gens = {};
  List<VtPaintImage> _paintBelow = const [];
  List<VtPaintImage> _paintAbove = const [];
  int _syncGen = 0;

  List<VtPaintImage> get belowText => _paintBelow;
  List<VtPaintImage> get aboveText => _paintAbove;

  /// Decode / refresh images from [layers]. Safe to call every frame.
  Future<void> sync(
    List<VtImageLayer> layers, {
    required double originX,
    required double originY,
    required double cellW,
    required double cellH,
  }) async {
    final token = ++_syncGen;
    final needed = <String>{};
    for (final layer in layers) {
      final key = _key(layer);
      needed.add(key);
      final cachedGen = _gens[key];
      if (cachedGen != layer.generation || !_images.containsKey(key)) {
        final img = await _decodeLayer(layer);
        if (token != _syncGen) {
          img?.dispose();
          return;
        }
        if (img != null) {
          _images[key]?.dispose();
          _images[key] = img;
          _gens[key] = layer.generation;
        }
      }
    }

    // Drop unused.
    final stale = _images.keys.where((k) => !needed.contains(k)).toList();
    for (final k in stale) {
      _images[k]?.dispose();
      _images.remove(k);
      _gens.remove(k);
    }

    final below = <VtPaintImage>[];
    final above = <VtPaintImage>[];
    for (final layer in layers) {
      if (!layer.viewportVisible) continue;
      final img = _images[_key(layer)];
      if (img == null) continue;
      final dest = layer.destRect(originX, originY, cellW, cellH);
      final entry = VtPaintImage(
        image: img,
        dest: dest,
        src: layer.sourceRect,
        z: layer.z,
      );
      if (layer.z < 0) {
        below.add(entry);
      } else {
        above.add(entry);
      }
    }
    _paintBelow = below;
    _paintAbove = above;
  }

  /// Paint-ready list (below then above callers split by z themselves).
  List<({ui.Image image, ui.Rect dest, ui.Rect? src, int z})> paintList(
    double originX,
    double originY,
    double cellW,
    double cellH,
  ) {
    final out = <({ui.Image image, ui.Rect dest, ui.Rect? src, int z})>[];
    for (final p in _paintBelow) {
      final img = p.image;
      if (img is ui.Image) {
        out.add((image: img, dest: p.dest, src: p.src, z: p.z));
      }
    }
    for (final p in _paintAbove) {
      final img = p.image;
      if (img is ui.Image) {
        out.add((image: img, dest: p.dest, src: p.src, z: p.z));
      }
    }
    return out;
  }

  void dispose() {
    _syncGen++;
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    _gens.clear();
    _paintBelow = const [];
    _paintAbove = const [];
  }

  String _key(VtImageLayer layer) =>
      '${layer.imageId}:${layer.placementId}';

  Future<ui.Image?> _decodeLayer(VtImageLayer layer) async {
    final w = layer.bufferWidth;
    final h = layer.bufferHeight;
    if (w <= 0 || h <= 0) return null;
    final need = w * h * 4;
    if (layer.rgba.length < need) return null;
    final rgba = layer.rgba.length == need
        ? layer.rgba
        : Uint8List.fromList(layer.rgba.sublist(0, need));
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

/// Helper: paint a [VtPaintImage] list onto [canvas].
void paintVtImages(
  ui.Canvas canvas,
  List<VtPaintImage> images,
) {
  for (final p in images) {
    final img = p.image;
    if (img is! ui.Image) continue;
    paintImage(
      canvas: canvas,
      rect: p.dest,
      image: img,
      sourceRect: p.src,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }
}
