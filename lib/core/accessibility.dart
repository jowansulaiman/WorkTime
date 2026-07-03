import 'package:flutter/widgets.dart';

import '../theme/theme_extensions.dart';

/// Accessibility-Helfer rund um MediaQuery (no-textscaler-reduce-motion).
extension AccessibilityContextX on BuildContext {
  /// True, wenn das System „Bewegung reduzieren" verlangt
  /// (iOS Reduce Motion / Android Remove Animations). Animationen sollten dann
  /// auf [Duration.zero] gekürzt werden.
  bool get prefersReducedMotion =>
      MediaQuery.maybeOf(this)?.disableAnimations ?? false;

  /// Animationsdauer, die „Bewegung reduzieren" respektiert.
  ///
  /// Delegiert an die **kanonische** Reduce-Motion-API [AppMotion.resolve]
  /// (Plan-Entscheidung E3 — genau eine Implementierung). Neue Aufrufer nutzen
  /// bevorzugt direkt `AppMotion.resolve(context, normal)`.
  Duration motionDuration(Duration normal) => AppMotion.resolve(this, normal);
}

/// Globale Obergrenze der Textskalierung (Plan-Entscheidung E1 „gestuft"):
/// Lese-lastige Screens dürfen bis hierher skalieren. **Dichte** Raster
/// (Admin-Tabellen, Kiosk-Board, Charts, Planer-Raster) klemmen lokal tiefer
/// auf [kDenseContentMaxTextScaleFactor] via [DenseContentTextScale].
/// Unterhalb der Grenze wird die System-Skalierung unverändert respektiert.
const double kMaxTextScaleFactor = 2.0;

/// Tiefere Obergrenze für dichte Inhalte, die bei sehr großer Schrift
/// überlaufen würden. Wird nur über [DenseContentTextScale]-Teilbäume wirksam;
/// die App bleibt global bei [kMaxTextScaleFactor].
const double kDenseContentMaxTextScaleFactor = 1.5;

/// Klemmt den oberen Rand der [TextScaler] auf [kMaxTextScaleFactor], lässt
/// kleinere/normale Skalierung aber unangetastet.
TextScaler clampTextScaler(TextScaler scaler) =>
    scaler.clamp(maxScaleFactor: kMaxTextScaleFactor);

/// Klemmt die Textskalierung innerhalb eines **dichten** Teilbaums auf
/// [kDenseContentMaxTextScaleFactor] (1,5), während die App global bis
/// [kMaxTextScaleFactor] (2,0) skaliert (gestufte Dynamic-Type-Leiter, E1).
///
/// Nur um wirklich dichte Inhalte (Tabellen/Raster/Charts/Boards) legen, nie um
/// Lese-Screens — diese sollen die volle Skalierung erhalten. Übernimmt alle
/// übrigen MediaQuery-Werte unverändert.
class DenseContentTextScale extends StatelessWidget {
  const DenseContentTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: mediaQuery.textScaler
            .clamp(maxScaleFactor: kDenseContentMaxTextScaleFactor),
      ),
      child: child,
    );
  }
}
