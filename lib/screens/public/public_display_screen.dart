import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_config.dart';
import '../../core/local_demo_operations_data.dart';
import '../../models/signage_display.dart';
import 'signage_token_store.dart';

/// Öffentlicher Vollbild-Werbe-Player für einen Store-Fernseher. Liest die
/// login-frei lesbare Projektion aus `publicDisplays/{token}` als Live-Stream
/// und spielt die Werbebilder in Endlosschleife ab (Standzeit je Bild aus der
/// Projektion). Ändert der Admin die Playlist, aktualisiert sich der Fernseher
/// von selbst (Firestore-Snapshot).
class PublicDisplayScreen extends StatefulWidget {
  const PublicDisplayScreen({super.key, required this.token});

  /// Bearer-Token des Displays (aus der URL). Null ⇒ freundlicher Hinweis.
  final String? token;

  @override
  State<PublicDisplayScreen> createState() => _PublicDisplayScreenState();
}

class _PublicDisplayScreenState extends State<PublicDisplayScreen> {
  Stream<PublicDisplayData?>? _stream;

  /// Aktiver Token (aus URL oder gemerkt). Null + [_resolving]==false ⇒ Pairing.
  String? _token;

  /// Solange der gemerkte Token aus dem Speicher geladen wird.
  bool _resolving = true;

  PublicDisplayData? _data;
  int _index = 0;
  Timer? _timer;

  // Signatur der zuletzt verarbeiteten Projektion (Playlist + Einstellungen).
  // Verhindert, dass ein bloßer Rebuild (z.B. durch [_advance]) den Slide-Timer
  // zurücksetzt — der Timer wird NUR bei echter Änderung neu gestartet.
  String _signature = '__init__';

  @override
  void initState() {
    super.initState();
    // Dauerbetrieb am Fernseher: Bildschirm wach halten (best-effort; auf Web
    // greift die Screen Wake Lock API, sofern der Browser sie unterstützt).
    WakelockPlus.enable().catchError((_) {});

    final urlToken = widget.token;
    if (urlToken != null && urlToken.isNotEmpty) {
      // Token aus der URL → sofort starten UND für den nächsten Neustart merken,
      // damit `…/anzeige` (ohne Code) das Display danach automatisch wieder
      // aufnimmt.
      _resolving = false;
      _activate(urlToken);
      SignageTokenStore.save(urlToken);
    } else {
      // Kein Token in der URL → gemerkten Token laden (Auto-Start nach Neustart).
      _resolveStoredToken();
    }
  }

  Future<void> _resolveStoredToken() async {
    final stored = await SignageTokenStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _resolving = false;
      if (stored != null) {
        _activate(stored);
      }
    });
  }

  /// Setzt den aktiven Token und öffnet den Firestore-Stream (falls Firebase da).
  void _activate(String token) {
    _token = token;
    if (Firebase.apps.isNotEmpty) {
      _stream = FirebaseFirestore.instance
          .collection('publicDisplays')
          .doc(token)
          .snapshots()
          .map(
            (doc) =>
                doc.exists && doc.data() != null
                    ? PublicDisplayData.fromMap(doc.data()!)
                    : null,
          );
      return;
    }
    if (AppConfig.disableAuthentication) {
      // Im lokalen Demo-Modus bleibt der Player fuer die stabilen Demo-Codes
      // testbar (inkl. pausierter/leerer Playlist und unbekanntem Code).
      _stream = Stream<PublicDisplayData?>.value(
        LocalDemoOperationsData.publicDisplayDataForToken(
          orgId: AppConfig.defaultOrganizationId,
          token: token,
        ),
      );
    }
  }

  /// Aus der Pairing-Seite: Code speichern, merken und Werbung starten.
  void _pair(String code) {
    final token = code.trim();
    if (token.isEmpty) {
      return;
    }
    SignageTokenStore.save(token);
    setState(() {
      _signature = '__init__';
      _data = null;
      _index = 0;
      _activate(token);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _onData(PublicDisplayData? data) {
    final signature =
        data == null
            ? ''
            : '${data.isActive}|${data.fit.value}|'
                '${data.slides.map((s) => '${s.url}@${s.seconds}').join(',')}';
    final changed = signature != _signature;
    _data = data;
    _signature = signature;
    if (!changed) {
      // Nur ein Rebuild (z.B. nach [_advance]) — Timer NICHT anfassen.
      return;
    }
    final slideCount = data?.slides.length ?? 0;
    if (_index >= slideCount) {
      _index = 0;
    }
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    final slides = _data?.slides ?? const <PublicDisplaySlide>[];
    if (slides.length < 2) {
      // 0 oder 1 Bild: kein Wechsel nötig.
      return;
    }
    final seconds = slides[_index.clamp(0, slides.length - 1)].seconds;
    _timer = Timer(Duration(seconds: seconds < 3 ? 3 : seconds), _advance);
    _precacheNext();
  }

  void _advance() {
    final slides = _data?.slides ?? const <PublicDisplaySlide>[];
    if (slides.isEmpty) {
      return;
    }
    setState(() {
      _index = (_index + 1) % slides.length;
    });
    _restartTimer();
  }

  void _precacheNext() {
    final slides = _data?.slides ?? const <PublicDisplaySlide>[];
    if (slides.length < 2) {
      return;
    }
    final next = slides[(_index + 1) % slides.length];
    // Nächstes Bild vorladen, damit der Wechsel nicht flackert.
    precacheImage(NetworkImage(next.url), context).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    // Gemerkten Token laden (kurz).
    if (_resolving) {
      return const _MessageScreen(
        icon: null,
        title: 'Anzeige wird gestartet …',
        message: '',
        showLoader: true,
      );
    }

    // Kein Token (weder in der URL noch gemerkt) → einmalige Pairing-Seite.
    // Nach dem Koppeln merkt sich das Gerät den Code und startet künftig selbst.
    if (_token == null) {
      return _PairingView(onSubmit: _pair);
    }

    if (_stream == null) {
      return const _MessageScreen(
        icon: Icons.tv_off_outlined,
        title: 'Nicht verbunden',
        message:
            'Diese Seite ist hier nicht mit dem Backend verbunden. Sie '
            'funktioniert nur im echten Web-Build mit Firebase.',
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<PublicDisplayData?>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _data == null) {
            return const _MessageScreen(
              icon: null,
              title: 'Anzeige wird geladen …',
              message: '',
              showLoader: true,
            );
          }

          if (snapshot.hasError) {
            return const _MessageScreen(
              icon: Icons.error_outline,
              title: 'Anzeige nicht verfügbar',
              message: 'Die Werbung konnte nicht geladen werden.',
            );
          }

          final data = snapshot.data;

          // Neuen Stand übernehmen (Playlist-Änderung) — nach dem Build, damit
          // setState/Timer-Restart nicht mitten im Build läuft.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _onData(data);
            }
          });

          if (data == null) {
            return const _MessageScreen(
              icon: Icons.tv_off_outlined,
              title: 'Display nicht gefunden',
              message: 'Für diesen Code ist keine Anzeige hinterlegt.',
            );
          }

          if (!data.isActive || data.slides.isEmpty) {
            return _MessageScreen(
              icon: Icons.photo_library_outlined,
              title: data.name.isEmpty ? 'Anzeige' : data.name,
              message:
                  !data.isActive
                      ? 'Diese Anzeige ist derzeit pausiert.'
                      : 'Es ist noch keine Werbung hinterlegt.',
            );
          }

          final slide = data.slides[_index.clamp(0, data.slides.length - 1)];
          final fit =
              data.fit == SignageFit.contain ? BoxFit.contain : BoxFit.cover;

          return SizedBox.expand(
            child: AnimatedSwitcher(
              // Harter Schnitt ≈ 1ms; sonst 700ms weicher Übergang.
              duration:
                  data.transition == SignageTransition.none
                      ? const Duration(milliseconds: 1)
                      : const Duration(milliseconds: 700),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder:
                  (child, animation) =>
                      _buildTransition(data.transition, child, animation),
              child: _buildSlide(slide, fit, data.transition),
            ),
          );
        },
      ),
    );
  }

  /// Baut das aktuell sichtbare Bild. Bei Ken-Burns wird es während der Standzeit
  /// langsam herangezoomt (Transform.scale über die Slide-Dauer). Der eindeutige
  /// Key (Index + URL) sorgt dafür, dass der [AnimatedSwitcher] jeden Wechsel
  /// animiert — auch wenn zufällig zweimal dieselbe URL folgt.
  Widget _buildSlide(
    PublicDisplaySlide slide,
    BoxFit fit,
    SignageTransition transition,
  ) {
    final image = Image.network(
      slide.url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder:
          (context, error, stackTrace) => const _MessageScreen(
            icon: Icons.broken_image_outlined,
            title: 'Bild nicht ladbar',
            message: '',
          ),
    );

    if (transition == SignageTransition.kenBurns) {
      final seconds = slide.seconds < 3 ? 3 : slide.seconds;
      return TweenAnimationBuilder<double>(
        key: ValueKey<String>('kb:$_index:${slide.url}'),
        tween: Tween<double>(begin: 1.0, end: 1.08),
        duration: Duration(seconds: seconds),
        curve: Curves.easeOut,
        builder:
            (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
        child: image,
      );
    }

    return KeyedSubtree(
      key: ValueKey<String>('$_index:${slide.url}'),
      child: image,
    );
  }

  /// Übergangs-Animation zwischen zwei Bildern (auf beide — ein- und ausgehendes
  /// — Kind angewandt; der [AnimatedSwitcher] fährt das ausgehende rückwärts).
  Widget _buildTransition(
    SignageTransition transition,
    Widget child,
    Animation<double> animation,
  ) {
    switch (transition) {
      case SignageTransition.slide:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      case SignageTransition.zoom:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
            child: child,
          ),
        );
      case SignageTransition.none:
        return child; // kein Effekt (Dauer ~1ms → harter Schnitt)
      case SignageTransition.fade:
      case SignageTransition.kenBurns:
        return FadeTransition(opacity: animation, child: child);
    }
  }
}

/// Ruhiger Vollbild-Hinweis (kein Bild / Ladezustand / Fehler) für den Player.
class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.icon,
    required this.title,
    required this.message,
    this.showLoader = false,
  });

  final IconData? icon;
  final String title;
  final String message;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLoader)
                const CircularProgressIndicator(color: Colors.white24)
              else if (icon != null)
                Icon(icon, size: 72, color: Colors.white24),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Einmalige Kopplungs-Seite: Der Bildschirm wird über die feste Adresse
/// `…/anzeige` (ohne Code) geöffnet, hier gibt das Personal EINMAL den
/// Display-Code ein. Danach merkt sich das Gerät den Code (localStorage) und
/// startet die Werbung bei jedem Neustart automatisch — der Code muss nie
/// wieder eingegeben werden.
class _PairingView extends StatefulWidget {
  const _PairingView({required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<_PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<_PairingView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isNotEmpty) {
      widget.onSubmit(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cast_outlined,
                  size: 64,
                  color: Colors.white24,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Display koppeln',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Gib den Anzeige-Code aus der Verwaltung ein '
                  '(„Fernseh-Link kopieren" → der Teil hinter /anzeige/). '
                  'Dieser Bildschirm merkt ihn sich und startet die Werbung '
                  'ab dann automatisch.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 15),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Anzeige-Code',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Werbung starten'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
