import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/class_item.dart';
import '../services/reminder_service.dart';
import 'app_notification.dart';

/// Deletes a single class immediately and offers a five-second undo action.
/// Undo uses the app-level messenger, so it survives route changes.
Future<bool> deleteClassWithUndo(BuildContext context, ClassItem item) async {
  final id = item.id;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (id == null || messenger == null) return false;
  final scheme = Theme.of(context).colorScheme;

  try {
    final deleted = await DatabaseHelper.instance.delete(id);
    if (deleted == 0) throw StateError('Class was not found.');
  } catch (error, stackTrace) {
    debugPrint('Class delete failed: $error\n$stackTrace');
    showAppNotificationOnMessenger(
      messenger,
      scheme,
      'Could not delete the class. Please try again.',
      kind: AppNotificationKind.error,
    );
    return false;
  }

  try {
    await ReminderService.instance.sync();
  } catch (error, stackTrace) {
    debugPrint('Reminder sync after delete failed: $error\n$stackTrace');
  }

  showAppNotificationOnMessenger(
    messenger,
    scheme,
    'Class deleted',
    kind: AppNotificationKind.info,
    duration: const Duration(seconds: 5),
    actionLabel: 'Undo',
    onAction: () async {
      try {
        await DatabaseHelper.instance.restoreDeleted(item);
        try {
          await ReminderService.instance.sync();
        } catch (error, stackTrace) {
          debugPrint('Reminder sync after restore failed: $error\n$stackTrace');
        }
        showAppNotificationOnMessenger(
          messenger,
          scheme,
          'Class restored',
          kind: AppNotificationKind.success,
        );
      } catch (error, stackTrace) {
        debugPrint('Class restore failed: $error\n$stackTrace');
        showAppNotificationOnMessenger(
          messenger,
          scheme,
          "Couldn't restore. Add it again.",
          kind: AppNotificationKind.error,
        );
      }
    },
  );
  return true;
}
