# Free Time & Classes Done Hero Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the home screen hero card when today's classes are done or when today is a free day into an encouraging, restful banner with a compact preview shelf for the next upcoming class.

**Architecture:** Extend `NextClass` with day comparison helpers (`isTomorrow`, `dayPillText`). Add celebration state support to `NextClassCard` (clean icons, uplifting titles, and a nested shelf with a high-contrast day pill, time range, countdown, subject, and small metadata). Connect `HomeScreen` to detect all-done vs free-day states and supply the celebration configuration.

**Tech Stack:** Flutter / Dart, Material 3 with `AppTheme` design tokens.

**Spec:** `docs/superpowers/specs/2026-10-22-free-time-next-class-hero-design.md`

## Global Constraints
- Strictly follow `AppTheme` design tokens: `inverseSurface`, `cardRadius` (16), `chipRadius` (12), `cardInset` (16), `itemGap` (12), `FontFeature.tabularFigures()`.
- No emojis; use only clean Material rounded vector icons (`Icons.check_circle_outline_rounded`, `Icons.wb_sunny_outlined`, `Icons.location_on_outlined`, `Icons.person_outline_rounded`).
- Retain existing functionality: tap on the hero card still opens class details/form, long-press handles delete with undo.

## Review Focus
- Class tomorrow vs class multiple days away: Verify that tomorrow displays `TOMORROW` pill, while 2+ days away displays the uppercase weekday name (e.g. `MONDAY`).
- Active day non-regression: When a class is live or upcoming today, the hero card must still show the standard live marker or "Next up" hero.
- Empty schedule: When there are no classes in the schedule at all, `NextClassCard.empty` is still shown.
- All classes today done: When today had 3 classes and all 3 are completed, the hero transitions to "All classes done".
- Free day (0 classes today): When today has 0 classes scheduled but future classes exist, the hero displays "No classes today".

---

### Task 1: Add Day Preview Helper to `NextClass`

**Files:**
- Modify: `lib/utils/next_class.dart`
- Test: `test/next_class_test.dart`

**Interfaces:**
- Consumes: `ClassItem` (`item.day`, `item.dayName`), `DateTime now`
- Produces: `String dayPillText(DateTime now)` on `NextClass`:
  - Returns `'TOMORROW'` if the next class is on the day immediately following `now.weekday` (e.g., Wed -> Thu, or Sun -> Mon).
  - Returns `item.dayName.toUpperCase()` (e.g., `'MONDAY'`, `'FRIDAY'`) if the next class is 2 or more days away.

- [ ] **Step 1: Write the failing unit tests for `dayPillText` in `test/next_class_test.dart`**

```dart
test('dayPillText returns TOMORROW when next class is on the following day', () {
  final now = DateTime(2026, 10, 14, 18); // Wednesday evening
  final next = NextClass(cls('Science', 4, 8, 10), false, 840); // Thursday
  expect(next.dayPillText(now), 'TOMORROW');
});

test('dayPillText returns uppercase day name when next class is 2+ days away', () {
  final now = DateTime(2026, 10, 16, 18); // Friday evening
  final next = NextClass(cls('Math', 1, 8, 10), false, 3720); // Monday
  expect(next.dayPillText(now), 'MONDAY');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/next_class_test.dart`  
Expected: FAIL with "The method 'dayPillText' isn't defined"

- [ ] **Step 3: Implement `dayPillText(DateTime now)` in `lib/utils/next_class.dart`**

Add method to `NextClass`:
```dart
String dayPillText(DateTime now) {
  final tomorrowWeekday = (now.weekday % 7) + 1;
  if (item.day == tomorrowWeekday) {
    return 'TOMORROW';
  }
  return item.dayName.toUpperCase();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/next_class_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/utils/next_class.dart test/next_class_test.dart
git commit -m "feat: add dayPillText helper to NextClass"
```

---

### Task 2: Implement Celebration Layout with Day Pill in `NextClassCard`

**Files:**
- Modify: `lib/widgets/next_class_card.dart`
- Test: `test/ui_widgets_test.dart`

**Interfaces:**
- Consumes: `AppTheme` tokens, `IconData? celebrationIcon`, `String? celebrationTitle`, `String? celebrationSubtitle`, `String? dayPillText`.
- Produces: `NextClassCard` widget that conditionally renders either:
  1. Standard active layout (`celebrationTitle == null`).
  2. Celebration layout (`celebrationTitle != null`): Top celebration section with clean icon, bold title, and muted subtitle; followed by the nested shelf with high-contrast day pill, time range, countdown, subject, and small room/instructor metadata.

- [ ] **Step 1: Write the failing widget tests in `test/ui_widgets_test.dart`**

```dart
testWidgets('NextClassCard renders celebration state with day pill shelf', (tester) async {
  await tester.pumpWidget(
    _host(
      const NextClassCard(
        label: 'Next up',
        subject: 'Advanced Mathematics',
        room: 'Room 304',
        professor: 'Prof. Santos',
        time: '08:00 AM - 09:30 AM',
        whenText: 'Starts in 16h 20m',
        celebrationTitle: 'All classes done',
        celebrationSubtitle: 'Good job today — rest up and recharge.',
        celebrationIcon: Icons.check_circle_outline_rounded,
        dayPillText: 'TOMORROW',
      ),
    ),
  );

  expect(find.text('All classes done'), findsOneWidget);
  expect(find.text('Good job today — rest up and recharge.'), findsOneWidget);
  expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
  expect(find.text('TOMORROW'), findsOneWidget);
  expect(find.text('08:00 AM - 09:30 AM'), findsOneWidget);
  expect(find.text('Starts in 16h 20m'), findsOneWidget);
  expect(find.text('Advanced Mathematics'), findsOneWidget);
  expect(find.text('Room 304'), findsOneWidget);
  expect(find.text('Prof. Santos'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui_widgets_test.dart`  
Expected: FAIL with "No named parameter with the name 'celebrationTitle'"

- [ ] **Step 3: Update `NextClassCard` to support celebration mode**

In `lib/widgets/next_class_card.dart`:
1. Add optional parameters:
   - `final String? celebrationTitle;`
   - `final String? celebrationSubtitle;`
   - `final IconData? celebrationIcon;`
   - `final String? dayPillText;`
2. In `build(BuildContext context)`:
   - If `celebrationTitle != null`:
     - Render top header with `celebrationIcon`, `celebrationTitle`, and `celebrationSubtitle`.
     - Render shelf container (`color: foreground.withValues(alpha: 0.08)`, `borderRadius: BorderRadius.circular(AppTheme.controlRadius)`).
     - Inside shelf:
       - Row with `Container` pill (`color: scheme.primary`, `padding: 2px 9px`, `borderRadius: AppTheme.chipRadius`, text: `dayPillText`), followed by `time` with tabular figures, and `Spacer` + `whenText`.
       - Title: `subject` in `textTheme.titleMedium` with `foreground`.
       - Metadata: `room` and `professor` in `_NextClassMeta` rows.
   - If `celebrationTitle == null`: keep existing active layout.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui_widgets_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/next_class_card.dart test/ui_widgets_test.dart
git commit -m "feat: add celebration state and day pill shelf to NextClassCard"
```

---

### Task 3: Wire Celebration States in `HomeScreen` and Verify End-to-End

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Test: `test/home_screen_hero_test.dart` (new widget test file)

**Interfaces:**
- Consumes: `findNextClass`, `next.dayPillText(now)`, `today`, `doneCount`, `NextClassCard`
- Produces: Dynamic hero card in `HomeScreen` passing celebration parameters when all classes are done or when today is a free day.

- [ ] **Step 1: Write widget test in `test/home_screen_hero_test.dart`**

Create test verifying:
1. When today has classes and all are done, `HomeScreen` displays "All classes done" and the `TOMORROW` pill.
2. When today has no classes and tomorrow has classes, `HomeScreen` displays "No classes today" and the `TOMORROW` pill.
3. When today has an active class, `HomeScreen` displays the standard "In class" or "Next up" badge without celebration.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/home_screen_hero_test.dart`  
Expected: FAIL

- [ ] **Step 3: Update `HomeScreen` hero builder in `lib/screens/home_screen.dart`**

Compute:
```dart
final allDoneForToday = hasTodayClasses && doneCount == today.length;
final isFreeDay = !hasTodayClasses && _classes.isNotEmpty;
```
When building `NextClassCard`:
```dart
celebrationTitle: allDoneForToday
    ? 'All classes done'
    : isFreeDay
        ? 'No classes today'
        : null,
celebrationSubtitle: allDoneForToday
    ? 'Good job today — rest up and recharge.'
    : isFreeDay
        ? 'Enjoy your free time and recharge.'
        : null,
celebrationIcon: allDoneForToday
    ? Icons.check_circle_outline_rounded
    : isFreeDay
        ? Icons.wb_sunny_outlined
        : null,
dayPillText: (allDoneForToday || isFreeDay) ? next.dayPillText(now) : null,
```

- [ ] **Step 4: Run all tests to verify everything passes**

Run: `flutter test`  
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart test/home_screen_hero_test.dart
git commit -m "feat: wire celebration states on home screen hero card"
```
