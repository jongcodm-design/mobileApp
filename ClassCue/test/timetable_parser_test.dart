import 'package:flutter_test/flutter_test.dart';
import 'package:class_schedule/features/schedule_import/utils/timetable_parser.dart';

void main() {
  test('parses a row when both times include AM/PM', () {
    final rows = TimetableParser.parse(
      'Monday Mathematics 8:00 AM - 9:30 AM Room 101',
    );
    expect(rows, hasLength(1));
    expect(rows.single.subject, contains('Mathematics'));
    expect(rows.single.day, 1);
    expect(rows.single.startMinutes, 480);
    expect(rows.single.endMinutes, 570);
    expect(rows.single.room, 'Room 101');
  });

  test('infers PM for an omitted end meridiem when needed', () {
    final rows = TimetableParser.parse('Tue Programming 11:00 AM - 1:00 Lab 2');
    expect(rows, hasLength(1));
    expect(rows.single.startMinutes, 660);
    expect(rows.single.endMinutes, 780);
  });

  test('parses abbreviated weekdays and dash variants', () {
    final rows = TimetableParser.parse(
      'Thu - English - 1:00 PM to 2:30 PM - Room 202',
    );
    expect(rows, hasLength(1));
    expect(rows.single.day, 4);
    expect(rows.single.startMinutes, 780);
    expect(rows.single.endMinutes, 870);
  });

  test('deduplicates identical OCR lines', () {
    final rows = TimetableParser.parse(
      'Friday Biology 8:00 AM - 9:00 AM Room 4\nFriday Biology 8:00 AM - 9:00 AM Room 4',
    );
    expect(rows, hasLength(1));
  });

  test('uses a standalone weekday heading for following timetable rows', () {
    final rows = TimetableParser.parse('''
Monday
Mathematics 8:00 AM - 9:30 AM Room 101
Science 10:00 AM - 11:00 AM Room 202
Tuesday
Programming 1:00 PM - 3:00 PM Lab 2
''');
    expect(rows, hasLength(3));
    expect(rows[0].day, 1);
    expect(rows[1].day, 1);
    expect(rows[2].day, 2);
  });

  test('duplicates a class across multiple explicit weekdays', () {
    final rows = TimetableParser.parse(
      'Mon Wed Fri Mathematics 8:00 AM - 9:00 AM Room 101',
    );
    expect(rows.map((r) => r.day).toList(), [1, 3, 5]);
  });

  test('parses OCR-style separators with compact weekday groups', () {
    final rows = TimetableParser.parse(
      'MWF | 8:00 AM – 9:30 AM | biology | Room 14',
    );
    expect(rows.map((row) => row.day).toList(), [1, 3, 5]);
    expect(rows.first.subject.toLowerCase(), contains('biology'));
    expect(rows.first.room, 'Room 14');
  });

  test('does not accept malformed or backwards time ranges', () {
    expect(
      TimetableParser.parse('Monday Math 9:00 AM - 8:00 AM Room 1'),
      isEmpty,
    );
    expect(
      TimetableParser.parse('Monday Math 25:90 AM - 8:00 AM Room 1'),
      isEmpty,
    );
  });

  test('parses 24-hour time ranges', () {
    final rows = TimetableParser.parse(
      'Monday Mathematics 08:00-09:30 Room 101',
    );
    expect(rows, hasLength(1));
    expect(rows.single.startMinutes, 480);
    expect(rows.single.endMinutes, 570);
  });

  test('parses a one-letter Thursday heading', () {
    final rows = TimetableParser.parse(
      'R Mathematics 8:00 AM - 9:00 AM Room 101',
    );

    expect(rows, hasLength(1));
    expect(rows.single.day, 4);
  });

  test('parses 12-hour range where end omits AM/PM', () {
    final rows = TimetableParser.parse(
      'Monday Mathematics 8:00-9:30 AM Room 101',
    );
    expect(rows, hasLength(1));
    expect(rows.single.startMinutes, 480);
    expect(rows.single.endMinutes, 570);
  });

  test('does not mistake Computer Lab Programming for a room', () {
    final rows = TimetableParser.parse(
      'Monday Computer Lab Programming 8:00 AM - 9:30 AM',
    );
    expect(rows, hasLength(1));
    expect(
      rows.single.subject.toLowerCase(),
      contains('computer lab programming'),
    );
    expect(rows.single.room, 'Room to confirm');
  });
}
