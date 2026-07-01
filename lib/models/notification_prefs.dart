import '../core/firestore_num_parser.dart' as parse;

/// Push-Präferenzen eines Nutzers — eingebettetes Feld-Objekt `notificationPrefs`
/// am `users/{uid}`-Doc (Muster wie `UserPermissions`/`WorkRuleSettings`).
/// Die fünf Kategorie-Schalter sind deckungsgleich mit den Android-Channels
/// (`PushMessagingService`) und den Push-Typen (`channelIdForType`).
///
/// Plan: plan/push-benachrichtigungen-plan.md (M5). Wird serverseitig vor dem
/// Versand ausgewertet (`functions/push_notifications.js#pushAllowed`).
class NotificationPrefs {
  const NotificationPrefs({
    this.masterEnabled = true,
    this.genehmigungen = true,
    this.schichtplan = true,
    this.aufgaben = true,
    this.kundenwuensche = true,
    this.bestand = true,
    this.quietHoursEnabled = false,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 6 * 60,
  });

  final bool masterEnabled;
  final bool genehmigungen;
  final bool schichtplan;
  final bool aufgaben;
  final bool kundenwuensche;
  final bool bestand;
  final bool quietHoursEnabled;

  /// Beginn/Ende der Ruhezeit als Minuten seit Mitternacht (lokale Zeit). Das
  /// Fenster darf über Mitternacht laufen (z. B. 22:00–06:00).
  final int quietStartMinutes;
  final int quietEndMinutes;

  factory NotificationPrefs.fromMap(Map<String, dynamic> map) {
    const d = NotificationPrefs();
    return NotificationPrefs(
      masterEnabled:
          parse.toBool(map['masterEnabled'] ?? map['master_enabled']) ??
              d.masterEnabled,
      genehmigungen: parse.toBool(map['genehmigungen']) ?? d.genehmigungen,
      schichtplan: parse.toBool(map['schichtplan']) ?? d.schichtplan,
      aufgaben: parse.toBool(map['aufgaben']) ?? d.aufgaben,
      kundenwuensche: parse.toBool(map['kundenwuensche']) ?? d.kundenwuensche,
      bestand: parse.toBool(map['bestand']) ?? d.bestand,
      quietHoursEnabled: parse
              .toBool(map['quietHoursEnabled'] ?? map['quiet_hours_enabled']) ??
          d.quietHoursEnabled,
      quietStartMinutes: parse
              .toInt(map['quietStartMinutes'] ?? map['quiet_start_minutes']) ??
          d.quietStartMinutes,
      quietEndMinutes:
          parse.toInt(map['quietEndMinutes'] ?? map['quiet_end_minutes']) ??
              d.quietEndMinutes,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'masterEnabled': masterEnabled,
        'genehmigungen': genehmigungen,
        'schichtplan': schichtplan,
        'aufgaben': aufgaben,
        'kundenwuensche': kundenwuensche,
        'bestand': bestand,
        'quietHoursEnabled': quietHoursEnabled,
        'quietStartMinutes': quietStartMinutes,
        'quietEndMinutes': quietEndMinutes,
      };

  Map<String, dynamic> toMap() => {
        'master_enabled': masterEnabled,
        'genehmigungen': genehmigungen,
        'schichtplan': schichtplan,
        'aufgaben': aufgaben,
        'kundenwuensche': kundenwuensche,
        'bestand': bestand,
        'quiet_hours_enabled': quietHoursEnabled,
        'quiet_start_minutes': quietStartMinutes,
        'quiet_end_minutes': quietEndMinutes,
      };

  /// Ist die Kategorie (= Android-Channel-ID) aktiviert?
  bool categoryEnabled(String channelId) {
    switch (channelId) {
      case 'genehmigungen':
        return genehmigungen;
      case 'schichtplan':
        return schichtplan;
      case 'aufgaben':
        return aufgaben;
      case 'kundenwuensche':
        return kundenwuensche;
      case 'bestand':
        return bestand;
      default:
        return true;
    }
  }

  NotificationPrefs copyWith({
    bool? masterEnabled,
    bool? genehmigungen,
    bool? schichtplan,
    bool? aufgaben,
    bool? kundenwuensche,
    bool? bestand,
    bool? quietHoursEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
  }) {
    return NotificationPrefs(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      genehmigungen: genehmigungen ?? this.genehmigungen,
      schichtplan: schichtplan ?? this.schichtplan,
      aufgaben: aufgaben ?? this.aufgaben,
      kundenwuensche: kundenwuensche ?? this.kundenwuensche,
      bestand: bestand ?? this.bestand,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
      quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    );
  }
}
