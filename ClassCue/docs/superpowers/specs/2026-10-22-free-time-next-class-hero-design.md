# Design Spec: Free Time & Classes Done Hero Card

**Date**: 2026-10-22  
**Status**: Pending Approval  

---

## 1. Intent & Context
Currently, when all classes for today are finished—or when today has no classes scheduled—the home screen hero card (`NextClassCard`) displays tomorrow's class with the same high-urgency "Next up" badge as if it were starting in 10 minutes.

This design introduces a celebratory, restful state when a student is done for the day or enjoying a day off, while keeping upcoming class awareness via a compact, secondary shelf.

---

## 2. Requirements & Behavior

### A. States
1. **Classes Finished Today (`allDoneForToday`)**:
   - Condition: Today has $\ge 1$ classes scheduled, and all are marked `done`.
   - Icon: `Icons.check_circle_outline_rounded` (quiet, refined outline)
   - Title: **All classes done**
   - Subtitle: **Good job today — rest up and recharge.**
2. **Free Day / Day Off (`isFreeDay`)**:
   - Condition: Today has 0 classes scheduled (e.g., weekend or free weekday) and the student has other classes in the schedule.
   - Icon: `Icons.wb_sunny_outlined` or `Icons.calendar_today_outlined`
   - Title: **No classes today**
   - Subtitle: **Enjoy your free time and recharge.**
3. **Active Day (Existing behavior preserved)**:
   - When a class is live (`In class`) or upcoming today (`Next up`), the existing hero layout is displayed.

### B. Next Class Shelf Layout (Variations 2 & 3)
Inside the hero card, below the celebration header, a compact shelf displays the upcoming class:
* **Header Strip**:
  * **Day Pill**: A distinct, high-contrast badge:
    * `TOMORROW` if the class is on the immediately following day.
    * `<DAYNAME>` (e.g. `MONDAY`, `FRIDAY`) if the class is 2+ days away.
  * **Time Range**: `item.timeRange` formatted with tabular figures.
  * **Countdown**: `next.whenText` (e.g. `Starts in 16h 20m` or `Starts in 2d 14h`).
* **Subject**: Full or 2-line title in bold.
* **Metadata**: Small icons and text for `Room` and `Instructor` (hidden if not set).
* **Tap / Long Press**: Tapping the card opens class details / edit; long-press opens delete options.

---

## 3. Design System & Token Consistency

To strictly follow ClassCue's existing theme tokens (`AppTheme`):
* **Surface**: Card maintains `scheme.inverseSurface` background with `AppTheme.cardRadius` (16px) and `AppTheme.cardInset` (16px).
* **Shelf Background**: `surfaceContainerHigh` or `onInverseSurface.withValues(alpha: 0.08)` to stay monochromatic with subtle depth.
* **Day Pill**:
  * Shape: `RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.chipRadius))` (12px) or 8px block.
  * Color: `scheme.primary` or high-contrast accent with white/on-primary text.
* **Typography**:
  * Title: `textTheme.titleLarge` with bold weight.
  * Subtitle: `textTheme.bodySmall` / `textTheme.bodyMedium` with `onInverseSurface` muted ($80\%$ opacity).
  * Shelf subject: `textTheme.titleMedium` ($600$ weight).
  * Shelf metadata: `textTheme.bodySmall` with tabular figures on time numbers.
* **Accessibility**: Full semantic label grouping celebration, day pill, subject, time, and countdown.

---

## 4. Approaches Considered

1. **Option A (Side-by-Side Split)**:
   - *Pros*: Compact vertical height.
   - *Cons*: Restricts horizontal width on small mobile screens (e.g. 360dp), causing long course names or professor titles to truncate aggressively.
2. **Option B (Stacked Celebration + Shelf with Day Pill) [SELECTED]**:
   - *Pros*: Strong visual hierarchy. Room for encouraging copy and unconstrained course details. Responsive across all phone sizes.
   - *Trade-off*: Slightly taller card height, but sits in an empty space on days with no other active classes.
3. **Option C (Minimal Status Footer)**:
   - *Pros*: Minimalist.
   - *Cons*: Next class info feels cramped into a single footer line without visual emphasis on the day.

---

## 5. Technical Touchpoints

1. [`lib/utils/next_class.dart`](file:///c:/Users/clarisse%20sibug/OneDrive/Desktop/CARL/ClassCue_mobile/lib/utils/next_class.dart):
   - Add helper properties to determine if the next class is tomorrow vs another weekday relative to `DateTime.now()`.
2. [`lib/widgets/next_class_card.dart`](file:///c:/Users/clarisse%20sibug/OneDrive/Desktop/CARL/ClassCue_mobile/lib/widgets/next_class_card.dart):
   - Support the celebration mode with `celebrationTitle`, `celebrationSubtitle`, and day pill badge in the secondary shelf.
3. [`lib/screens/home_screen.dart`](file:///c:/Users/clarisse%20sibug/OneDrive/Desktop/CARL/ClassCue_mobile/lib/screens/home_screen.dart):
   - Check `today.isEmpty` vs `doneCount == today.length` to supply the appropriate celebration state to `NextClassCard`.
4. Tests:
   - Add widget tests for the celebration hero card covering "All classes done" and "Free day".
