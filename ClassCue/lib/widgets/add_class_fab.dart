import 'package:flutter/material.dart';

/// The single "Add class" action for list screens.
///
/// Screens show this button only when they are not already showing their own
/// empty-state Add button, so the two can never appear together. On narrow
/// phones it collapses to an icon so it does not compete with the nav bar.
Widget addClassFab(
  BuildContext context, {
  required String heroTag,
  required VoidCallback onPressed,
}) {
  final compact = MediaQuery.sizeOf(context).width < 380;
  if (compact) {
    return FloatingActionButton(
      heroTag: heroTag,
      tooltip: 'Add class',
      onPressed: onPressed,
      child: const Icon(Icons.add),
    );
  }
  return FloatingActionButton.extended(
    heroTag: heroTag,
    tooltip: 'Add class',
    onPressed: onPressed,
    icon: const Icon(Icons.add),
    label: const Text('Add class'),
  );
}
