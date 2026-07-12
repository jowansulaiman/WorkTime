import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'public_display_screen.dart';

/// Erkennt, ob die App als öffentlicher **Werbe-Player** (Store-Fernseher)
/// laufen soll.
///
/// Greift NUR im Web und NUR auf der Route `/anzeige/<token>` (oder
/// `?d=<token>`). Wird im Bootstrap VOR der Provider-Kette ausgewertet, damit
/// der Fernseher vollständig vom internen App-Zustand isoliert bleibt (kein
/// Login, keine Mitarbeiter-Provider) — analog `/wunsch` und `/feedback`.
bool isPublicDisplayRoute() {
  if (!kIsWeb) {
    return false;
  }
  final segments =
      Uri.base.pathSegments.map((segment) => segment.toLowerCase());
  return segments.contains('anzeige');
}

/// Liest den Display-Token aus der aktuellen URL: bevorzugt das Pfadsegment
/// nach `/anzeige/…`, sonst der Query-Parameter `?d=`/`?token=`. Der Token wirkt
/// wie ein Schlüssel (Bearer-Secret) auf genau ein Display.
String? displayTokenFromUri() {
  final segments = Uri.base.pathSegments;
  final index =
      segments.indexWhere((segment) => segment.toLowerCase() == 'anzeige');
  if (index >= 0 && index + 1 < segments.length) {
    final token = segments[index + 1].trim();
    if (token.isNotEmpty) {
      return token;
    }
  }
  final query = Uri.base.queryParameters['d'] ??
      Uri.base.queryParameters['token'];
  if (query != null && query.trim().isNotEmpty) {
    return query.trim();
  }
  return null;
}

/// Minimale, eigenständige App-Hülle für den öffentlichen Werbe-Player.
/// Bewusst dunkel (Dauerbetrieb am Fernseher) und ohne Provider-Kette.
class PublicDisplayApp extends StatelessWidget {
  const PublicDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anzeige',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
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
      home: PublicDisplayScreen(token: displayTokenFromUri()),
    );
  }
}
