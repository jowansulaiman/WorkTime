import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Seam fuer akustisches + haptisches Feedback beim Scannen.
///
/// Wird dem [ScannerScreen] per Konstruktor uebergeben, damit Widget-Tests die
/// echten Platform-Channel-Aufrufe (Audio/Haptik) durch [NoopScanFeedback]
/// ersetzen koennen und nicht haengen.
abstract interface class ScanFeedback {
  /// Erfolg: heller Bestaetigungston + leichte Haptik.
  Future<void> success();

  /// Fehler: tieferer/doppelter Ton + kraeftige Haptik.
  Future<void> failure();

  /// Ressourcen freigeben (AudioPlayer schliessen).
  Future<void> dispose();
}

/// Echtes Feedback: kurze WAV-Toene (audioplayers, Low-Latency) plus Haptik.
///
/// Auf Web/Desktop sind Haptik und ggf. Audio No-op/stumm — die visuelle
/// Rueckmeldung im [ScannerScreen] (Rahmen-Blitz + SnackBar) ist deshalb Pflicht.
class AudioHapticFeedback implements ScanFeedback {
  AudioHapticFeedback({this.soundEnabled = true, this.hapticsEnabled = true});

  /// Toene abspielen (im Laden ggf. abschaltbar).
  bool soundEnabled;

  /// Vibration ausloesen.
  bool hapticsEnabled;

  // AssetSource-Pfad OHNE 'assets/'-Praefix — AudioCache praefixt selbst.
  static const String _okAsset = 'audio/scan_ok.wav';
  static const String _errorAsset = 'audio/scan_error.wav';

  final AudioPlayer _okPlayer = AudioPlayer();
  final AudioPlayer _errorPlayer = AudioPlayer();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    try {
      await _okPlayer.setReleaseMode(ReleaseMode.stop);
      await _errorPlayer.setReleaseMode(ReleaseMode.stop);
      await _okPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _errorPlayer.setPlayerMode(PlayerMode.lowLatency);
    } catch (_) {
      // Audio nicht verfuegbar (z. B. Web ohne Nutzergeste) — Haptik/visuell
      // reicht. Kein Rethrow: Feedback darf den Scan-Flow nie blockieren.
    }
  }

  Future<void> _play(AudioPlayer player, String asset) async {
    if (!soundEnabled) return;
    await _ensureConfigured();
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // Ton stumm schlucken — visuelles Feedback bleibt.
    }
  }

  @override
  Future<void> success() async {
    if (hapticsEnabled) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}
    }
    await _play(_okPlayer, _okAsset);
  }

  @override
  Future<void> failure() async {
    if (hapticsEnabled) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
    await _play(_errorPlayer, _errorAsset);
  }

  @override
  Future<void> dispose() async {
    try {
      await _okPlayer.dispose();
    } catch (_) {}
    try {
      await _errorPlayer.dispose();
    } catch (_) {}
  }
}

/// Tut nichts — fuer Tests und fuer den lautlosen Betrieb (Ton + Vibration aus).
class NoopScanFeedback implements ScanFeedback {
  const NoopScanFeedback();

  @override
  Future<void> success() async {}

  @override
  Future<void> failure() async {}

  @override
  Future<void> dispose() async {}
}
