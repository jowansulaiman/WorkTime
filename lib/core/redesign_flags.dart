import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/feature_flag_provider.dart';
import '../providers/theme_provider.dart';
import 'app_config.dart';

/// Aufloesung des Signal-Teal-Redesign-Flags (`redesign_v2`).
///
/// Legt einen lokalen Dev-Override (`bool.fromEnvironment('APP_REDESIGN_V2')`,
/// siehe [AppConfig.redesignV2Override]) ueber das org-/server-gesteuerte Flag
/// aus dem [FeatureFlagProvider]. Der Override gewinnt immer und macht die
/// V2-Optik offline / im `APP_DISABLE_AUTH`-Demo-Modus testbar, wo es keine
/// Remote-Config gibt.
///
/// Zwei Lese-Stellen (siehe Rollout-Plan): die Theme-Wahl in `main.dart`
/// (`AppTheme.resolveLight/Dark(useV2: …)`) und ein duenner Chooser je Screen
/// am Einstiegspunkt (`RedesignFlags.isOnRead(context) ? XV2() : X()`). Solange
/// kein Screen das Flag liest, bleibt die App in V1 — diese Klasse ist die
/// einzige Quelle der Wahrheit fuer „V1 oder V2".
abstract final class RedesignFlags {
  RedesignFlags._();

  /// Schluessel des Feature-Flags in der org-seitigen Remote-Config
  /// (`organizations/{orgId}/config/appFlags` → `featureFlags.redesign_v2`).
  static const String flagKey = 'redesign_v2';

  /// Lokaler Dev-/Test-Override. Gewinnt immer.
  static bool get devOverride => AppConfig.redesignV2Override;

  /// Reine Wert-Logik ohne [BuildContext] — direkt unit-testbar. Prioritaet:
  /// [runtimeOverride] (Laufzeit-Schalter) → Dev-Define → [serverFlag] (Wert aus
  /// `FeatureFlagProvider.isEnabled(flagKey, fallback: false)`).
  static bool resolve({required bool serverFlag, bool? runtimeOverride}) {
    if (runtimeOverride != null) {
      return runtimeOverride;
    }
    return devOverride || serverFlag;
  }

  /// Liest das Flag mit Subscription (`context.watch`) — ein Wechsel (frisch
  /// geladene Remote-Config ODER der Laufzeit-Schalter aus [ThemeProvider])
  /// loest ein Rebuild aus. Prioritaet: Laufzeit-Override → Dev-Define →
  /// org-Flag. Im Offline-/Demo-Modus liefert der FeatureFlagProvider nichts
  /// (fallback `false`) ⇒ deterministisch V1, ausser Override/Dev-Define.
  static bool isOn(BuildContext context) {
    final override = context.watch<ThemeProvider>().redesignV2Override;
    if (override != null) {
      return override;
    }
    if (devOverride) {
      return true;
    }
    final flags = context.watch<FeatureFlagProvider>();
    return flags.isEnabled(flagKey, fallback: false);
  }

  /// Wie [isOn], aber ohne Subscription (`context.read`) — fuer einmalige
  /// Entscheidungen am Screen-Einstiegspunkt, die nicht live umschalten muessen.
  static bool isOnRead(BuildContext context) {
    final override = context.read<ThemeProvider>().redesignV2Override;
    if (override != null) {
      return override;
    }
    if (devOverride) {
      return true;
    }
    return context
        .read<FeatureFlagProvider>()
        .isEnabled(flagKey, fallback: false);
  }
}
