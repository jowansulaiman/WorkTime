import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../theme/app_theme.dart';
import 'public_legal_screen.dart';

/// Pfad-Segmente, die auf die Impressum- bzw. Datenschutz-Route matchen.
/// Als Konstanten gehalten, damit die reine Matching-Logik unten testbar ist.
const Set<String> _kImpressumSegments = {'impressum'};
const Set<String> _kDatenschutzSegments = {
  'datenschutz',
  'datenschutzerklaerung',
  'datenschutzerklärung',
  'privacy',
};

/// Reine, `kIsWeb`-unabhängige Matching-Helfer (case-insensitiv) — von den
/// Route-Erkennern UND von Unit-Tests genutzt, damit ein vertippter/entfernter
/// Alias oder eine Case-Regression auffällt.
@visibleForTesting
bool matchesImpressumSegments(Iterable<String> segments) =>
    segments.any((s) => _kImpressumSegments.contains(s.toLowerCase()));

@visibleForTesting
bool matchesDatenschutzSegments(Iterable<String> segments) =>
    segments.any((s) => _kDatenschutzSegments.contains(s.toLowerCase()));

/// Erkennt die eigenständige Web-Route `/impressum`.
///
/// Wie [isPublicWishRoute] nur im Web und VOR der Provider-Kette/`_AuthGate`
/// ausgewertet — die Rechtsseite läuft als vollständig isolierte, login-freie
/// Hülle (kein Firebase nötig, reine Statik).
bool isPublicImpressumRoute() =>
    kIsWeb && matchesImpressumSegments(Uri.base.pathSegments);

/// Erkennt die eigenständige Web-Route `/datenschutz`
/// (auch `/datenschutzerklaerung`, `/datenschutzerklärung`, `/privacy`).
bool isPublicDatenschutzRoute() =>
    kIsWeb && matchesDatenschutzSegments(Uri.base.pathSegments);

/// Minimale, eigenständige App-Hülle für die rechtlichen Pflichtseiten
/// (Impressum, Datenschutz). Spiegelt [PublicWishApp]/[PublicFeedbackApp]: nur
/// Material-App + de_DE-Locale + V2-Theme, hält den Hell/Dunkel-Modus. Braucht
/// KEIN [FirestoreService] — die Seiten sind reine Statik.
class PublicLegalApp extends StatefulWidget {
  const PublicLegalApp({super.key, required this.page});

  final PublicLegalPage page;

  @override
  State<PublicLegalApp> createState() => _PublicLegalAppState();
}

class _PublicLegalAppState extends State<PublicLegalApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.page.title,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightV2,
      darkTheme: AppTheme.darkV2,
      themeMode: _themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de', 'DE'),
        Locale('en', 'US'),
      ],
      locale: const Locale('de', 'DE'),
      home: PublicLegalScreen(
        page: widget.page,
        onSelectThemeMode: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}
