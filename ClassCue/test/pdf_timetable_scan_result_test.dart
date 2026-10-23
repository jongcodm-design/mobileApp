import 'package:class_schedule/features/schedule_import/utils/pdf_timetable_scan_result.dart';
import 'package:class_schedule/features/schedule_import/utils/timetable_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const spatialRow = ParsedTimetableRow(
    subject: 'Mathematics',
    room: 'Room 101',
    professor: 'Prof. Cruz',
    day: 1,
    startMinutes: 480,
    endMinutes: 540,
  );

  test(
    'keeps fallback rows from a PDF page when another page has grid rows',
    () {
      const result = PdfTimetableScanResult(
        pages: [
          PdfPageScanResult(
            pageNumber: 1,
            gridRows: [spatialRow],
            fallbackText: '',
            hasWeekdayHeaders: false,
          ),
          PdfPageScanResult(
            pageNumber: 2,
            gridRows: [],
            fallbackText: 'Tue Programming 9:00 AM - 10:00 AM Room 202',
            hasWeekdayHeaders: false,
          ),
        ],
        totalPages: 2,
        scannedPages: 2,
      );

      expect(result.gridRows.map((row) => row.subject), [
        'Mathematics',
        'Programming',
      ]);
      expect(result.pagesNeedingReview, isEmpty);
    },
  );

  test('reports skipped and unmapped PDF pages for explicit review', () {
    const result = PdfTimetableScanResult(
      pages: [
        PdfPageScanResult(
          pageNumber: 1,
          gridRows: [spatialRow],
          fallbackText: '',
          hasWeekdayHeaders: false,
        ),
        PdfPageScanResult(
          pageNumber: 2,
          gridRows: [],
          fallbackText: 'Monday\nTuesday\nWednesday',
          hasWeekdayHeaders: true,
        ),
      ],
      totalPages: 10,
      scannedPages: 8,
    );

    expect(result.pagesSkipped, 2);
    expect(result.pagesNeedingReview, [2]);
    expect(result.gridRows, hasLength(1));
  });

  test('flags pages whose fallback text still cannot be parsed', () {
    const result = PdfTimetableScanResult(
      pages: [
        PdfPageScanResult(
          pageNumber: 3,
          gridRows: [],
          fallbackText: '7:00 AM 8:30 AM Advanced English',
          hasWeekdayHeaders: false,
        ),
      ],
      totalPages: 3,
      scannedPages: 3,
    );

    expect(result.gridRows, isEmpty);
    expect(result.pagesNeedingReview, [3]);
  });
}
