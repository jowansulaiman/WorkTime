import 'package:flutter/widgets.dart';

/// Accessibility-Helfer rund um MediaQuery (no-textscaler-reduce-motion).
extension AccessibilityContextX on BuildContext {
  /// True, wenn das System „Bewegung reduzieren" verlangt
  /// (iOS Reduce Motion / Android Remove Animations). Animationen sollten dann
  /// auf [Duration.zero] gekürzt werden.
  bool get prefersReducedMotion =>
      MediaQuery.maybeOf(this)?.disableAnimations ?? false;

  /// Animationsdauer, die „Bewegung reduzieren" respektiert.
  Duration motionDuration(Duration normal) =>
      prefersReducedMotion ? Duration.zero : normal;
}

/// Obergrenze für die Textskalierung. Schützt Komponenten mit fixen Höhen
/// (NavigationBar, Slide-to-Clock) vor dem Überlaufen bei sehr großer
/// System-Schriftgröße, bis diese Komponenten flexibel mitwachsen.
/// Unterhalb der Grenze wird die System-Skalierung unverändert respektiert.
const double kMaxTextScaleFactor = 1.5;

/// Klemmt den oberen Rand der [TextScaler] auf [kMaxTextScaleFactor], lässt
/// kleinere/normale Skalierung aber unangetastet.
TextScaler clampTextScaler(TextScaler scaler) =>
    scaler.clamp(maxScaleFactor: kMaxTextScaleFactor);
