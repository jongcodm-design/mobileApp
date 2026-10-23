import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/class_item.dart';

/// Keeps the Android launcher widget in sync with the app's local schedule.
class NextClassWidgetService {
  NextClassWidgetService._();

  static const MethodChannel _channel = MethodChannel(
    'classcue/next_class_widget',
  );

  static Future<void> sync(List<ClassItem> classes) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _channel.invokeMethod<void>('updateSchedule', {
        'scheduleJson': jsonEncode(
          classes.map((item) => item.toMap()).toList(),
        ),
      });
    } catch (error, stackTrace) {
      // Widget sync must never block schedule edits or imports.
      debugPrint('Next-class widget sync failed: $error\n$stackTrace');
    }
  }
}
