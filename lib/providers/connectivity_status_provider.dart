import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// Dreiwertiger Konnektivitäts-Zustand (ZV-1.1, Skill 21):
/// - [online] — Interface vorhanden **und** (falls eine Reachability-Probe
///   injiziert ist) Backend erreichbar.
/// - [offline] — kein Netzwerk-Interface.
/// - [backendUnreachable] — Interface vorhanden, aber die Probe scheitert
///   (Captive-Portal/LAN-ohne-Uplink) — der klassische „verbunden, aber nichts
///   geht"-Fall.
enum ConnectivityStatus { online, offline, backendUnreachable }

/// Online-/Offline-Status des Geräts (Anf. 13 „Offline-Funktionalität";
/// ZV-1.1-Härtung).
///
/// Liest den Interface-Status von `connectivity_plus` und — sofern eine
/// [ConnectivityStatusProvider.new.reachabilityProbe] injiziert ist — eine
/// leichtgewichtige Reachability-Probe gegen den eigenen Backend-Endpunkt. Das
/// Ergebnis ist ein dreiwertiges [ConnectivityStatus]-Enum; `isOnline`/`isOffline`
/// bleiben abwärtskompatibel (Banner/Home lesen sie weiter via `context.select`).
///
/// Statuswechsel werden um [debounce] entprellt (Banner-Flackern, Skill 21);
/// der **Initial**-Check wirkt sofort, damit die UI schnell einen Zustand hat.
/// Bei `AppLifecycleState.resumed` wird via [recheck] erneut geprüft.
///
/// Von Auth/Storage **unabhängig** → früh in der Provider-Kette registriert.
/// Stream/Check/Probe sind injizierbar (Tests ohne Platform-Channel). Startwert
/// ist optimistisch **online**, damit die UI vor dem ersten Ergebnis nichts sperrt.
class ConnectivityStatusProvider extends ChangeNotifier
    with WidgetsBindingObserver {
  ConnectivityStatusProvider({
    Stream<List<ConnectivityResult>>? changes,
    Future<List<ConnectivityResult>> Function()? check,
    Future<bool> Function()? reachabilityProbe,
    Duration debounce = const Duration(seconds: 2),
    bool observeLifecycle = true,
  })  : _changes = changes ?? Connectivity().onConnectivityChanged,
        _check = check ?? Connectivity().checkConnectivity,
        _reachabilityProbe = reachabilityProbe,
        _debounce = debounce {
    if (observeLifecycle) {
      // Kann in reinen Unit-Tests ohne initialisiertes Binding werfen — dann
      // still überspringen (Resume-Recheck ist nur eine Optimierung).
      try {
        WidgetsBinding.instance.addObserver(this);
        _lifecycleObserved = true;
      } catch (_) {
        _lifecycleObserved = false;
      }
    }
    _init();
  }

  final Stream<List<ConnectivityResult>> _changes;
  final Future<List<ConnectivityResult>> Function() _check;
  final Future<bool> Function()? _reachabilityProbe;
  final Duration _debounce;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounceTimer;
  bool _lifecycleObserved = false;
  ConnectivityStatus _status = ConnectivityStatus.online;
  bool _initialized = false;
  bool _disposed = false;

  /// Aktueller dreiwertiger Zustand.
  ConnectivityStatus get status => _status;

  /// True, solange ein Interface verfügbar **und** das Backend erreichbar ist.
  bool get isOnline => _status == ConnectivityStatus.online;

  /// True bei [ConnectivityStatus.offline] **oder** [backendUnreachable] — beide
  /// bedeuten für die UI „keine verlässliche Verbindung" (Banner zeigen).
  bool get isOffline => _status != ConnectivityStatus.online;

  /// True, wenn ein Interface da ist, aber das Backend nicht antwortet.
  bool get isBackendUnreachable =>
      _status == ConnectivityStatus.backendUnreachable;

  /// True, sobald der erste Konnektivitäts-Check ausgewertet wurde.
  bool get initialized => _initialized;

  Future<void> _init() async {
    _sub = _changes.listen((results) => _apply(results));
    try {
      await _apply(await _check(), initial: true);
    } catch (_) {
      // Plattform ohne Konnektivitäts-API (z. B. Test/Headless): optimistisch
      // online lassen, aber als initialisiert markieren.
    }
    _initialized = true;
    _safeNotify();
  }

  /// Erneute Prüfung anstoßen (Resume/online-Event). Öffentlich, damit auch
  /// Bereiche gezielt neu prüfen können.
  Future<void> recheck() async {
    try {
      await _apply(await _check(), initial: true);
    } catch (_) {
      // still: bestehenden Zustand behalten.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      recheck();
    }
  }

  Future<void> _apply(List<ConnectivityResult> results,
      {bool initial = false}) async {
    final hasInterface = results.any((r) => r != ConnectivityResult.none);

    final probe = _reachabilityProbe;
    ConnectivityStatus target;
    if (!hasInterface) {
      target = ConnectivityStatus.offline;
    } else if (probe == null) {
      // Kein Probe injiziert → Interface-Status genügt (abwärtskompatibel).
      target = ConnectivityStatus.online;
    } else {
      bool reachable;
      try {
        reachable = await probe();
      } catch (_) {
        reachable = false;
      }
      target = reachable
          ? ConnectivityStatus.online
          : ConnectivityStatus.backendUnreachable;
    }

    if (_disposed) return;

    // Der Initial-Check wirkt sofort (UI braucht schnell einen Zustand).
    if (initial) {
      _debounceTimer?.cancel();
      _setStatus(target);
      return;
    }

    // Jede neue Auswertung verwirft eine noch schwebende Änderung — ein kurzer
    // Blip zurück auf den aktuellen Zustand wird so verschluckt (Skill 21).
    _debounceTimer?.cancel();
    if (target == _status) return;

    if (_debounce == Duration.zero) {
      _setStatus(target);
    } else {
      _debounceTimer = Timer(_debounce, () {
        if (!_disposed && target != _status) _setStatus(target);
      });
    }
  }

  void _setStatus(ConnectivityStatus next) {
    if (_status == next) return;
    _status = next;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _sub?.cancel();
    if (_lifecycleObserved) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
    }
    super.dispose();
  }
}
