import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'public_feedback_screen.dart';

/// Erkennt, ob die App im öffentlichen Feedback-Modus laufen soll.
///
/// Greift NUR im Web und NUR auf der Route `/feedback` (oder `/beschwerde`).
/// Wird im Bootstrap VOR der Provider-Kette/`_AuthGate` ausgewertet, damit die
/// öffentliche Seite vollständig vom internen App-Zustand isoliert bleibt
/// (kein Login, keine Mitarbeiter-Provider, kein Profil-Auflösen) — analog zu
/// `isPublicWishRoute()`.
bool isPublicFeedbackRoute() {
  if (!kIsWeb) {
    return false;
  }
  final segments =
      Uri.base.pathSegments.map((segment) => segment.toLowerCase());
  return segments.contains('feedback') || segments.contains('beschwerde');
}

/// Minimale, eigenständige App-Hülle für die öffentliche Feedback-Seite.
/// Bewusst ohne MultiProvider/Theme-Flip: nur Material-App + de_DE-Locale.
/// Hält den vom Nutzer gewählten Hell/Dunkel-Modus (Default: System).
class PublicFeedbackApp extends StatefulWidget {
  const PublicFeedbackApp({super.key, required this.firestoreService});

  final FirestoreService firestoreService;

  @override
  State<PublicFeedbackApp> createState() => _PublicFeedbackAppState();
}

class _PublicFeedbackAppState extends State<PublicFeedbackApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feedback',
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
      home: PublicFeedbackScreen(
        firestoreService: widget.firestoreService,
        onSelectThemeMode: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}
