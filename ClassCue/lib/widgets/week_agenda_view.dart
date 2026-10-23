import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../theme/app_theme.dart';
import 'campus_break_divider.dart';
import 'class_card.dart';
import 'empty_state_card.dart';
import 'selected_day_header.dart';
import 'weekday_tile.dart';

/// Single-day agenda view showing the 1-row week strip, sticky day header,
/// and time-ordered class cards with campus break indicators.
class WeekAgendaView extends StatelessWidget {
  const WeekAgendaView({
    super.key,
    required this.classesByDay,
    required this.allClassesEmpty,
    required this.today,
    required this.nowMinutes,
    required this.selectedDay,
    required this.onSelectDay,
    this.onTap,
    this.statusFor,
    this.focusClassId,
    required this.onEdit,
    required this.onLongPress,
    required this.onAddClassForDay,
  });

  final Map<int, List<ClassItem>> classesByDay;
  final bool allClassesEmpty;
  final int today;
  final int nowMinutes;
  final int selectedDay;
  final ValueChanged<int> onSelectDay;
  final ValueChanged<ClassItem>? onTap;
  final ClassStatusEntry? Function(ClassItem item)? statusFor;

  /// The class the hero focuses on, when it is today's. Its time takes the live color.
  final int? focusClassId;
  final ValueChanged<ClassItem> onEdit;
  final ValueChanged<ClassItem> onLongPress;
  final ValueChanged<int> onAddClassForDay;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Normalize to date-only to eliminate Daylight Saving Time and hour boundary drift
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final monday = todayMidnight.subtract(Duration(days: today - 1));
    final selectedDate = monday.add(Duration(days: selectedDay - 1));
    final selectedClasses = classesByDay[selectedDay]!;
    final isToday = selectedDay == today;

    // Calculate total hours scheduled for the selected day
    final totalHours = selectedClasses.fold<double>(
      0.0,
      (sum, item) => sum + ((item.endMinutes - item.startMinutes) / 60.0),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppTheme.pageContentMaxWidth,
        ),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Responsive 1-row week strip
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pageInset,
                10,
                AppTheme.pageInset,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Semantics(
                  label: 'Choose a day of the week',
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final weekdayTiles = [
                        for (var index = 0; index < dayNames.length; index++)
                          WeekdayTile(
                            date: monday.add(Duration(days: index)),
                            name: dayNames[index],
                            classCount: classesByDay[index + 1]!.length,
                            isToday: index + 1 == today,
                            selected: index + 1 == selectedDay,
                            onTap: () => onSelectDay(index + 1),
                          ),
                      ];

                      // If width allows, distribute evenly across the row
                      if (constraints.maxWidth >= dayNames.length * 44) {
                        return Row(
                          children: [
                            for (final tile in weekdayTiles)
                              Expanded(child: tile),
                          ],
                        );
                      }

                      // On narrower widths, keep a smooth single-row horizontal scroll
                      // rather than breaking the week into disjoint rows
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (final tile in weekdayTiles)
                              SizedBox(width: 48, child: tile),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),

            // Sticky Header displaying Selected Day and Daily Workload Badge
            SliverPersistentHeader(
              pinned: true,
              delegate: SelectedDayHeaderDelegate(
                dayName: dayNames[selectedDay - 1],
                formattedDate:
                    MaterialLocalizations.of(context).formatShortMonthDay(selectedDate),
                classCount: selectedClasses.length,
                totalHours: totalHours,
              ),
            ),

            // Class List or Empty States
            if (selectedClasses.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.pageInset,
                  16,
                  AppTheme.pageInset,
                  100,
                ),
                sliver: SliverToBoxAdapter(
                  child: allClassesEmpty
                      ? EmptyStateCard(
                          icon: Icons.calendar_month_outlined,
                          title: 'Build your week',
                          message:
                              'Add your first class now, or bring in a timetable to review before saving.',
                          actions: [
                            FilledButton.icon(
                              onPressed: () => onAddClassForDay(selectedDay),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add a class'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pushNamed<void>(AppRoutes.importSchedule),
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('Import a timetable'),
                            ),
                          ],
                        )
                      : EmptyStateCard(
                          icon: Icons.event_available_outlined,
                          title: 'Nothing scheduled',
                          message: 'Enjoy your open space.',
                          actions: [
                            FilledButton.icon(
                              onPressed: () => onAddClassForDay(selectedDay),
                              icon: const Icon(Icons.add_rounded),
                              label: Text(
                                  'Add a class for ${dayNames[selectedDay - 1]}'),
                            ),
                          ],
                        ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 12, bottom: 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // Items alternate between class cards and break dividers
                      if (index.isOdd) {
                        final prevIndex = index ~/ 2;
                        final prevClass = selectedClasses[prevIndex];
                        final nextClass = selectedClasses[prevIndex + 1];
                        final gapMinutes =
                            nextClass.startMinutes - prevClass.endMinutes;

                        if (gapMinutes >= 15) {
                          return CampusBreakDivider(breakMinutes: gapMinutes);
                        }
                        // Consecutive classes: ClassCard already includes standard 10px bottom gap.
                        return const SizedBox.shrink();
                      }

                      final classIndex = index ~/ 2;
                      final item = selectedClasses[classIndex];
                      return ClassCard(
                        item: item,
                        status: isToday ? classStatusAt(item, nowMinutes) : null,
                        statusEntry: statusFor?.call(item),
                        isFocus: focusClassId != null && item.id == focusClassId,
                        onTap: onTap != null ? () => onTap!(item) : null,
                        onEdit: () => onEdit(item),
                        onDelete: () => onLongPress(item),
                        onLongPress: () => onLongPress(item),
                      );
                    },
                    // Count includes class cards plus dividers between them
                    childCount: math.max(0, selectedClasses.length * 2 - 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
