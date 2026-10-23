import 'package:flutter/material.dart';

import '../features/schedule_import/import_route_cache.dart';
import '../routes/app_routes.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/component_kit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _remindersEnabled;

  @override
  void initState() {
    super.initState();
    ReminderService.instance.addListener(_onReminderSettingsChanged);
    _loadReminderState();
  }

  @override
  void dispose() {
    ReminderService.instance.removeListener(_onReminderSettingsChanged);
    super.dispose();
  }

  void _onReminderSettingsChanged() => _loadReminderState();

  Future<void> _loadReminderState() async {
    final enabled = await ReminderService.instance.isEnabled;
    if (!mounted || enabled == _remindersEnabled) return;
    setState(() => _remindersEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.pageContentMaxWidth,
          ),
          child: ListView(
            padding: AppTheme.pagePadding,
            children: [
              _SettingsGroup(
                title: 'Schedule',
                rows: [
                  const _SettingsRowData(
                    icon: Icons.upload_file_outlined,
                    title: 'Import a timetable',
                    subtitle: 'Add classes from a photo or PDF',
                    route: AppRoutes.importSchedule,
                  ),
                  _SettingsRowData(
                    icon: Icons.notifications_active_outlined,
                    title: 'Class reminders',
                    subtitle: _remindersEnabled == null
                        ? 'Checking reminder status…'
                        : _remindersEnabled!
                        ? 'Reminders are on. You’ll get alerts before class.'
                        : 'Reminders are off. Turn on to get alerts.',
                    route: AppRoutes.reminders,
                  ),
                  const _SettingsRowData(
                    icon: Icons.backup_outlined,
                    title: 'Backup and restore',
                    subtitle: 'Save or restore your classes',
                    route: AppRoutes.backup,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SettingsGroup(
                title: 'Help',
                rows: [
                  _SettingsRowData(
                    icon: Icons.menu_book_outlined,
                    title: 'How ClassCue works',
                    subtitle: 'Features and how to start',
                    route: AppRoutes.onboarding,
                    arguments: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRowData {
  const _SettingsRowData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.arguments,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Object? arguments;
}

/// A grouped panel of rows separated by hairlines. One surface per group,
/// instead of one card per row.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.rows});

  final String title;
  final List<_SettingsRowData> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: SectionHeader(title: title),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                SettingsRow(
                  compact: true,
                  icon: rows[i].icon,
                  title: rows[i].title,
                  subtitle: rows[i].subtitle,
                  onTap: () {
                    if (rows[i].route == AppRoutes.importSchedule) {
                      openOrResumeImport(context);
                    } else {
                      Navigator.pushNamed(
                        context,
                        rows[i].route,
                        arguments: rows[i].arguments,
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
