import 'package:flutter/material.dart';

import '../models/class_item.dart';
import '../theme/app_theme.dart';
import 'live_pulse.dart';

/// Where a class sits relative to the current time. Only used on today.
enum ClassStatus { done, live, upcoming }

/// Returns the status of [item] at [nowMinutes] (minutes since midnight).
ClassStatus classStatusAt(ClassItem item, int nowMinutes) {
  if (item.startMinutes <= nowMinutes && nowMinutes < item.endMinutes) {
    return ClassStatus.live;
  }
  if (item.endMinutes <= nowMinutes) return ClassStatus.done;
  return ClassStatus.upcoming;
}

/// One class on a timeline: a rail with a status marker on the left, and a
/// card with the time, subject and details on the right.
///
/// Pass [status] only when the list is for today; without it the rail shows
/// neutral markers, which is right for any other day of the week.
class ClassCard extends StatelessWidget {
  final ClassItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showDay;
  final ClassStatus? status;

  /// True for the class the hero block is showing as "Next up". It gets the
  /// same accent so the list links back to the hero.
  final bool isNext;

  const ClassCard({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
    this.showDay = false,
    this.status,
    this.isNext = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final live = AppTheme.liveOf(context);
    final hasProfessor =
        item.professor.trim().isNotEmpty &&
        item.professor.trim() != 'Not specified';
    final room = formatRoom(item.room);
    final isLive = status == ClassStatus.live;
    final isDone = status == ClassStatus.done;
    final hasMenu = onEdit != null || onDelete != null;

    final timeColor = isLive
        ? live
        : isDone
        ? scheme.onSurfaceVariant
        : scheme.primary;
    final subjectColor = isDone ? scheme.onSurfaceVariant : scheme.onSurface;
    final detailStyle = textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    // Match the component sheet: quiet filled rows, with a slightly darker
    // neutral fill for the class highlighted as next. Status is communicated
    // through text color rather than heavy borders or shadows.
    final cardFill = isNext
        ? scheme.surfaceContainerHighest
        : isDone
        ? scheme.surfaceContainerLow.withValues(alpha: 0.6)
        : scheme.surfaceContainer;

    return Semantics(
      container: true,
      label: [
        item.subject,
        item.timeRange,
        room,
        if (hasProfessor) item.professor.trim(),
        if (isLive) 'in progress',
        if (isDone) 'finished',
        if (isNext) 'next class',
      ].join(', '),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.pageInset),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Opacity(
                      opacity: isDone ? 0.5 : 1.0,
                      child: Material(
                        color: cardFill,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                        onTap: onTap,
                        onLongPress: onLongPress,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            14,
                            hasMenu ? 4 : 16,
                            14,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: AnimatedDefaultTextStyle(
                                            duration: AppTheme.motionDuration(
                                              context,
                                              AppTheme.motionStandard,
                                            ),
                                            curve: AppTheme.motionEaseOut,
                                            style:
                                                textTheme.labelLarge
                                                    ?.copyWith(
                                                      color: timeColor,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontFeatures: const [
                                                        FontFeature
                                                            .tabularFigures(),
                                                      ],
                                                    ) ??
                                                const TextStyle(),
                                            child: Text(
                                              item.timeRange,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        if (isLive) ...[
                                          // The one live signal in the list:
                                          // a breathing dot marking "now".
                                          const LivePulse(size: 7),
                                          const SizedBox(width: 8),
                                        ],
                                        if (showDay)
                                          Text(
                                            item.dayName.substring(0, 3),
                                            style: textTheme.labelMedium
                                                ?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.subject,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleMedium?.copyWith(
                                        color: subjectColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        _ClassMeta(
                                          icon: Icons.location_on_outlined,
                                          label: room,
                                          style: detailStyle,
                                        ),
                                        if (hasProfessor)
                                          _ClassMeta(
                                            icon: Icons.person_outline_rounded,
                                            label: item.professor.trim(),
                                            style: detailStyle,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (hasMenu)
                                PopupMenuButton<_ClassAction>(
                                  tooltip: 'More options',
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  onSelected: (action) {
                                    switch (action) {
                                      case _ClassAction.edit:
                                        onEdit?.call();
                                      case _ClassAction.delete:
                                        onDelete?.call();
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (onEdit != null)
                                      const PopupMenuItem(
                                        value: _ClassAction.edit,
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 20),
                                            SizedBox(width: AppTheme.itemGap),
                                            Text('Edit class'),
                                          ],
                                        ),
                                      ),
                                    if (onDelete != null)
                                      PopupMenuItem(
                                        value: _ClassAction.delete,
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: scheme.error,
                                            ),
                                            const SizedBox(
                                              width: AppTheme.itemGap,
                                            ),
                                            Text(
                                              'Delete class',
                                              style: TextStyle(
                                                color: scheme.error,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Gap below each card. It sits inside the row, so the rail
                  // runs continuously from one class to the next.
                  const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ClassAction { edit, delete }

class _ClassMeta extends StatelessWidget {
  const _ClassMeta({required this.icon, required this.label, this.style});

  final IconData icon;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(label, style: style, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}
