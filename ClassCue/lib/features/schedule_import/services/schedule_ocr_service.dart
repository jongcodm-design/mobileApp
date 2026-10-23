import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../utils/domain_rescoring.dart';
import '../utils/ocr_image_size.dart';
import '../utils/pdf_timetable_scan_result.dart';
import '../utils/schedule_text_parser.dart';
import '../utils/timetable_format.dart';
import '../utils/timetable_parser.dart';
import 'ocr_image_preprocessor.dart';
import 'timetable_grid_scanner.dart';

/// Coordinates on-device OCR passes for image, PDF, and weekly-grid imports.
class ScheduleOcrService {
  final PaddleOcr _ocr = PaddleOcr();
  final OcrImagePreprocessor _preprocessor = OcrImagePreprocessor();
  late final TimetableGridScanner _gridScanner = TimetableGridScanner(
    recognize: _ocr.recognize,
    preprocessor: _preprocessor,
  );

  Future<void>? _ocrInitialization;
  Future<void>? _pdfTextInitialization;

  Future<void> _initializeOcr() {
    return _ocrInitialization ??= _ocr.init(
      // Small printed course labels and room codes need finer detection.
      config: const PaddleOcrConfig(
        detThresh: 0.25,
        detBoxThresh: 0.35,
        detUnclipRatio: 1.0,
        detLimitSideLen: 2304,
        detLimitType: 'max',
        detMaxSideLimit: 4000,
        recScoreThresh: 0.0,
      ),
      engine: const EngineConfig(numThreads: 4),
    );
  }

  Future<void> _initializePdfText() {
    return _pdfTextInitialization ??= pdfrx.pdfrxFlutterInitialize();
  }

  bool _isCancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Stops ongoing OCR processing after the current step.
  void cancel() {
    _isCancelled = true;
  }

  /// Clears cancellation state before starting a new scan.
  void resetCancel() {
    _isCancelled = false;
  }

  Future<void> dispose() {
    cancel();
    return _ocr.dispose();
  }

  Future<List<ParsedTimetableRow>> scanGridImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => _isCancelled || (isCancelled?.call() ?? false);
    if (cancelled()) return [];
    await _initializeOcr();
    if (cancelled()) return [];
    return _gridScanner.scan(
      path,
      onProgress: onProgress,
      isCancelled: cancelled,
    );
  }

  /// Runs independent OCR candidates and selects the most useful one instead
  /// of concatenating them. Concatenating alternate passes often duplicates
  /// subjects and can make the timetable parser associate the wrong fields.
  Future<String> scanImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => _isCancelled || (isCancelled?.call() ?? false);
    if (cancelled()) return '';
    onProgress(.44, 'Starting on-device text recognition');
    await _initializeOcr();
    if (cancelled()) return '';
    final candidates = <_OcrTextCandidate>[];
    final temporaryFiles = <File>[];

    var candidateProgress = .46;
    Future<void> addCandidate(String imagePath, String label) async {
      if (cancelled()) return;
      onProgress(candidateProgress, '$label text recognition');
      try {
        final result = await _ocr.recognize(imagePath);
        if (cancelled()) return;
        final text = _joinOcrRegions(result.results);
        if (text.trim().isEmpty) return;
        final confidence = result.results.isEmpty
            ? 0.0
            : result.results
                      .map(
                        (region) =>
                            region.confidence.clamp(0.0, 1.0).toDouble(),
                      )
                      .fold<double>(0.0, (sum, value) => sum + value) /
                  result.results.length;
        candidates.add(_OcrTextCandidate(text, confidence, label));
      } catch (error) {
        debugPrint('$label OCR pass failed: $error');
      } finally {
        candidateProgress = (candidateProgress + .09)
            .clamp(.46, .82)
            .toDouble();
        onProgress(candidateProgress, '$label scan complete');
      }
    }

    try {
      await addCandidate(path, 'Original');
      if (cancelled()) return '';
      onProgress(candidateProgress, 'Preparing an enhanced image');
      final enhanced = await _preprocessor.prepare(path);
      if (enhanced != null) temporaryFiles.add(enhanced.file);
      if (cancelled()) return '';
      if (enhanced != null) {
        await addCandidate(enhanced.file.path, 'Contrast enhanced');
      }
      if (cancelled()) return '';

      // Adaptive thresholding can help faint text, but can also erase thin
      // strokes and timetable grid details. Treat it as a candidate, not truth.
      onProgress(candidateProgress, 'Preparing a high-contrast image');
      final adaptive = await _preprocessor.prepare(
        path,
        adaptiveThreshold: true,
      );
      if (adaptive != null) temporaryFiles.add(adaptive.file);
      if (cancelled()) return '';
      if (adaptive != null) {
        await addCandidate(adaptive.file.path, 'Adaptive threshold');
      }
      final inverted = await _preprocessor.prepare(
        path,
        invertDarkBackground: true,
      );
      if (inverted != null) temporaryFiles.add(inverted.file);
      if (cancelled()) return '';
      if (inverted != null) {
        await addCandidate(inverted.file.path, 'Dark-background inversion');
      }
      if (cancelled()) return '';

      // Rotation is expensive and normally unnecessary. Try it only when the
      // initial independent candidates fail to yield a usable parsed row.
      final initialBestRows = candidates.isEmpty
          ? 0
          : candidates
                .map(
                  (candidate) => TimetableParser.parse(candidate.text).length,
                )
                .reduce((a, b) => a > b ? a : b);
      if (initialBestRows == 0) {
        for (final turns in const [1, 3, 2]) {
          if (cancelled()) return '';
          onProgress(candidateProgress, 'Trying a rotated scan');
          final rotated = await _preprocessor.prepare(
            path,
            quarterTurns: turns,
          );
          if (rotated != null) temporaryFiles.add(rotated.file);
          if (cancelled()) return '';
          if (rotated == null) continue;
          await addCandidate(rotated.file.path, 'Rotated $turns');
          if (cancelled()) return '';
        }
      }

      if (cancelled()) return '';
      if (candidates.isEmpty) return '';
      candidates.sort(
        (a, b) => _scoreOcrCandidate(b).compareTo(_scoreOcrCandidate(a)),
      );
      final best = candidates.first;

      // Format routing + domain correction: OCR letter/digit slips inside
      // times and codes are normalized first, then list-style schedules
      // ("CS201 Mon 9:30-11:00 Room B12", one per line) are parsed
      // line-by-line when that yields more valid rows than the merged
      // free-text path.
      final normalizedText = normalizeOcrTokens(best.text);
      final estimate = TimetableFormatClassifier.classify(normalizedText);
      String selectedText = normalizedText;
      int selectedRows = TimetableParser.parse(normalizedText).length;
      if (estimate.format == TimetableFormat.list && estimate.confidence >= .6) {
        final listRows = TimetableListParser.parse(normalizedText);
        if (listRows.length > selectedRows) {
          // Emit only the class lines the list parser understood so the
          // downstream review screen re-parses exactly these rows.
          selectedText = listRows
              .map((row) => row.subject)
              .join('\n');
          selectedRows = listRows.length;
          debugPrint(
            'Selected ${best.label} OCR candidate with list-format routing: '
            '$selectedRows parsed rows (${estimate.evidence}).',
          );
        }
      }

      debugPrint(
        'Selected ${best.label} OCR candidate: '
        '$selectedRows parsed rows, '
        'confidence ${best.meanConfidence.toStringAsFixed(3)}, '
        'format ${estimate.format.name}.',
      );
      onProgress(.84, 'Text recognition complete');
      return selectedText;
    } finally {
      for (final file in temporaryFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (error) {
          debugPrint('Could not remove temporary OCR image: $error');
        }
      }
    }
  }

  /// Accuracy is judged by useful, valid timetable rows first. Model confidence
  /// is only a tie-breaker because a confident OCR result can still be wrong.
  double _scoreOcrCandidate(_OcrTextCandidate candidate) {
    final rows = TimetableParser.parse(candidate.text);
    if (rows.isEmpty) return candidate.meanConfidence * 5;

    final distinctSubjects = rows
        .map(
          (row) =>
              row.subject.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
        )
        .where((subject) => subject.isNotEmpty)
        .toSet()
        .length;
    final uniqueSlots = rows
        .map((row) => '${row.day}:${row.startMinutes}:${row.endMinutes}')
        .toSet()
        .length;
    final repeatedLines = candidate.text
        .split('\n')
        .map(
          (line) => line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
        )
        .where((line) => line.length > 3)
        .toList();
    final duplicatePenalty =
        repeatedLines.length - repeatedLines.toSet().length;
    final validTimePairs = RegExp(
      r'\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm)?\s*(?:-|–|—|to)\s*\d{1,2}(?:[:.]\d{2})?',
      caseSensitive: false,
    ).allMatches(candidate.text).length;

    return (rows.length * 100.0 +
            distinctSubjects * 8.0 +
            uniqueSlots * 4.0 +
            math.min(validTimePairs, 20) * 1.5 +
            candidate.meanConfidence * 12.0 -
            duplicatePenalty * 12.0)
        .toDouble();
  }

  Future<PdfTimetableScanResult> scanPdf(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => _isCancelled || (isCancelled?.call() ?? false);
    if (cancelled()) {
      return const PdfTimetableScanResult(
        pages: [],
        totalPages: 0,
        scannedPages: 0,
      );
    }
    onProgress(.1, 'Opening the PDF');
    final doc = await PdfDocument.openFile(path);
    final temp = await getTemporaryDirectory();
    final totalPages = doc.pagesCount;
    final pageResults = <PdfPageScanResult>[];
    pdfrx.PdfDocument? textDocument;
    try {
      try {
        onProgress(.11, 'Checking for selectable PDF text');
        await _initializePdfText();
        textDocument = await pdfrx.PdfDocument.openFile(path);
      } catch (error) {
        debugPrint('Selectable PDF text is unavailable; using OCR: $error');
        await textDocument?.dispose();
        textDocument = null;
      }
      await _initializeOcr();
      if (cancelled()) {
        return PdfTimetableScanResult(
          pages: const [],
          totalPages: totalPages,
          scannedPages: 0,
        );
      }
      final pageCount = math.min(totalPages, 8);
      for (var i = 1; i <= pageCount; i++) {
        if (cancelled()) break;
        onProgress(
          .1 + .72 * (i - 1) / pageCount,
          pageCount < totalPages
              ? 'Reading PDF page $i of $pageCount (first $pageCount of $totalPages)'
              : 'Reading PDF page $i of $pageCount',
        );
        final page = await doc.getPage(i);
        try {
          if (cancelled()) break;
          final pdfTextFragments = await _readPdfTextFragments(textDocument, i);
          final renderScale = math
              .min(3.0, maxOcrRasterSide / math.max(page.width, page.height))
              .toDouble();
          final rendered = await page.render(
            width: page.width * renderScale,
            height: page.height * renderScale,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) {
            pageResults.add(
              PdfPageScanResult(
                pageNumber: i,
                gridRows: const [],
                fallbackText: '',
                hasWeekdayHeaders: false,
              ),
            );
            onProgress(
              .1 + .72 * i / pageCount,
              'Skipped unreadable PDF page $i of $pageCount',
            );
            continue;
          }
          final imageFile = File(
            p.join(
              temp.path,
              'schedule_import_page_${i}_${DateTime.now().microsecondsSinceEpoch}.png',
            ),
          );
          await imageFile.writeAsBytes(rendered.bytes, flush: true);
          try {
            final scannedPageRows = await _gridScanner.scan(
              imageFile.path,
              isCancelled: cancelled,
              onProgress: (progress, detail) {
                final pageFraction =
                    (progress / .43).clamp(0.0, 1.0).toDouble() * .45;
                onProgress(
                  .1 + .72 * ((i - 1 + pageFraction) / pageCount),
                  'PDF page $i of $pageCount - $detail',
                );
              },
            );
            if (cancelled()) break;
            final pageRows = scannedPageRows.isNotEmpty
                ? _applyPdfTextLayer(scannedPageRows, pdfTextFragments)
                : const <ParsedTimetableRow>[];
            final fallbackText = pageRows.isEmpty
                ? await scanImage(
                    imageFile.path,
                    isCancelled: cancelled,
                    onProgress: (progress, detail) {
                      final pageFraction = ((progress - .44) / .4)
                          .clamp(0.0, 1.0)
                          .toDouble();
                      onProgress(
                        .1 +
                            .72 *
                                ((i - 1 + .45 + .55 * pageFraction) /
                                    pageCount),
                        'PDF page $i of $pageCount · $detail',
                      );
                    },
                  )
                : '';
            if (cancelled()) break;
            final hasWeekdayHeaders =
                RegExp(
                  r'\b(?:MON(?:DAY)?|TUE(?:SDAY)?|WED(?:NESDAY)?|THU(?:RSDAY)?|FRI(?:DAY)?)\b',
                  caseSensitive: false,
                ).allMatches(fallbackText).length >=
                2;
            pageResults.add(
              PdfPageScanResult(
                pageNumber: i,
                gridRows: pageRows,
                fallbackText: fallbackText,
                hasWeekdayHeaders: hasWeekdayHeaders,
              ),
            );
            onProgress(
              .1 + .72 * i / pageCount,
              'Finished PDF page $i of $pageCount',
            );
          } finally {
            if (await imageFile.exists()) await imageFile.delete();
          }
        } finally {
          await page.close();
        }
      }
      return cancelled()
          ? PdfTimetableScanResult(
              pages: const [],
              totalPages: totalPages,
              scannedPages: 0,
            )
          : PdfTimetableScanResult(
              pages: pageResults,
              totalPages: totalPages,
              scannedPages: pageCount,
            );
    } finally {
      await textDocument?.dispose();
      await doc.close();
    }
  }

  Future<List<_PdfTextFragment>> _readPdfTextFragments(
    pdfrx.PdfDocument? document,
    int pageNumber,
  ) async {
    if (document == null ||
        pageNumber < 1 ||
        pageNumber > document.pages.length) {
      return const [];
    }
    try {
      final text = await document.pages[pageNumber - 1].loadStructuredText();
      return [
        for (final fragment in text.fragments)
          if (fragment.text.trim().isNotEmpty && fragment.bounds.isNotEmpty)
            _PdfTextFragment(
              text: fragment.text.trim(),
              left: fragment.bounds.left,
              right: fragment.bounds.right,
              top: fragment.bounds.top,
              bottom: fragment.bounds.bottom,
            ),
      ];
    } catch (error) {
      debugPrint('Could not read PDF text on page $pageNumber: $error');
      return const [];
    }
  }

  List<ParsedTimetableRow> _applyPdfTextLayer(
    List<ParsedTimetableRow> gridRows,
    List<_PdfTextFragment> fragments,
  ) {
    if (gridRows.isEmpty || fragments.isEmpty) return gridRows;
    final lines = _pdfTextLines(fragments);
    final dayCenters = <int, double>{};
    final dayHeader = RegExp(
      r'^(MON(?:DAY)?|TUE(?:SDAY)?|WED(?:NESDAY)?|THU(?:RSDAY)?|FRI(?:DAY)?)$',
      caseSensitive: false,
    );
    for (final line in lines) {
      final heading = line.text.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
      final match = dayHeader.firstMatch(heading);
      if (match == null) continue;
      final day = switch (match.group(1)!.substring(0, 3)) {
        'MON' => 1,
        'TUE' => 2,
        'WED' => 3,
        'THU' => 4,
        'FRI' => 5,
        _ => 0,
      };
      if (day != 0) dayCenters[day] = line.centerX;
    }
    if (dayCenters.length < 2) return gridRows;

    final sortedDays = dayCenters.keys.toList()
      ..sort((a, b) => dayCenters[a]!.compareTo(dayCenters[b]!));
    final firstGap = dayCenters[sortedDays[1]]! - dayCenters[sortedDays.first]!;
    final lastGap =
        dayCenters[sortedDays.last]! -
        dayCenters[sortedDays[sortedDays.length - 2]]!;
    final dayBounds = <int, List<double>>{};
    for (var i = 0; i < sortedDays.length; i++) {
      final day = sortedDays[i];
      final center = dayCenters[day]!;
      final left = i == 0
          ? center - firstGap / 2
          : (dayCenters[sortedDays[i - 1]]! + center) / 2;
      final right = i == sortedDays.length - 1
          ? center + lastGap / 2
          : (center + dayCenters[sortedDays[i + 1]]!) / 2;
      dayBounds[day] = [left, right];
    }

    final timePattern = RegExp(
      r'(\d{1,2}):(\d{2})\s*([AP])\.?M\.?\s*[-–—]\s*(\d{1,2}):(\d{2})\s*([AP])\.?M\.?',
      caseSensitive: false,
    );
    final ticks = <({double y, double minute})>[];
    for (final line in lines) {
      if (line.left >= dayBounds[sortedDays.first]![0]) continue;
      final match = timePattern.firstMatch(line.text);
      if (match == null) continue;
      final start = _pdfClockMinute(
        match.group(1)!,
        match.group(2)!,
        match.group(3)!,
      );
      final end = _pdfClockMinute(
        match.group(4)!,
        match.group(5)!,
        match.group(6)!,
      );
      if (start == null || end == null || end <= start) continue;
      ticks.add((y: line.centerY, minute: (start + end) / 2));
    }
    if (ticks.length < 2) return gridRows;

    final meanY =
        ticks.map((tick) => tick.y).reduce((a, b) => a + b) / ticks.length;
    final meanMinute =
        ticks.map((tick) => tick.minute).reduce((a, b) => a + b) / ticks.length;
    var covariance = 0.0;
    var minuteVariance = 0.0;
    for (final tick in ticks) {
      covariance += (tick.minute - meanMinute) * (tick.y - meanY);
      minuteVariance += math.pow(tick.minute - meanMinute, 2).toDouble();
    }
    if (minuteVariance == 0) return gridRows;
    final yPerMinute = covariance / minuteVariance;
    final yIntercept = meanY - yPerMinute * meanMinute;
    double yAt(double minute) => yIntercept + yPerMinute * minute;
    final halfSlotHeight = yPerMinute.abs() * 15;

    var correctedCount = 0;
    final correctedRows = gridRows.map((row) {
      final bounds = dayBounds[row.day];
      if (bounds == null) return row;
      // pdfrx may expose page coordinates with either a top-left or
      // bottom-left origin. Normalize the interval instead of assuming that
      // later times always have a smaller Y value.
      final firstY = yAt(row.startMinutes + 15);
      final lastY = yAt(row.endMinutes - 15);
      final lowerY = math.min(firstY, lastY) - halfSlotHeight;
      final upperY = math.max(firstY, lastY) + halfSlotHeight;

      final cellFragments = fragments.where((fragment) {
        final centerX = (fragment.left + fragment.right) / 2;
        final centerY = (fragment.top + fragment.bottom) / 2;
        return centerX >= bounds[0] &&
            centerX < bounds[1] &&
            centerY >= lowerY - 2 &&
            centerY <= upperY + 2;
      }).toList();
      final cellLines = _pdfTextLines(
        cellFragments,
      ).map((line) => line.text).where((text) => text.isNotEmpty).toList();
      if (cellLines.isEmpty) return row;

      final details = ScheduleTextDetails.parseLines(cellLines);
      final subject = details.subject.trim();
      if (subject.length < 2 ||
          TimetableParser.looksLikeOcrTextIssue(subject)) {
        return row;
      }
      correctedCount++;
      return ParsedTimetableRow(
        subject: subject,
        room: details.room == 'Room to confirm' ? row.room : details.room,
        professor: details.professor == 'Not specified'
            ? row.professor
            : details.professor,
        day: row.day,
        startMinutes: row.startMinutes,
        endMinutes: row.endMinutes,
        ocrConfidence: null,
      );
    }).toList();

    // A sparse or flattened PDF text layer may expose only a few labels. In
    // that case keep the complete OCR result instead of mixing partial data.
    return correctedCount >= (gridRows.length / 2).ceil()
        ? correctedRows
        : gridRows;
  }

  List<_PdfTextLine> _pdfTextLines(List<_PdfTextFragment> fragments) {
    final ordered = fragments.toList()
      ..sort((a, b) {
        final vertical = b.centerY.compareTo(a.centerY);
        return vertical == 0 ? a.left.compareTo(b.left) : vertical;
      });
    final lines = <List<_PdfTextFragment>>[];
    for (final fragment in ordered) {
      final lineIndex = lines.indexWhere((line) {
        final center =
            line.map((item) => item.centerY).reduce((a, b) => a + b) /
            line.length;
        final height = line
            .map((item) => item.height)
            .reduce((a, b) => a < b ? a : b);
        return (fragment.centerY - center).abs() <=
            math.max(1.5, math.min(height, fragment.height) * .45);
      });
      if (lineIndex < 0) {
        lines.add([fragment]);
      } else {
        lines[lineIndex].add(fragment);
      }
    }

    return lines.map((line) {
      line.sort((a, b) => a.left.compareTo(b.left));
      return _PdfTextLine(
        text: line.map((fragment) => fragment.text).join(' ').trim(),
        left: line.map((fragment) => fragment.left).reduce(math.min),
        right: line.map((fragment) => fragment.right).reduce(math.max),
        centerY:
            line.map((fragment) => fragment.centerY).reduce((a, b) => a + b) /
            line.length,
      );
    }).toList();
  }

  int? _pdfClockMinute(String hourText, String minuteText, String meridiem) {
    final hour = int.tryParse(hourText);
    final minute = int.tryParse(minuteText);
    if (hour == null ||
        minute == null ||
        hour < 1 ||
        hour > 12 ||
        minute > 59) {
      return null;
    }
    final normalizedHour = hour % 12 + (meridiem.toUpperCase() == 'P' ? 12 : 0);
    return normalizedHour * 60 + minute;
  }

  String _joinOcrRegions(List<OcrResult> regions) {
    final sorted = regions.toList()
      ..sort((a, b) {
        final vertical = a.boundingBox.center.dy.compareTo(
          b.boundingBox.center.dy,
        );
        return vertical == 0
            ? a.boundingBox.left.compareTo(b.boundingBox.left)
            : vertical;
      });
    final lines = <String>[];
    var bandCenter = 0.0;
    var bandHeight = 0.0;
    var band = <OcrResult>[];
    void flushBand() {
      if (band.isEmpty) return;
      band.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      lines.add(band.map((region) => region.text.trim()).join(' | '));
      band = <OcrResult>[];
      bandCenter = 0;
      bandHeight = 0;
    }

    for (final region in sorted) {
      final center = region.boundingBox.center.dy;
      if (band.isNotEmpty &&
          center - bandCenter >
              math.max(
                5.0,
                math.min(region.boundingBox.height, bandHeight) * .6,
              )) {
        flushBand();
      }
      if (band.isEmpty) {
        bandCenter = center;
        bandHeight = region.boundingBox.height;
      } else {
        bandCenter = (bandCenter * band.length + center) / (band.length + 1);
        bandHeight =
            (bandHeight * band.length + region.boundingBox.height) /
            (band.length + 1);
      }
      band.add(region);
    }
    flushBand();
    return lines.join('\n');
  }
}

class _OcrTextCandidate {
  const _OcrTextCandidate(this.text, this.meanConfidence, this.label);

  final String text;
  final double meanConfidence;
  final String label;
}

class _PdfTextFragment {
  const _PdfTextFragment({
    required this.text,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;

  double get centerY => (top + bottom) / 2;
  double get height => (top - bottom).abs();
}

class _PdfTextLine {
  const _PdfTextLine({
    required this.text,
    required this.left,
    required this.right,
    required this.centerY,
  });

  final String text;
  final double left;
  final double right;
  final double centerY;

  double get centerX => (left + right) / 2;
}
