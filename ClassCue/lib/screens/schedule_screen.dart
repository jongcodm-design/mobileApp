import 'dart:async';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/class_item.dart';
import '../routes/app_routes.dart';
import '../widgets/app_state_transition.dart';
import '../widgets/class_delete_undo.dart';
import '../widgets/error_view.dart';
import '../widgets/week_agenda_view.dart';

/// Screen coordinating the student's weekly schedule.
///
/// Displays the single-day agenda view with a week strip, sticky day header,
/// time-ordered class cards, and campus break dividers.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.onSelectedDayChanged});

  final ValueChanged<int>? onSelectedDayChanged;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with WidgetsBindingObserver {
  final _db = DatabaseHelper.instance;
  List<ClassItem> _classes = [];
  bool _loading = true;
  String? _error;
  int _selectedDay = DateTime.now().weekday;
  int _loadVersion = 0;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _db.addListener(_onScheduleChanged);
    _load();
    _startMinuteTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _db.removeListener(_onScheduleChanged);
    _minuteTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {});
        _load();
      }
    }
  }

  void _startMinuteTimer() {
    _minuteTimer?.cancel();
    final now = DateTime.now();
    final untilNextMinute = const Duration(minutes: 1) -
        Duration(seconds: now.second, milliseconds: now.millisecond);
    _minuteTimer = Timer(untilNextMinute, () {
      if (!mounted) return;
      if (!_loading && _error == null) setState(() {});
      _startMinuteTimer();
    });
  }

  void _onScheduleChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final classes = await _db.getAll();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _classes = classes;
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Schedule load failed: $error\n$stackTrace');
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load your classes. Your saved data wasn\'t changed.';
      });
    }
  }

  void _retry() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _open(ClassItem item) async {
    await Navigator.pushNamed(context, AppRoutes.classForm, arguments: item);
    _load();
  }

  Future<void> _openAddClassForDay(int day) async {
    await Navigator.pushNamed(context, AppRoutes.classForm, arguments: day);
    _load();
  }

  Future<void> _deleteClass(ClassItem item) async {
    await deleteClassWithUndo(context, item);
  }

  void _selectDay(int day) {
    setState(() => _selectedDay = day);
    widget.onSelectedDayChanged?.call(day);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = now.weekday;
    final nowMinutes = now.hour * 60 + now.minute;
    final classesByDay = <int, List<ClassItem>>{
      for (var day = 1; day <= 7; day++)
        day: _classes.where((item) => item.day == day).toList()
          ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes)),
    };

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Weekly schedule'),
      ),
      body: AppStateTransition(
        stateKey: ValueKey(
          _loading
              ? 'loading'
              : _error != null
                  ? 'error'
                  : 'schedule',
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _retry)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: WeekAgendaView(
                      classesByDay: classesByDay,
                      allClassesEmpty: _classes.isEmpty,
                      today: today,
                      nowMinutes: nowMinutes,
                      selectedDay: _selectedDay,
                      onSelectDay: _selectDay,
                      onEdit: (item) => _open(item),
                      onLongPress: _deleteClass,
                      onAddClassForDay: _openAddClassForDay,
                    ),
                  ),
      ),
    );
  }
}
