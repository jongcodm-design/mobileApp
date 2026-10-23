import 'package:class_schedule/models/class_item.dart';
import 'package:class_schedule/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'does not clear reminders when reading the saved schedule fails',
    () async {
      var cancelled = false;

      await expectLater(
        readClassesBeforeClearingReminders(
          readClasses: () async => throw StateError('database unavailable'),
          cancelAll: () async {
            cancelled = true;
          },
        ),
        throwsStateError,
      );

      expect(cancelled, isFalse);
    },
  );

  test('reads the schedule before clearing current reminders', () async {
    final events = <String>[];
    const item = ClassItem(
      subject: 'Mathematics',
      room: '101',
      professor: 'Prof. Cruz',
      day: 1,
      startMinutes: 480,
      endMinutes: 540,
    );

    final result = await readClassesBeforeClearingReminders(
      readClasses: () async {
        events.add('read');
        return [item];
      },
      cancelAll: () async => events.add('cancel'),
    );

    expect(result, [item]);
    expect(events, ['read', 'cancel']);
  });
}
