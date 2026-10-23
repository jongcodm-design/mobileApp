import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/adaptive_ocr_threshold.dart';

class _OcrPixelTransformRequest {
  const _OcrPixelTransformRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.invertDarkBackground,
    required this.adaptiveThreshold,
  });

  final TransferableTypedData rgba;
  final int width;
  final int height;
  final bool invertDarkBackground;
  final bool adaptiveThreshold;
}

class _OcrPixelTransformResult {
  const _OcrPixelTransformResult(this.pixels);

  final TransferableTypedData? pixels;
}

_OcrPixelTransformResult _transformOcrPixels(
  _OcrPixelTransformRequest request,
) {
  final rgba = request.rgba.materialize().asUint8List();
  final total = request.width * request.height;
  final histogram = List<int>.filled(256, 0);
  final gray = Uint8List(total);
  for (var pixel = 0; pixel < total; pixel++) {
    final offset = pixel * 4;
    final luminance =
        (rgba[offset] * 299 +
            rgba[offset + 1] * 587 +
            rgba[offset + 2] * 114) ~/
        1000;
    gray[pixel] = luminance;
    histogram[luminance]++;
  }

  if (request.invertDarkBackground) {
    var cumulative = 0;
    var median = 0;
    for (var value = 0; value < 256; value++) {
      cumulative += histogram[value];
      if (cumulative >= total / 2) {
        median = value;
        break;
      }
    }
    if (median >= 128) return const _OcrPixelTransformResult(null);
  }

  final clip = math.max(1, (total * .01).round());
  var low = 0;
  var high = 255;
  var cumulative = 0;
  for (var value = 0; value < 256; value++) {
    cumulative += histogram[value];
    if (cumulative >= clip) {
      low = value;
      break;
    }
  }
  cumulative = 0;
  for (var value = 255; value >= 0; value--) {
    cumulative += histogram[value];
    if (cumulative >= clip) {
      high = value;
      break;
    }
  }
  if (high <= low) {
    low = 0;
    high = 255;
  }

  final enhancedPixels = Uint8List(total * 4);
  final range = high - low;
  for (var pixel = 0; pixel < total; pixel++) {
    final stretched = ((gray[pixel] - low) / range).clamp(0.0, 1.0);
    final enhancedValue = (math.pow(stretched, .85) * 255)
        .round()
        .clamp(0, 255)
        .toInt();
    final value = request.invertDarkBackground
        ? 255 - enhancedValue
        : enhancedValue;
    final offset = pixel * 4;
    enhancedPixels[offset] = value;
    enhancedPixels[offset + 1] = value;
    enhancedPixels[offset + 2] = value;
    enhancedPixels[offset + 3] = 255;
  }

  final pixels = request.adaptiveThreshold
      ? adaptiveThresholdRgba(enhancedPixels, request.width, request.height)
      : enhancedPixels;
  return _OcrPixelTransformResult(TransferableTypedData.fromList([pixels]));
}

/// Creates temporary, OCR-friendly variants while preserving image geometry.
class OcrImagePreprocessor {
  Future<PreparedOcrImage?> prepare(
    String path, {
    int quarterTurns = 0,
    bool adaptiveThreshold = false,
    bool invertDarkBackground = false,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? normalized;
    ui.Image? output;
    try {
      final bytes = await File(path).readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final originalWidth = descriptor.width;
      final originalHeight = descriptor.height;
      final longestSide = math.max(originalWidth, originalHeight);
      final ratio = longestSide < 1800
          ? math.min(2.0, 1800 / longestSide)
          : math.min(1.0, 2400 / longestSide);
      final targetWidth = math.max(1, (originalWidth * ratio).round());
      final targetHeight = math.max(1, (originalHeight * ratio).round());
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      source = (await codec.getNextFrame()).image;
      descriptor.dispose();
      descriptor = null;
      buffer.dispose();
      buffer = null;

      final byteData = await source.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;
      final transformed = await compute(
        _transformOcrPixels,
        _OcrPixelTransformRequest(
          rgba: TransferableTypedData.fromList([
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
          ]),
          width: source.width,
          height: source.height,
          invertDarkBackground: invertDarkBackground,
          adaptiveThreshold: adaptiveThreshold,
        ),
        debugLabel: 'Prepare OCR pixels',
      );
      final pixels = transformed.pixels?.materialize().asUint8List();
      if (pixels == null) return null;
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        source.width,
        source.height,
        ui.PixelFormat.rgba8888,
        decoded.complete,
      );
      normalized = await decoded.future;

      final turns = quarterTurns % 4;
      final rotated = turns.isOdd;
      final outputWidth = rotated ? normalized.height : normalized.width;
      final outputHeight = rotated ? normalized.width : normalized.height;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (turns == 1) {
        canvas
          ..translate(outputWidth.toDouble(), 0)
          ..rotate(math.pi / 2);
      } else if (turns == 2) {
        canvas
          ..translate(outputWidth.toDouble(), outputHeight.toDouble())
          ..rotate(math.pi);
      } else if (turns == 3) {
        canvas
          ..translate(0, outputHeight.toDouble())
          ..rotate(-math.pi / 2);
      }
      canvas.drawImage(
        normalized,
        ui.Offset.zero,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      output = await recorder.endRecording().toImage(outputWidth, outputHeight);
      final png = await output.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;

      final temp = await getTemporaryDirectory();
      final imageFile = File(
        p.join(
          temp.path,
          'schedule_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await imageFile.writeAsBytes(png.buffer.asUint8List(), flush: true);
      final scale = normalized.width / originalWidth;
      return PreparedOcrImage(file: imageFile, scale: scale);
    } catch (error, stackTrace) {
      debugPrint(
        'Could not prepare an enhanced timetable image: $error\n$stackTrace',
      );
      return null;
    } finally {
      output?.dispose();
      normalized?.dispose();
      source?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

class PreparedOcrImage {
  const PreparedOcrImage({required this.file, required this.scale});

  final File file;
  final double scale;
}
