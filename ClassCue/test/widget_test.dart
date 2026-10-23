import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:class_schedule/main.dart';
import 'package:class_schedule/widgets/bottom_navigation_item.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
  });

  testWidgets('ClassCue app opens', (WidgetTester tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(const ScheduleApp());

    // The home screen starts by loading classes from the local database.
    // Pump once more so the initial loading state can settle where possible.
    await tester.pump();

    expect(find.text('ClassCue'), findsOneWidget);
    expect(find.bySemanticsLabel('Today'), findsOneWidget);
    expect(find.bySemanticsLabel('Week'), findsOneWidget);
    expect(find.text('Import'), findsNothing);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(find.byType(BottomNavigationItem), findsNWidgets(3));
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(800, 1000);
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(BottomNavigationItem), findsNothing);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(find.byType(BottomNavigationItem), findsNWidgets(3));
    expect(find.byType(NavigationRail), findsNothing);

    await tester.tap(find.bySemanticsLabel('Week'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Weekly schedule'), findsOneWidget);
    expect(find.byTooltip('Switch to weekly grid'), findsNothing);
    expect(find.text('Week at a glance'), findsNothing);
    expect(find.byTooltip('Add class'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Import a timetable'), findsOneWidget);

    await tester.tap(find.text('Import a timetable'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Import weekly schedule'), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Class reminders'), findsOneWidget);
    expect(find.text('Backup and restore'), findsOneWidget);
    expect(find.text('How ClassCue works'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Today'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('ClassCue'), findsOneWidget);
  });
}
