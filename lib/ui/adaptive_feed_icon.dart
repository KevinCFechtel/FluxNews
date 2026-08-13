import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const int _analysisExtent = 32;
const double _minimumTransparentPixelRatio = 0.12;
const double _darkAverageLuminanceThreshold = 0.34;
const double _darkPixelLuminanceThreshold = 0.28;
const double _minimumDarkPixelRatio = 0.65;

class AdaptiveFeedIcon extends StatelessWidget {
  const AdaptiveFeedIcon({
    super.key,
    required this.bytes,
    required this.mimeType,
    required this.size,
    required this.feedIconID,
    required this.automaticContrastEnabled,
    required this.manualAdaptLightMode,
    required this.manualAdaptDarkMode,
  });

  final Uint8List bytes;
  final String mimeType;
  final double size;
  final int? feedIconID;
  final bool automaticContrastEnabled;
  final bool manualAdaptLightMode;
  final bool manualAdaptDarkMode;

  @override
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    final icon = _iconWidget();
    final manualSurface = darkMode ? manualAdaptDarkMode : manualAdaptLightMode;

    if (manualSurface) {
      return _FeedIconContrastSurface(child: icon);
    }
    if (!automaticContrastEnabled ||
        !darkMode ||
        manualAdaptLightMode ||
        manualAdaptDarkMode) {
      return icon;
    }

    final cached = FeedIconContrastAnalyzer.cachedResult(
      bytes: bytes,
      mimeType: mimeType,
      feedIconID: feedIconID,
    );
    if (cached != null) {
      return cached ? _FeedIconContrastSurface(child: icon) : icon;
    }

    return FutureBuilder<bool>(
      future: FeedIconContrastAnalyzer.analyze(
        bytes: bytes,
        mimeType: mimeType,
        feedIconID: feedIconID,
      ),
      initialData: false,
      builder: (context, snapshot) =>
          snapshot.data == true ? _FeedIconContrastSurface(child: icon) : icon,
    );
  }

  Widget _iconWidget() {
    if (mimeType == 'image/svg+xml') {
      return SvgPicture.memory(
        bytes,
        width: size,
        height: size,
      );
    }
    return Image.memory(
      bytes,
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) =>
          SizedBox.square(dimension: size),
    );
  }
}

class _FeedIconContrastSurface extends StatelessWidget {
  const _FeedIconContrastSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('feed-icon-contrast-surface'),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92),
      ),
      child: child,
    );
  }
}

class FeedIconContrastAnalyzer {
  FeedIconContrastAnalyzer._();

  static final Map<String, bool> _results = <String, bool>{};
  static final Map<String, Future<bool>> _pending = <String, Future<bool>>{};

  static bool? cachedResult({
    required Uint8List bytes,
    required String mimeType,
    required int? feedIconID,
  }) {
    return _results[_cacheKey(bytes, mimeType, feedIconID)];
  }

  static Future<bool> analyze({
    required Uint8List bytes,
    required String mimeType,
    required int? feedIconID,
  }) {
    final key = _cacheKey(bytes, mimeType, feedIconID);
    final cached = _results[key];
    if (cached != null) return Future<bool>.value(cached);

    return _pending.putIfAbsent(key, () async {
      final result = await _analyzeBytes(bytes, mimeType);
      _results[key] = result;
      _pending.remove(key);
      return result;
    });
  }

  static void clearCache() {
    _results.clear();
    _pending.clear();
  }

  static String _cacheKey(
    Uint8List bytes,
    String mimeType,
    int? feedIconID,
  ) {
    var fingerprint = bytes.lengthInBytes;
    if (bytes.isNotEmpty) {
      final sampleStep =
          (bytes.lengthInBytes ~/ 16).clamp(1, bytes.lengthInBytes);
      for (var index = 0; index < bytes.lengthInBytes; index += sampleStep) {
        fingerprint = 0x1fffffff & (fingerprint * 31 + bytes[index]);
      }
    }
    return '$mimeType:$feedIconID:$fingerprint:${bytes.lengthInBytes}';
  }

  static Future<bool> _analyzeBytes(
    Uint8List bytes,
    String mimeType,
  ) async {
    ui.Image? image;
    try {
      image = mimeType == 'image/svg+xml'
          ? await _rasterizeSvg(bytes)
          : await _decodeRaster(bytes);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (byteData == null) return false;
      return _isDarkTransparent(byteData.buffer.asUint8List());
    } catch (_) {
      return false;
    } finally {
      image?.dispose();
    }
  }

  static Future<ui.Image> _decodeRaster(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _analysisExtent,
      targetHeight: _analysisExtent,
      allowUpscaling: true,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  static Future<ui.Image> _rasterizeSvg(Uint8List bytes) async {
    final pictureInfo = await vg.loadPicture(SvgBytesLoader(bytes), null);
    try {
      final sourceSize = pictureInfo.size;
      if (sourceSize.isEmpty) {
        return pictureInfo.picture.toImage(_analysisExtent, _analysisExtent);
      }
      final scale = math.min(
        _analysisExtent / sourceSize.width,
        _analysisExtent / sourceSize.height,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.translate(
        (_analysisExtent - sourceSize.width * scale) / 2,
        (_analysisExtent - sourceSize.height * scale) / 2,
      );
      canvas.scale(scale);
      canvas.drawPicture(pictureInfo.picture);
      final scaledPicture = recorder.endRecording();
      try {
        return scaledPicture.toImage(_analysisExtent, _analysisExtent);
      } finally {
        scaledPicture.dispose();
      }
    } finally {
      pictureInfo.picture.dispose();
    }
  }

  static bool _isDarkTransparent(Uint8List rgba) {
    if (rgba.lengthInBytes < 4) return false;

    final totalPixels = rgba.lengthInBytes ~/ 4;
    var transparentPixels = 0;
    var visibleWeight = 0.0;
    var luminanceWeight = 0.0;
    var darkWeight = 0.0;

    for (var index = 0; index + 3 < rgba.lengthInBytes; index += 4) {
      final alpha = rgba[index + 3] / 255.0;
      if (alpha < 0.08) {
        transparentPixels++;
        continue;
      }
      final luminance = _relativeLuminance(
        rgba[index],
        rgba[index + 1],
        rgba[index + 2],
      );
      visibleWeight += alpha;
      luminanceWeight += luminance * alpha;
      if (luminance < _darkPixelLuminanceThreshold) darkWeight += alpha;
    }

    if (visibleWeight == 0) return false;
    final transparentRatio = transparentPixels / totalPixels;
    final averageLuminance = luminanceWeight / visibleWeight;
    final darkPixelRatio = darkWeight / visibleWeight;
    return transparentRatio >= _minimumTransparentPixelRatio &&
        (averageLuminance < _darkAverageLuminanceThreshold ||
            darkPixelRatio >= _minimumDarkPixelRatio);
  }

  static double _relativeLuminance(int red, int green, int blue) {
    double linearize(int value) {
      final channel = value / 255.0;
      return channel <= 0.04045
          ? channel / 12.92
          : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * linearize(red) +
        0.7152 * linearize(green) +
        0.0722 * linearize(blue);
  }
}
