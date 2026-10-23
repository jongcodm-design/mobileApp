import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact bottom tab matching the component reference's 52 × 28 icon pill.
class BottomNavigationItem extends StatelessWidget {
  const BottomNavigationItem({
    super.key,
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.badge,
    this.showDot = false,
  });

  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 52,
          height: 48,
          child: Center(
            child: SizedBox(
              width: 52,
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: AppTheme.motionDuration(
                      context,
                      AppTheme.motionFast,
                    ),
                    curve: AppTheme.motionEaseOut,
                    width: 52,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 22, color: foreground),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badge!,
                          style: TextStyle(
                            color: scheme.onError,
                            fontSize: 12,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (showDot)
                    Positioned(
                      top: 0,
                      right: 4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
