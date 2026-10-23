import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'live_pulse.dart';

/// The hero block at the top of Today: the class in progress, or the next one.
///
/// It is the only inverted surface on the screen, so the eye lands here first.
/// Time, room, and instructor follow the order used in the component guide.
class NextClassCard extends StatelessWidget {
  final String label;
  final String subject;
  final String room;
  final String professor;
  final String time;
  final String whenText;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? celebrationTitle;
  final String? celebrationSubtitle;
  final IconData? celebrationIcon;
  final String? dayPillText;

  const NextClassCard({
    super.key,
    required this.label,
    required this.subject,
    required this.room,
    this.professor = '',
    required this.time,
    required this.whenText,
    this.onTap,
    this.onLongPress,
    this.celebrationTitle,
    this.celebrationSubtitle,
    this.celebrationIcon,
    this.dayPillText,
  });

  const NextClassCard.empty({super.key})
    : label = 'Next class',
      subject = 'Your next class will appear here.',
      room = '',
      professor = '',
      time = '',
      whenText = '',
      onTap = null,
      onLongPress = null,
      celebrationTitle = null,
      celebrationSubtitle = null,
      celebrationIcon = null,
      dayPillText = null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = scheme.onInverseSurface;
    final muted = foreground.withValues(alpha: .8);
    final meta = <({IconData icon, String value})>[
      if (room.trim().isNotEmpty)
        (icon: Icons.location_on_outlined, value: room.trim()),
      if (professor.trim().isNotEmpty)
        (icon: Icons.person_outline_rounded, value: professor.trim()),
    ];
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
    );
    final isCelebration = celebrationTitle != null;

    return SizedBox(
      width: double.infinity,
      child: Semantics(
        container: true,
        button: onTap != null,
        label: [
          if (celebrationTitle != null) celebrationTitle!,
          if (celebrationSubtitle != null) celebrationSubtitle!,
          if (dayPillText != null) dayPillText!,
          label,
          subject,
          time,
          room,
          professor,
          whenText,
        ].where((value) => value.trim().isNotEmpty).join('. '),
        child: Material(
          color: scheme.inverseSurface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            customBorder: shape,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.cardInset),
              child: isCelebration
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (celebrationIcon != null) ...[
                              Icon(
                                celebrationIcon,
                                size: 22,
                                color: foreground,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                celebrationTitle!,
                                style: textTheme.titleLarge?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (celebrationSubtitle != null &&
                            celebrationSubtitle!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            celebrationSubtitle!,
                            style: textTheme.bodySmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                              AppTheme.controlRadius,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  if (dayPillText != null &&
                                      dayPillText!.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: foreground,
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.chipRadius,
                                        ),
                                      ),
                                      child: Text(
                                        dayPillText!,
                                        style: textTheme.labelSmall?.copyWith(
                                          color: scheme.inverseSurface,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  if (whenText.isNotEmpty)
                                    Text(
                                      whenText,
                                      style: textTheme.labelMedium?.copyWith(
                                        color: muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    subject,
                                    style: textTheme.titleMedium?.copyWith(
                                      color: foreground,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (time.isNotEmpty)
                                    Text(
                                      time,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: muted,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              if (meta.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    for (final m in meta)
                                      _NextClassMeta(
                                        icon: m.icon,
                                        value: m.value,
                                        color: muted,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: muted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (whenText.isEmpty)
                          _StatusTag(label: label, foreground: foreground)
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final whenMaxWidth = (constraints.maxWidth - 88)
                                  .clamp(0.0, constraints.maxWidth)
                                  .toDouble();
                              return Row(
                                children: [
                                  _StatusTag(
                                    label: label,
                                    foreground: foreground,
                                  ),
                                  const Spacer(),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: whenMaxWidth,
                                    ),
                                    child: Text(
                                      whenText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: textTheme.labelLarge?.copyWith(
                                        color: foreground,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        const SizedBox(height: 12),
                        Text(
                          subject,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge?.copyWith(
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (time.isNotEmpty)
                          Text(
                            time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              color: foreground,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < meta.length; i++) ...[
                                if (i > 0)
                                  const SizedBox(height: AppTheme.tightGap / 2),
                                _NextClassMeta(
                                  icon: meta[i].icon,
                                  value: meta[i].value,
                                  color: muted,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextClassMeta extends StatelessWidget {
  const _NextClassMeta({
    required this.icon,
    required this.value,
    required this.color,
    required this.style,
  });

  final IconData icon;
  final String value;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(child: Icon(icon, size: 16, color: color)),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    ],
  );
}

/// "Next up" / "In class".
///
/// The pill itself never resizes or jumps: the label crossfades when the
/// status changes (the minute ticker flips "Next up" to "In class"), and an
/// "In class" state carries a live pulse dot as its state indicator.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.foreground});

  final String label;
  final Color foreground;

  static const double _labelHeight = 16;

  @override
  Widget build(BuildContext context) {
    final isLive = label == 'In class';
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            LivePulse(size: 6, color: foreground, haloOpacity: 0.3),
            const SizedBox(width: 6),
          ],
          _CrossFadeText(
            text: label,
            height: _labelHeight,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
    return AnimatedContainer(
      duration: AppTheme.motionDuration(context, AppTheme.motionStandard),
      curve: AppTheme.motionEaseOut,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle(
        style: const TextStyle(),
        child: IntrinsicWidth(child: content),
      ),
    );
  }
}

/// Crossfades between two strings without letting the shorter one collapse
/// the row: the box keeps the width of whichever variant is widest.
class _CrossFadeText extends StatelessWidget {
  const _CrossFadeText({
    required this.text,
    required this.height,
    required this.style,
  });

  final String text;
  final double height;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final variant = Text(
      text,
      style: style,
      maxLines: 1,
      textAlign: TextAlign.center,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        // Invisible widest label reserves the space so the pill never snaps.
        Opacity(opacity: 0, child: Text('In class', style: style)),
        AnimatedSwitcher(
          duration: AppTheme.motionDuration(
            context,
            AppTheme.motionStandard,
          ),
          switchInCurve: AppTheme.motionEaseOut,
          switchOutCurve: AppTheme.motionEaseOut,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(
            key: ValueKey(text),
            child: SizedBox(height: height, child: variant),
          ),
        ),
      ],
    );
  }
}
