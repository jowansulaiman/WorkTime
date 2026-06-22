import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'public_wish_screen.dart';

/// Erkennt, ob die App im öffentlichen Kundenwunsch-Modus laufen soll.
///
/// Greift NUR im Web und NUR auf der Route `/wunsch` (oder `/kundenwunsch`).
/// Wird im Bootstrap VOR der Provider-Kette/`_AuthGate` ausgewertet, damit die
/// öffentliche Seite vollständig vom internen App-Zustand isoliert bleibt
/// (kein Login, keine Mitarbeiter-Provider, kein Profil-Auflösen).
bool isPublicWishRoute() {
  if (!kIsWeb) {
    return false;
  }
  final segments =
      Uri.base.pathSegments.map((segment) => segment.toLowerCase());
  return segments.contains('wunsch') || segments.contains('kundenwunsch');
}

/// Minimale, eigenständige App-Hülle für die öffentliche Kundenwunsch-Seite.
/// Bewusst ohne MultiProvider/Theme-Flip: nur Material-App + de_DE-Locale.
/// Hält den vom Nutzer gewählten Hell/Dunkel-Modus (Default: System).
class PublicWishApp extends StatefulWidget {
  const PublicWishApp({super.key, required this.firestoreService});

  final FirestoreService firestoreService;

  @override
  State<PublicWishApp> createState() => _PublicWishAppState();
}

class _PublicWishAppState extends State<PublicWishApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kundenwunsch',
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
      home: PublicWishScreen(
        firestoreService: widget.firestoreService,
        onSelectThemeMode: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}
