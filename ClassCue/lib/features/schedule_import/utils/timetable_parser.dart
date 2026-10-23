import 'schedule_text_parser.dart';

/// Conservative OCR parser for line-oriented timetables.
/// Every parsed entry must still be reviewed by the user before saving.
class ParsedTimetableRow {
  final String subject;
  final String room;
  final String professor;
  final int day;
  final int startMinutes;
  final int endMinutes;
  final double? ocrConfidence;

  const ParsedTimetableRow({
    required this.subject,
    required this.room,
    required this.professor,
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    this.ocrConfidence,
  });
}

class TimetableParser {
  static final RegExp _dayPattern = RegExp(
    r'\b(mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?|th|sa|su|m(?!\.)|t(?!\.)|w(?!\.)|r(?!\.)|f(?!\.)|s(?!\.)|u(?!\.))\b',
    caseSensitive: false,
  );

  // Compact day groups used in many college timetables (MWF, MTWThF, TTh, TR).
  // These are recognized separately from full weekday names so a course
  // listed once with a repeated weekly pattern expands into one row per day.
  static final RegExp _compactDayPattern = RegExp(
    r'\b(MTWTHF|MTWRF|MTWR|MTW|MWF|MW|TTH|TR)\b',
    caseSensitive: false,
  );
  // The second time may omit AM/PM, as in "8:00 AM - 9:30".
  static final RegExp _timePattern = RegExp(
    r'(\d{1,2}(?:[:.]\d{2})?\s*(?:(?:a\.?m\.?|p\.?m\.?))?)\s*(?:-|–|—|to)\s*(\d{1,2}(?:[:.]\d{2})?\s*(?:(?:a\.?m\.?|p\.?m\.?))?)',
    caseSensitive: false,
  );

  /// Flags names that commonly result from OCR merging nearby cells or text.
  static bool looksLikeOcrTextIssue(String subject) {
    final compact = subject.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compact.length > 36) return true;
    for (var length = 5; length <= compact.length ~/ 2; length++) {
      for (var start = 0; start + length * 2 <= compact.length; start++) {
        final phrase = compact.substring(start, start + length);
        if (phrase == compact.substring(start + length, start + length * 2)) {
          return true;
        }
      }
    }
    return false;
  }

  static List<ParsedTimetableRow> parse(String raw) {
    final rows = <ParsedTimetableRow>[];
    final seen = <String>{};
    var activeDay = 0;
    final lines = raw.replaceAll('\r', '\n').split('\n');

    for (final source in lines) {
      final line = source.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isEmpty) continue;

      // OCR often reads a column heading (e.g. "MONDAY") on its own line,
      // followed by subject/time/room rows that do not repeat the weekday.
      final dayMatches = _dayPattern.allMatches(line).toList();
      final compactDayMatches = _compactDayPattern.allMatches(line).toList();
      final timeMatch = _timePattern.firstMatch(line);
      if (timeMatch == null &&
          dayMatches.length == 1 &&
          compactDayMatches.isEmpty) {
        final before = line.substring(0, dayMatches.single.start).trim();
        final after = line.substring(dayMatches.single.end).trim();
        if (before.isEmpty && after.isEmpty) {
          activeDay = _dayNumber(dayMatches.single.group(1)!) ?? activeDay;
          continue;
        }
      }

      if (timeMatch == null) continue;
      final explicitDays = dayMatches
          .map((m) => _dayNumber(m.group(1)!))
          .whereType<int>()
          .toSet();
      for (final match in compactDayMatches) {
        explicitDays.addAll(_compactDays(match.group(1)!));
      }
      final days = explicitDays.isNotEmpty
          ? explicitDays.toList()
          : (activeDay == 0 ? <int>[] : <int>[activeDay]);
      if (days.isEmpty) continue;

      final start = _parseTime(timeMatch.group(1)!);
      final end = _parseEndTime(timeMatch.group(2)!, timeMatch.group(1)!);
      if (start == null || end == null || end <= start) continue;

      var subject = line
          .replaceAll(_dayPattern, ' ')
          .replaceAll(_compactDayPattern, ' ')
          .replaceFirst(_timePattern, ' ')
          .replaceAll(RegExp(r'[|•,:;]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      subject = subject.replaceAll(RegExp(r'^(?:/\s*)+|(?:\s*/)+$'), '').trim();
      subject = subject
          .replaceAll(RegExp(r'^(?:[-–—]\s*)+|(?:\s*[-–—])+$'), '')
          .trim();
      final details = ScheduleTextDetails.parse(subject);
      subject = details.subject;
      // Ignore common table headings accidentally recognized as subjects.
      if (subject.length < 2 ||
          RegExp(
            r'^(subject|course|class|time|schedule|room)$',
            caseSensitive: false,
          ).hasMatch(subject)) {
        continue;
      }

      for (final day in days) {
        final key =
            '$day|$start|$end|${subject.toLowerCase()}|${details.room.toLowerCase()}';
        if (seen.add(key)) {
          rows.add(
            ParsedTimetableRow(
              subject: subject,
              room: details.room,
              professor: details.professor,
              day: day,
              startMinutes: start,
              endMinutes: end,
            ),
          );
        }
      }
    }
    return rows;
  }

  static int? _dayNumber(String value) {
    const days = {
      'mon': 1,
      'tue': 2,
      'wed': 3,
      'thu': 4,
      'fri': 5,
      'sat': 6,
      'sun': 7,
      'm': 1,
      't': 2,
      'w': 3,
      'th': 4,
      'r': 4,
      'f': 5,
      'sa': 6,
      's': 6,
      'su': 7,
      'u': 7,
    };
    final normalized = value.toLowerCase();
    return days[normalized] ??
        (normalized.length >= 3 ? days[normalized.substring(0, 3)] : null);
  }

  static List<int> _compactDays(String value) {
    switch (value.toUpperCase()) {
      case 'MWF':
        return [1, 3, 5];
      case 'MW':
        return [1, 3];
      case 'MTWTHF':
      case 'MTWRF':
        return [1, 2, 3, 4, 5];
      case 'MTWR':
        return [1, 2, 3, 4];
      case 'MTW':
        return [1, 2, 3];
      case 'TTH':
      case 'TR':
        return [2, 4];
      default:
        return const [];
    }
  }

  static int? _parseTime(String input) {
    final value = input.trim().toUpperCase().replaceAllMapped(
      RegExp(r'\b([AP])\.?\s*M\.?'),
      (match) => '${match.group(1)}M',
    );
    final match = RegExp(
      r'^(\d{1,2})(?:[:.](\d{2}))?\s*(AM|PM)?$',
    ).firstMatch(value);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2) ?? '0');
    final meridiem = match.group(3);
    if (minute > 59) return null;
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (meridiem == 'PM' ? 12 : 0);
    } else if (hour < 0 || hour > 23) {
      return null;
    }
    return hour * 60 + minute;
  }

  static int? _parseEndTime(String endText, String startText) {
    final explicit = _parseTime(endText);
    if (explicit != null &&
        RegExp(
          r'(?:a\.?m\.?|p\.?m\.?)',
          caseSensitive: false,
        ).hasMatch(endText)) {
      return explicit;
    }
    final start = _parseTime(startText);
    if (start == null) return null;
    final endMatch = RegExp(
      r'^(\d{1,2})(?:[:.](\d{2}))?$',
    ).firstMatch(endText.trim());
    if (endMatch == null) return explicit;
    final hour = int.parse(endMatch.group(1)!);
    final minute = int.parse(endMatch.group(2) ?? '0');
    if (minute > 59) return null;

    // If start is in 12-hour format and end omits AM/PM, infer the nearest
    // later plausible time. For 24-hour ranges, retain 24-hour interpretation.
    final startHasMeridiem = RegExp(
      r'(?:a\.?m\.?|p\.?m\.?)',
      caseSensitive: false,
    ).hasMatch(startText);
    if (!startHasMeridiem) {
      if (hour > 23) return null;
      var result = hour * 60 + minute;
      if (result <= start && result + 720 <= 1440) result += 720;
      return result;
    }
    if (hour < 1 || hour > 12) return null;
    final startIsPm = RegExp(
      r'p\.?m\.?',
      caseSensitive: false,
    ).hasMatch(startText);
    var result = (hour % 12 + (startIsPm ? 12 : 0)) * 60 + minute;
    if (result <= start && result + 720 <= 1440) result += 720;
    return result;
  }
}
