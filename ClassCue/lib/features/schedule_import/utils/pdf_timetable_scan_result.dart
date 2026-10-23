import 'timetable_parser.dart';

class PdfPageScanResult {
  const PdfPageScanResult({
    required this.pageNumber,
    required this.gridRows,
    required this.fallbackText,
    required this.hasWeekdayHeaders,
  });

  final int pageNumber;
  final List<ParsedTimetableRow> gridRows;
  final String fallbackText;
  final bool hasWeekdayHeaders;
}

class PdfTimetableScanResult {
  const PdfTimetableScanResult({
    required this.pages,
    required this.totalPages,
    required this.scannedPages,
  });

  final List<PdfPageScanResult> pages;
  final int totalPages;
  final int scannedPages;

  int get pagesSkipped => totalPages - scannedPages;

  String get text => pages.map((page) => page.fallbackText).join('\n');

  List<ParsedTimetableRow> get gridRows {
    final rows = <ParsedTimetableRow>[];
    for (final page in pages) {
      rows.addAll(page.gridRows);
      if (page.gridRows.isEmpty && !page.hasWeekdayHeaders) {
        rows.addAll(TimetableParser.parse(page.fallbackText));
      }
    }

    final seen = <String>{};
    return rows.where((row) {
      final subject = row.subject
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return seen.add(
        '${row.day}|${row.startMinutes}|${row.endMinutes}|$subject',
      );
    }).toList();
  }

  List<int> get pagesNeedingReview => [
    for (final page in pages)
      if (page.gridRows.isEmpty &&
          (page.hasWeekdayHeaders ||
              TimetableParser.parse(page.fallbackText).isEmpty))
        page.pageNumber,
  ];
}
