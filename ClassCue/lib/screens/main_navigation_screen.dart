import 'dart:async';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/class_item.dart';
import '../routes/app_routes.dart';
import '../services/next_class_widget_service.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_navigation_item.dart';
import '../widgets/quick_action_menu.dart';
import '../widgets/quick_actions_button.dart';
import 'home_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  /// Tab indexes, so other screens can ask for one without magic numbers.
  static const todayTab = 0;
  static const weekTab = 1;

  /// Pages pushed on top of this shell (e.g. timetable import) set this to ask
  /// for a tab once they close. The shell switches to it and clears the value.
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  int? _pendingDestination;
  bool _switchingDestination = false;
  bool _quickActionsExpanded = false;
  int _selectedWeekday = DateTime.now().weekday;
  final _database = DatabaseHelper.instance;
  int _widgetSyncVersion = 0;
  late final AnimationController _screenTransitionController;
  late final CurvedAnimation _screenOpacity;

  /// +1 when moving to a later tab, -1 for an earlier one. The incoming screen
  /// slides in from that side, so the direction of travel is visible.
  int _direction = 1;

  /// Classes from the last database read, used to recount today's remaining
  /// classes as time passes without another database query.
  List<ClassItem> _classes = const [];
  int _todayRemaining = 0;
  bool _remindersEnabled = false;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    _screenTransitionController = AnimationController(
      vsync: this,
      duration: AppTheme.motionFast,
    )..value = 1;
    _screenOpacity = CurvedAnimation(
      parent: _screenTransitionController,
      curve: AppTheme.motionEaseOut,
      reverseCurve: AppTheme.motionEaseOut,
    );
    _database.addListener(_onScheduleChanged);
    ReminderService.instance.addListener(_onReminderSettingsChanged);
    MainNavigationScreen.tabRequest.addListener(_onTabRequested);
    unawaited(_loadReminderState());
    _minuteTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _recountToday(),
    );
    unawaited(_syncWidgetSchedule());
  }

  @override
  void dispose() {
    _database.removeListener(_onScheduleChanged);
    ReminderService.instance.removeListener(_onReminderSettingsChanged);
    MainNavigationScreen.tabRequest.removeListener(_onTabRequested);
    _minuteTimer?.cancel();
    _widgetSyncVersion++;
    _screenOpacity.dispose();
    _screenTransitionController.dispose();
    super.dispose();
  }

  void _onScheduleChanged() {
    unawaited(_syncWidgetSchedule());
  }

  void _onTabRequested() {
    final index = MainNavigationScreen.tabRequest.value;
    if (index == null) return;
    MainNavigationScreen.tabRequest.value = null;
    if (!mounted || index < 0 || index >= _destinations.length) return;
    _selectDestination(index);
  }

  void _onReminderSettingsChanged() {
    unawaited(_loadReminderState());
  }

  Future<void> _loadReminderState() async {
    final enabled = await ReminderService.instance.isEnabled;
    if (!mounted || enabled == _remindersEnabled) return;
    setState(() => _remindersEnabled = enabled);
  }

  Future<void> _syncWidgetSchedule() async {
    final version = ++_widgetSyncVersion;
    try {
      final classes = await _database.getAll();
      final statuses = await _database.getClassStatuses();
      if (!mounted || version != _widgetSyncVersion) return;
      _classes = classes;
      _recountToday();
      await NextClassWidgetService.sync(classes, statuses: statuses);
    } catch (error, stackTrace) {
      debugPrint(
        'Could not load classes for the launcher widget: $error\n$stackTrace',
      );
    }
  }

  /// Classes today that have not ended yet. Shown as the Today badge.
  void _recountToday() {
    if (!mounted) return;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final remaining = _classes
        .where((c) => c.day == now.weekday && c.endMinutes > nowMinutes)
        .length;
    if (remaining != _todayRemaining) {
      setState(() => _todayRemaining = remaining);
    }
  }

  static const _destinations =
      <({IconData icon, IconData selectedIcon, String label})>[
        (
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_rounded,
          label: 'Today',
        ),
        (
          icon: Icons.calendar_view_week_outlined,
          selectedIcon: Icons.calendar_view_week_rounded,
          label: 'Week',
        ),
        (
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
          label: 'Settings',
        ),
      ];

  /// Today shows remaining classes; Settings shows a dot when reminders are off.
  Widget _tabIcon(int index, {required bool selected}) {
    final destination = _destinations[index];
    final icon = Icon(selected ? destination.selectedIcon : destination.icon);
    if (index == 0 && _todayRemaining > 0) {
      return Badge(label: Text('$_todayRemaining'), child: icon);
    }
    if (index == 2 && !_remindersEnabled) {
      return Badge(
        smallSize: 8,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: icon,
      );
    }
    return icon;
  }

  Future<void> _openQuickAction(String route) async {
    setState(() => _quickActionsExpanded = false);
    if (route == AppRoutes.importSchedule) {
      await Navigator.of(context, rootNavigator: true)
          .pushNamed<void>(AppRoutes.importSchedule);
      return;
    }
    final selectedDay = route == AppRoutes.classForm && _selectedIndex == 1
        ? _selectedWeekday
        : null;
    await Navigator.of(context).pushNamed(route, arguments: selectedDay);
  }

  void _onWeekdaySelected(int day) {
    if (day == _selectedWeekday) return;
    setState(() => _selectedWeekday = day);
  }

  Widget _quickActionMenu() => QuickActionMenu(
    onAddClass: () => unawaited(_openQuickAction(AppRoutes.classForm)),
    importLabel: 'Import timetable',
    onImportClass: () => unawaited(_openQuickAction(AppRoutes.importSchedule)),
  );

  Widget _quickActionMenuTransition({bool withBottomGap = false}) =>
      AnimatedSwitcher(
        duration: AppTheme.motionDuration(context, AppTheme.motionFast),
        switchInCurve: AppTheme.motionEaseOut,
        switchOutCurve: AppTheme.motionEaseOut,
        transitionBuilder: (child, animation) => ExcludeSemantics(
          excluding: animation.status == AnimationStatus.reverse,
          child: IgnorePointer(
            ignoring: animation.status == AnimationStatus.reverse,
            child: FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                alignment: Alignment.bottomRight,
                scale: Tween<double>(begin: .97, end: 1).animate(animation),
                child: child,
              ),
            ),
          ),
        ),
        child: _quickActionsExpanded
            ? Padding(
                key: const ValueKey('quick-actions-menu'),
                padding: EdgeInsets.only(bottom: withBottomGap ? 8 : 0),
                child: _quickActionMenu(),
              )
            : const SizedBox(key: ValueKey('quick-actions-menu-closed')),
      );

  Widget _quickActionsButton() => QuickActionsButton(
    expanded: _quickActionsExpanded,
    onPressed: () =>
        setState(() => _quickActionsExpanded = !_quickActionsExpanded),
  );

  Widget _mobileNavigationBar() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < _destinations.length; i++)
                      Expanded(
                        child: BottomNavigationItem(
                          label: _destinations[i].label,
                          selected: i == _selectedIndex,
                          icon: i == _selectedIndex
                              ? _destinations[i].selectedIcon
                              : _destinations[i].icon,
                          badge: i == 0 && _todayRemaining > 0
                              ? '$_todayRemaining'
                              : null,
                          showDot: i == 2 && !_remindersEnabled,
                          onTap: () => _selectDestination(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _quickActionsButton(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 600;
        final screens = <Widget>[
          const HomeScreen(),
          ScheduleScreen(onSelectedDayChanged: _onWeekdaySelected),
          const SettingsScreen(),
        ];
        // Shared-axis motion: the screen fades in while sliding from the side
        // of the tab it came from, so moving left or right reads as direction.
        final screen = AnimatedBuilder(
          animation: _screenOpacity,
          builder: (context, child) => Opacity(
            opacity: _screenOpacity.value,
            child: Transform.translate(
              offset: Offset(_direction * 24 * (1 - _screenOpacity.value), 0),
              child: child,
            ),
          ),
          child: IndexedStack(index: _selectedIndex, children: screens),
        );

        return Scaffold(
          body: expanded
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SafeArea(
                      child: NavigationRail(
                        minWidth: 80,
                        selectedIndex: _selectedIndex,
                        labelType: NavigationRailLabelType.none,
                        leading: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/classcue_logo.png',
                              width: 40,
                              height: 40,
                              excludeFromSemantics: true,
                            ),
                          ),
                        ),
                        onDestinationSelected: _selectDestination,
                        destinations: [
                          for (var i = 0; i < _destinations.length; i++)
                            NavigationRailDestination(
                              icon: _tabIcon(i, selected: false),
                              selectedIcon: _tabIcon(i, selected: true),
                              label: Text(_destinations[i].label),
                            ),
                        ],
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppTheme.pageContentMaxWidth,
                          ),
                          child: screen,
                        ),
                      ),
                    ),
                  ],
                )
              : screen,
          floatingActionButton: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _quickActionMenuTransition(withBottomGap: true),
                    _quickActionsButton(),
                  ],
                )
              : _quickActionMenuTransition(),
          bottomNavigationBar: expanded ? null : _mobileNavigationBar(),
        );
      },
    );
  }

  void _selectDestination(int index) {
    if (_quickActionsExpanded) {
      setState(() => _quickActionsExpanded = false);
    }
    if (_switchingDestination) {
      _pendingDestination = index == _selectedIndex ? null : index;
      return;
    }
    if (index == _selectedIndex) return;
    if (MediaQuery.of(context).disableAnimations) {
      setState(() {
        _direction = index > _selectedIndex ? 1 : -1;
        _selectedIndex = index;
      });
      return;
    }

    _pendingDestination = index;
    _switchingDestination = true;
    unawaited(_transitionToPendingDestination());
  }

  Future<void> _transitionToPendingDestination() async {
    try {
      while (mounted && _pendingDestination != null) {
        await _screenTransitionController.reverse();
        if (!mounted) return;

        final destination = _pendingDestination;
        _pendingDestination = null;
        if (destination != null && destination != _selectedIndex) {
          setState(() {
            _direction = destination > _selectedIndex ? 1 : -1;
            _selectedIndex = destination;
          });
        }

        await _screenTransitionController.forward();
        if (!mounted) return;
      }
    } finally {
      _switchingDestination = false;
    }
  }
}
