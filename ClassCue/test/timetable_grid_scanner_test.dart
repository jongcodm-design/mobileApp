import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
import 'package:class_schedule/features/schedule_import/services/ocr_image_preprocessor.dart';
import 'package:class_schedule/features/schedule_import/services/timetable_grid_scanner.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

class _NoPreprocessing extends OcrImagePreprocessor {
  @override
  Future<PreparedOcrImage?> prepare(
    String path, {
    int quarterTurns = 0,
    bool adaptiveThreshold = false,
    bool invertDarkBackground = false,
  }) async => null;
}

OcrResult _region(String text, int left, int top, int right, int bottom) =>
    OcrResult(
      text: text,
      confidence: .99,
      points: [
        OcrPoint(x: left, y: top),
        OcrPoint(x: right, y: top),
        OcrPoint(x: right, y: bottom),
        OcrPoint(x: left, y: bottom),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps afternoon grid cells to their weekday and PM times', () async {
    final directory = await Directory.systemTemp.createTemp('classcue_grid_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _pathProvider,
          (call) async => directory.path,
        );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, null);
      await directory.delete(recursive: true);
    });

    final file = File(
      '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}timetable_grid_afternoon.png',
    );
    final regions = [
      _region('Monday', 680, 80, 720, 110),
      _region('Tuesday', 1280, 80, 1320, 110),
      _region('1:00 PM', 80, 590, 150, 610),
      _region('2:00 PM', 80, 790, 150, 810),
      _region('3:00 PM', 80, 990, 150, 1010),
      _region('Data Structures', 600, 550, 800, 580),
      _region('Chemistry', 1200, 750, 1400, 780),
    ];
    final scanner = TimetableGridScanner(
      preprocessor: _NoPreprocessing(),
      recognize: (path) async => path == file.path
          ? OcrRunResult(
              results: regions,
              detectionTimeMs: 0,
              recognitionTimeMs: 0,
            )
          : OcrRunResult.empty,
    );

    final rows = await scanner.scan(file.path, onProgress: (_, _) {});

    expect(
      rows
          .map(
            (row) =>
                '${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}',
          )
          .toSet(),
      {'Data Structures|1|780|840', 'Chemistry|2|840|900'},
      reason:
          'Scanned rows: ${rows.map((row) => "${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}").toList()}',
    );
    expect(rows.every((row) => row.ocrConfidence == .99), isTrue);
  });

  test(
    'keeps a multiline class together when a grid rule crosses its text',
    () async {
      final directory = await Directory.systemTemp.createTemp('classcue_grid_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _pathProvider,
            (call) async => directory.path,
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_pathProvider, null);
        await directory.delete(recursive: true);
      });

      final file = File(
        '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}timetable_grid_afternoon.png',
      );
      final regions = [
        _region('Monday', 680, 80, 720, 110),
        _region('Tuesday', 1280, 80, 1320, 110),
        _region('1:00 PM', 80, 590, 150, 610),
        _region('2:00 PM', 80, 790, 150, 810),
        _region('3:00 PM', 80, 990, 150, 1010),
        _region('Social and Professional', 580, 680, 880, 700),
        _region('Issues in IT', 580, 700, 820, 720),
        _region('Room R4', 580, 720, 700, 740),
        _region('J. Sarmiento', 580, 740, 820, 760),
      ];
      final scanner = TimetableGridScanner(
        preprocessor: _NoPreprocessing(),
        recognize: (path) async => path == file.path
            ? OcrRunResult(
                results: regions,
                detectionTimeMs: 0,
                recognitionTimeMs: 0,
              )
            : OcrRunResult.empty,
      );

      final rows = await scanner.scan(file.path, onProgress: (_, _) {});

      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Social and Professional Issues in IT');
      expect(rows.single.day, 1);
      expect(rows.single.startMinutes, 13 * 60);
      expect(rows.single.endMinutes, 15 * 60);
      expect(rows.single.room, 'Room R4');
      expect(rows.single.professor, 'J. Sarmiento');
    },
  );
}
