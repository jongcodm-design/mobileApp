import 'package:flutter_test/flutter_test.dart';
import 'package:class_schedule/features/schedule_import/utils/schedule_text_parser.dart';
import 'package:class_schedule/features/schedule_import/utils/timetable_parser.dart';

void main() {
  group('ScheduleTextDetails', () {
    test('extracts a standalone room code and uppercase instructor', () {
      final details = ScheduleTextDetails.parse('NSTP 1\nR4\nJ.SARMIENTO');

      expect(details.subject, 'NSTP 1');
      expect(details.room, 'R4');
      expect(details.professor, 'J.SARMIENTO');
    });

    test('does not mistake short uppercase course codes for instructors', () {
      for (final code in ['RPH', 'IOT', 'NSTP']) {
        final details = ScheduleTextDetails.parse(code);

        expect(details.subject, code);
        expect(details.professor, 'Not specified');
      }
    });

    test(
      'keeps timetable course codes with separate room and instructor lines',
      () {
        final rph = ScheduleTextDetails.parseLines([
          'RPH',
          'Room5',
          'R. Dimatulac',
        ]);
        final iot = ScheduleTextDetails.parseLines([
          'IOT',
          'B. Mallari',
          'MacLab',
        ]);

        expect(rph.subject, 'RPH');
        expect(rph.room, 'Room5');
        expect(rph.professor, 'R. Dimatulac');
        expect(iot.subject, 'IOT');
        expect(iot.room, 'MacLab');
        expect(iot.professor, 'B. Mallari');
      },
    );

    test('removes a repeated professor name from the course title', () {
      final details = ScheduleTextDetails.parseLines([
        'DS and Algo-Lec M.Panlaqui.',
        'Room2',
        'M.Panlaqui',
      ]);

      expect(details.subject, 'DS and Algo-Lec');
      expect(details.room, 'Room2');
      expect(details.professor, 'M.Panlaqui');
    });

    test('removes room and instructor appended to a course title', () {
      final details = ScheduleTextDetails.parse(
        'Social and Professional Issues in iT R4 J.SARMIENTO',
      );

      expect(details.subject, 'Social and Professional Issues in IT');
      expect(details.room, 'R4');
      expect(details.professor, 'J.SARMIENTO');
    });

    test('combines subject, room, and instructor from separate OCR blocks', () {
      final details = ScheduleTextDetails.parseLines([
        'Advanced English Language',
        'R4',
        'J. Tanguan',
      ]);

      expect(details.subject, 'Advanced English Language');
      expect(details.room, 'R4');
      expect(details.professor, 'J. Tanguan');
    });

    test('combines a split lab label and room code', () {
      final details = ScheduleTextDetails.parseLines([
        'Computer Programming 2',
        'Lab',
        'L3',
        'G. Esguerra',
      ]);

      expect(details.subject, 'Computer Programming 2');
      expect(details.room, 'Lab L3');
      expect(details.professor, 'G. Esguerra');
    });

    test('finds a room code fused to the end of a recognized subject', () {
      final details = ScheduleTextDetails.parse('Advanced English LanguageR4');

      expect(details.subject, 'Advanced English Language');
      expect(details.room, 'R4');
    });

    test('collapses repeated course names with OCR spelling variations', () {
      final details = ScheduleTextDetails.parseLines([
        'Computer Programming',
        'Computer Progrsming',
        'Computer Programming',
        'R4',
      ]);

      expect(details.subject, 'Computer Programming');
      expect(details.room, 'R4');
    });

    test('collapses three exact copies of a course name', () {
      final details = ScheduleTextDetails.parse(
        'Discrete Mathematics Discrete Mathematics Discrete Mathematics',
      );

      expect(details.subject, 'Discrete Mathematics');
    });

    test('collapses repeated OCR variants of a longer course name', () {
      final details = ScheduleTextDetails.parse(
        'Social and Professional Issues in IT '
        'Social and Professional (Issues in IT '
        'Social and Professional Issues In I]',
      );

      expect(details.subject, 'Social and Professional Issues in IT');
    });

    test('extracts compound lab room codes and title-case instructors', () {
      final details = ScheduleTextDetails.parse(
        'Discrete Mathematics Lab L3 V. Tengco',
      );

      expect(details.subject, 'Discrete Mathematics');
      expect(details.room, 'Lab L3');
      expect(details.professor, 'V. Tengco');
    });

    test('preserves full laboratory and labeled room formats', () {
      expect(
        ScheduleTextDetails.parse('Programming Laboratory 2').room,
        'Laboratory 2',
      );
      expect(ScheduleTextDetails.parse('Biology Room: 101').room, 'Room: 101');
    });

    test('normalizes common OCR casing in course titles', () {
      final details = ScheduleTextDetails.parse(
        'Social and Professional Issues in iT',
      );

      expect(details.subject, 'Social and Professional Issues in IT');
    });
  });

  test('line parser extracts room codes and instructors with course data', () {
    final rows = TimetableParser.parse(
      'Monday NSTP 1 8:00 AM - 9:30 AM R4 J.SARMIENTO',
    );

    expect(rows, hasLength(1));
    expect(rows.single.subject, 'NSTP 1');
    expect(rows.single.room, 'R4');
  });

  test(
    'line parser keeps uppercase course codes with uppercase instructors',
    () {
      final rows = TimetableParser.parse(
        'Monday RPH 10:30 AM - 12:30 PM Room5 R. DIMATULAC\n'
        'Tuesday IOT 2:00 PM - 3:00 PM MacLab B. MALLARI',
      );

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.subject), ['RPH', 'IOT']);
      expect(rows.map((row) => row.room), ['Room5', 'MacLab']);
    },
  );
}
