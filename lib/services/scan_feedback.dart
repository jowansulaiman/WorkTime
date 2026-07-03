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
    try {
      // Default-Modus (mediaPlayer) statt PlayerMode.lowLatency: der
      // lowLatency-/SoundPool-Pfad spielt Asset-Toene auf Android haeufig gar
      // nicht ab (bekanntes audioplayers-Problem). Quelle EINMAL vorladen ->
      // trotzdem geringe Latenz beim Abspielen (seek(0) + resume).
      await _okPlayer.setReleaseMode(ReleaseMode.stop);
      await _errorPlayer.setReleaseMode(ReleaseMode.stop);
      await _okPlayer.setSource(AssetSource(_okAsset));
      await _errorPlayer.setSource(AssetSource(_errorAsset));
      // Erst nach erfolgreichem Vorladen als konfiguriert markieren, damit ein
      // transienter Fehler beim naechsten Scan erneut versucht wird.
      _configured = true;
    } catch (_) {
      // Audio nicht verfuegbar (z. B. Web ohne Nutzergeste) — Haptik/visuell
      // reicht. Kein Rethrow: Feedback darf den Scan-Flow nie blockieren.
    }
  }

  Future<void> _play(AudioPlayer player) async {
    if (!soundEnabled) return;
    await _ensureConfigured();
    try {
      await player.seek(Duration.zero);
      await player.resume();
    } catch (_) {
      // Ton stumm schlucken — visuelles Feedback bleibt.
    }
  }

  @override
  Future<void> success() async {
    // Haptik + Ton parallel, damit die Vibration den Ton nicht verzoegert.
    await Future.wait<void>([
      if (hapticsEnabled) _vibrateSuccess(),
      _play(_okPlayer),
    ]);
  }

  @override
  Future<void> failure() async {
    await Future.wait<void>([
      if (hapticsEnabled) _vibrateFailure(),
      _play(_errorPlayer),
    ]);
  }

  /// Kurzer, deutlicher Buzz zur Erfolgs-Bestaetigung.
  Future<void> _vibrateSuccess() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Doppel-Buzz fuer Fehler — klar von der Erfolgs-Haptik unterscheidbar.
  Future<void> _vibrateFailure() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 130));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
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
