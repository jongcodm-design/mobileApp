import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:class_schedule/database/database_helper.dart';
import 'package:class_schedule/models/class_item.dart';
import 'package:class_schedule/screens/home_screen.dart';
import 'package:class_schedule/theme/app_theme.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': false});
  });

  testWidgets(
    'HomeScreen hero shows "All classes done" when today classes have passed',
    (tester) async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final todayWeekday = now.weekday;
      final tomorrowWeekday = (todayWeekday % 7) + 1;
      final nowMinutes = now.hour * 60 + now.minute;
      final pastEnd = nowMinutes > 1 ? nowMinutes - 1 : 1;
      final pastStart = (pastEnd - 30).clamp(0, pastEnd - 1);

      await tester.runAsync(() async {
        await db.replaceAll([]);
        await db.insert(
          ClassItem(
            subject: 'Morning Physics',
            room: 'Room 101',
            professor: 'Dr. Santos',
            day: todayWeekday,
            startMinutes: pastStart,
            endMinutes: pastEnd,
          ),
        );
        await db.insert(
          ClassItem(
            subject: 'Tomorrow Math',
            room: 'Room 202',
            professor: 'Prof. Lee',
            day: tomorrowWeekday,
            startMinutes: 480,
            endMinutes: 540,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const HomeScreen(),
        ),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text('All classes done'), findsOneWidget);
      expect(find.text('Good job today — rest up and recharge.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Tomorrow Math'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeScreen hero shows "No classes today" when today has 0 classes scheduled',
    (tester) async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final tomorrowWeekday = (now.weekday % 7) + 1;

      await tester.runAsync(() async {
        await db.replaceAll([]);
        await db.insert(
          ClassItem(
            subject: 'Next Day Chemistry',
            room: 'Lab 3',
            professor: 'Prof. Gomez',
            day: tomorrowWeekday,
            startMinutes: 480,
            endMinutes: 540,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const HomeScreen(),
        ),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text('No classes today'), findsOneWidget);
      expect(find.text('Enjoy your free time and recharge.'), findsOneWidget);
      expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Next Day Chemistry'), findsOneWidget);
    },
  );
}
