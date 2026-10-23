import 'package:flutter/material.dart';

import '../features/schedule_import/models/import_draft.dart';
import '../features/schedule_import/widgets/import_review_widgets.dart';
import '../models/class_item.dart';
import '../routes/app_routes.dart';
import '../services/onboarding_store.dart';
import '../theme/app_theme.dart';
import '../widgets/class_card.dart';
import '../widgets/component_kit.dart';
import '../widgets/next_class_card.dart';
import '../widgets/pill.dart';

class _OnboardingPage {
  final String title;
  final String body;
  final String continueLabel;
  final String previewDescription;

  /// A static, non-interactive preview of the real UI shown above the text.
  final WidgetBuilder preview;
  const _OnboardingPage(
    this.title,
    this.body,
    this.continueLabel,
    this.previewDescription,
    this.preview,
  );
}

final _pages = <_OnboardingPage>[
  _OnboardingPage(
    'See what’s next',
    'Today shows your current or next class. Tap a class for its room and details; use Week to choose a day and scan your full schedule.',
    'See how to add classes',
    'Today preview: the next class, another class, and the Today, Week, and Settings tabs.',
    (_) => const _TodayPreview(),
  ),
  _OnboardingPage(
    'Add your timetable',
    'Tap Add class to enter one yourself, or choose Import a timetable for a photo or PDF. Review detected times, rooms, and conflicts before saving.',
    'See reminders and backup',
    'Import preview: choose a timetable, inspect flagged class details, then save the reviewed schedule.',
    (_) => const _ImportPreview(),
  ),
  _OnboardingPage(
    'Keep your week ready',
    'Open Settings to turn on weekly reminders, sent 10 minutes before class. Export a backup before switching phones; restoring replaces the current schedule.',
    'Add my first class',
    'Settings preview: weekly reminders and schedule backup.',
    (_) => const _ReadyPreview(),
  ),
];

class OnboardingScreen extends StatefulWidget {
  /// True when opened again from Settings: finishing just closes the screen.
  final bool isReplay;
  const OnboardingScreen({super.key, this.isReplay = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == _pages.length - 1;
  bool get _isFirstRunStartPage => !widget.isReplay && _page == 0;
  bool get _showImportAction => !widget.isReplay && (_isLast || _page == 0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (widget.isReplay) {
      Navigator.pop(context);
      return;
    }
    await OnboardingStore.markCompleted();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.home);
  }

  Future<void> _startWith(String route) async {
    await OnboardingStore.markCompleted();
    if (!mounted) return;
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.home);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _moveToPage(_page + 1);
    }
  }

  void _moveToPage(int page) {
    if (MediaQuery.of(context).disableAnimations) {
      _controller.jumpToPage(page);
      return;
    }
    _controller.animateToPage(
      page,
      duration: AppTheme.motionPage,
      curve: AppTheme.motionEaseInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      // System back steps to the previous page before leaving the screen.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _moveToPage(_page - 1);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.asset(
                        'assets/classcue_logo.png',
                        width: 32,
                        height: 32,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'ClassCue',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _finish,
                      child: Text(widget.isReplay ? 'Close' : 'Skip'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                container: true,
                                label: page.previewDescription,
                                child: ExcludeSemantics(
                                  child: IgnorePointer(
                                    child: _PreviewPanel(
                                      key: ValueKey('onboarding-preview-$i'),
                                      title: switch (i) {
                                        0 => 'Today',
                                        1 => 'Weekly timetable',
                                        _ => 'Settings',
                                      },
                                      child: page.preview(context),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(page.title, style: textTheme.headlineSmall),
                              const SizedBox(height: 8),
                              Text(
                                _isFirstRunStartPage
                                    ? '${page.body} Swipe for more tips, or get started below.'
                                    : page.body,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Semantics(
                  label: 'Step ${_page + 1} of ${_pages.length}',
                  liveRegion: true,
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Text(
                          'Step ${_page + 1} of ${_pages.length}',
                          style: textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        for (var i = 0; i < _pages.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: AnimatedContainer(
                              duration: AppTheme.motionDuration(
                                context,
                                AppTheme.motionStandard,
                              ),
                              curve: AppTheme.motionEaseOut,
                              height: 4,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? scheme.primary
                                    : scheme.outlineVariant,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isFirstRunStartPage
                                ? () => _startWith(AppRoutes.classForm)
                                : _isLast
                                ? widget.isReplay
                                      ? _finish
                                      : () => _startWith(AppRoutes.classForm)
                                : _next,
                            child: Text(
                              _isFirstRunStartPage
                                  ? 'Add my first class'
                                  : !_isLast
                                  ? _pages[_page].continueLabel
                                  : widget.isReplay
                                  ? 'Done'
                                  : 'Add my first class',
                            ),
                          ),
                        ),
                        if (_showImportAction) ...[
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: () =>
                                  _startWith(AppRoutes.importSchedule),
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: const Text('Import a timetable'),
                            ),
                          ),
                        ],
                        if (_isFirstRunStartPage)
                          TextButton(
                            onPressed: _next,
                            child: const Text('Continue tour'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Pill(
                  label: 'Example',
                  background: scheme.surfaceContainerHigh,
                  foreground: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

class _TodayPreview extends StatelessWidget {
  const _TodayPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime.now().weekday;
    final laterClass = ClassItem(
      subject: 'Web Development',
      room: 'Lab 2',
      professor: 'Not specified',
      day: today,
      startMinutes: 15 * 60,
      endMinutes: 16 * 60 + 30,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dayNames[today - 1],
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Text(
                '2 classes',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const NextClassCard(
          label: 'Next up',
          subject: 'Data Structures',
          room: 'Room 304',
          professor: 'Prof. Santos',
          time: '1:00 PM - 2:30 PM',
          whenText: 'Starts in 45 min',
        ),
        const SizedBox(height: 4),
        ClassCard(item: laterClass),
        const SizedBox(height: 6),
        const _NavPreview(selectedIndex: 0),
      ],
    );
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final draft = ImportDraft(
      subject: 'Network Lab',
      room: 'Room to confirm',
      professor: 'Prof. Santos',
      day: 2,
      start: 13 * 60,
      end: 14 * 60 + 30,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Choose a timetable'),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Review detected classes',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 4),
        ImportDraftCard(
          draft: draft,
          note: null,
          unknownRoom: true,
          ocrReviewNeeded: true,
          ocrReviewLabel: 'Check scanned text',
          onTap: () {},
          onDelete: () {},
        ),
        const ImportAttentionBanner(
          title: 'Check flagged details',
          message: 'Confirm rooms and resolve conflicts before importing.',
        ),
      ],
    );
  }
}

class _ReadyPreview extends StatelessWidget {
  const _ReadyPreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Schedule',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SettingsRow(
                icon: Icons.notifications_active_outlined,
                title: 'Class reminders',
                subtitle: 'Alert 10 minutes before class',
                compact: true,
                onTap: () {},
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              SettingsRow(
                icon: Icons.backup_outlined,
                title: 'Backup and restore',
                subtitle: 'Export a copy of your schedule',
                compact: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mirrors the compact icon navigation and quick-action button used in-app.
class _NavPreview extends StatelessWidget {
  const _NavPreview({required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const items = [
      (Icons.today_rounded, 'Today'),
      (Icons.calendar_view_week_rounded, 'Week'),
      (Icons.settings_rounded, 'Settings'),
    ];

    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == selectedIndex,
                      label: items[i].$2,
                      child: SizedBox(
                        height: 40,
                        child: Center(
                          child: Container(
                            width: 52,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: i == selectedIndex
                                  ? scheme.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              items[i].$1,
                              size: 22,
                              color: i == selectedIndex
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          ),
          child: Icon(Icons.add_rounded, color: scheme.onPrimary, size: 24),
        ),
      ],
    );
  }
}
