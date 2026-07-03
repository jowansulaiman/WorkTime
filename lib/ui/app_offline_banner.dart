import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import 'app_status.dart';

/// Dünnes Offline-Banner (Anf. 13 „Offline-Funktionalität") — **präsentational**
/// ohne Provider-Kopplung: der Aufrufer (Shell) reicht [offline] aus dem
/// `ConnectivityStatusProvider` ein.
///
/// Blendet sich mit Höhe 0 → Inhalt animiert ein/aus (Reduce-Motion via
/// [AppMotion.resolve] → sofort), reserviert im Online-Zustand keinen Platz und
/// meldet sich als Screenreader-`liveRegion`. Warnton kommt aus [AppStatusBanner]
/// (→ `appColors.warning`, nie hardcodiert).
class AppOfflineBanner extends StatelessWidget {
  const AppOfflineBanner({
    super.key,
    required this.offline,
    this.message =
        'Offline – Änderungen werden lokal gespeichert und später synchronisiert.',
  });

  final bool offline;
  final String message;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return AnimatedSize(
      duration: AppMotion.resolve(context, context.motion.short),
      curve: context.motion.standard,
      alignment: Alignment.topCenter,
      child: offline
          ? Padding(
              padding:
                  EdgeInsets.fromLTRB(spacing.md, spacing.sm, spacing.md, 0),
              child: Semantics(
                liveRegion: true,
                child: AppStatusBanner(
                  icon: Icons.cloud_off_rounded,
                  message: message,
                  tone: AppStatusTone.warning,
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
