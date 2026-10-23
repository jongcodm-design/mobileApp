import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:class_schedule/screens/onboarding_screen.dart';
import 'package:class_schedule/services/onboarding_store.dart';

void main() {
  group('OnboardingStore', () {
    test('is not completed on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await OnboardingStore.isCompleted(), isFalse);
    });

    test('remembers completion', () async {
      SharedPreferences.setMockInitialValues({});
      await OnboardingStore.markCompleted();
      expect(await OnboardingStore.isCompleted(), isTrue);
    });
  });

  group('OnboardingScreen', () {
    Widget host() => const MaterialApp(home: OnboardingScreen(isReplay: true));

    testWidgets('walks through every page to the final button', (tester) async {
      await tester.pumpWidget(host());
      expect(find.text('See what’s next'), findsOneWidget);
      expect(find.text('Next up'), findsOneWidget);
      expect(find.text('Starts in 45 min'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-preview-0')),
        findsOneWidget,
      );
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('See how to add classes'));
      await tester.pumpAndSettle();
      expect(find.text('Add your timetable'), findsOneWidget);
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Weekly timetable'), findsOneWidget);

      await tester.tap(find.text('See reminders and backup'));
      await tester.pumpAndSettle();
      expect(find.text('Keep your week ready'), findsOneWidget);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Alert 10 minutes before class'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget); // replay mode label
      expect(find.text('See reminders and backup'), findsNothing);
    });

    testWidgets('close exits a replayed onboarding', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OnboardingScreen(isReplay: true),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('See what’s next'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('See what’s next'), findsNothing);
    });
  });
}
