import 'package:flutter/material.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_banner.dart';
import '../widgets/app_state_transition.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

enum _StatusKind { neutral, warning, error }

class _RemindersScreenState extends State<RemindersScreen> {
  bool _loading = true;
  bool _enabled = false;
  bool _exactAlarmsAvailable = true;
  String? _status;
  _StatusKind _statusKind = _StatusKind.neutral;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await ReminderService.instance.isEnabled;
      final exactAlarmsAvailable =
          await ReminderService.instance.exactAlarmsAvailable;
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _exactAlarmsAvailable = exactAlarmsAvailable;
          _loading = false;
          if (enabled && !exactAlarmsAvailable) {
            _statusKind = _StatusKind.warning;
            _status =
                'Reminders are on, but Android may delay them. Allow “Alarms & reminders” for on-time alerts.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusKind = _StatusKind.error;
          _status = 'Could not read reminder settings.';
        });
      }
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      if (value) {
        final granted = await ReminderService.instance.enable();
        if (!granted) {
          if (mounted) {
            setState(() {
              _loading = false;
              _enabled = false;
              _statusKind = _StatusKind.error;
              _status =
                  'Notification permission was not granted. Enable notifications in Android settings and try again.';
            });
          }
          return;
        }
        if (mounted) {
          final exactAlarmsAvailable =
              await ReminderService.instance.exactAlarmsAvailable;
          if (!mounted) return;
          setState(() {
            _loading = false;
            _enabled = true;
            _exactAlarmsAvailable = exactAlarmsAvailable;
            _statusKind = exactAlarmsAvailable
                ? _StatusKind.neutral
                : _StatusKind.warning;
            _status = exactAlarmsAvailable
                ? 'System notifications are enabled for your saved classes.'
                : 'Notifications are on, but Android may delay them. Allow “Alarms & reminders” in system settings for on-time alerts.';
          });
        }
      } else {
        await ReminderService.instance.disable();
        if (mounted) {
          setState(() {
            _loading = false;
            _enabled = false;
            _statusKind = _StatusKind.neutral;
            _status = 'Class reminders are disabled.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusKind = _StatusKind.error;
          _status =
              'Could not update reminders. Check notification permission and try again.';
        });
      }
    }
  }

  Future<void> _requestExactAlarmsAccess() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final allowed = await ReminderService.instance.requestExactAlarmsAccess();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _exactAlarmsAvailable = allowed;
        _statusKind = allowed ? _StatusKind.neutral : _StatusKind.warning;
        _status = allowed
            ? 'On-time class notifications are enabled.'
            : 'Exact alarms were not allowed. Android may delay notifications.';
      });
    } catch (error, stackTrace) {
      debugPrint('Exact alarm permission request failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusKind = _StatusKind.error;
        _status = 'Could not update the “Alarms & reminders” permission.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Class reminders')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.pageContentMaxWidth,
          ),
          child: ListView(
            padding: AppTheme.pagePadding,
            children: [
              Text('Leave on time', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Get a reminder 10 minutes before each class, every week, even when the app is closed.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.itemGap),
              Text(
                'Allow notifications and “Alarms & reminders” on your phone. Do Not Disturb still applies.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Material(
                color: scheme.surfaceContainer,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: SwitchListTile(
                  value: _enabled,
                  onChanged: _loading ? null : _toggle,
                  title: Text(
                    'Weekly class reminders',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: const Text('Uses your device time zone'),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              AppStateTransition(
                stateKey: ValueKey(_status ?? 'no-reminder-status'),
                child: _status == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: StatusBanner(
                          message: _status!,
                          kind: switch (_statusKind) {
                            _StatusKind.error => StatusKind.error,
                            _StatusKind.warning => StatusKind.warning,
                            _StatusKind.neutral => StatusKind.neutral,
                          },
                          onDismiss: () => setState(() => _status = null),
                        ),
                      ),
              ),
              if (_enabled && !_exactAlarmsAvailable) ...[
                const SizedBox(height: AppTheme.itemGap),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _requestExactAlarmsAccess,
                  icon: const Icon(Icons.alarm),
                  label: const Text('Allow Alarms & reminders'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
