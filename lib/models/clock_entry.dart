// lib/models/clock_entry.dart

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_num_parser.dart' as parse;

/// Status einer Stempel-Session (Kommen/Gehen) — AllTec-1:1 (M3).
///
/// `status` ist **autoritativ** (treibt die org-weite „Wer ist eingestempelt"-
/// Abfrage `where status == ongoing`); `isOngoing` liest es nur. Auf `gehen == null`
/// wird sich bewusst NICHT als zweite Quelle verlassen.
enum ClockStatus {
  ongoing,
  completed,
  klaerung,
  deaktiviert;

  String get value => switch (this) {
        ClockStatus.ongoing => 'ongoing',
        ClockStatus.completed => 'completed',
        ClockStatus.klaerung => 'klaerung',
        ClockStatus.deaktiviert => 'deaktiviert',
      };

  String get label => switch (this) {
        ClockStatus.ongoing => 'Läuft',
        ClockStatus.completed => 'Abgeschlossen',
        ClockStatus.klaerung => 'Klärung',
        ClockStatus.deaktiviert => 'Deaktiviert',
      };

  /// Tolerant: unbekannt/leer → [ongoing] (Default-Branch wirft nie).
  static ClockStatus fromValue(Object? raw) {
    final value = (raw ?? '').toString().trim();
    for (final status in ClockStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    return ClockStatus.ongoing;
  }
}

/// Eine Anwesenheits-Buchung (Kommen → Gehen). Persistente Stempel-Session
/// (ersetzt den früheren ephemeren Clock-State im `WorkProvider`).
///
/// **Datums-Ausnahme wie `WorkEntry`:** `kommen` ist Pflicht (wirft
/// `FormatException` bei fehlend/kaputt); `gehen` ist null, solange die Buchung
/// läuft. Zeitstempel werden NICHT auf Mittag normalisiert (präzise Uhrzeiten).
class ClockEntry {
  final String? id;
  final String orgId;
  final String userId;
  final String? userName;
  final String? siteId;
  final String? siteName;
  final DateTime kommen;
  final DateTime? gehen;
  final int pauseMinuten;

  /// Netto-Minuten der abgeschlossenen Buchung (0 solange laufend).
  final int nettoMinutes;

  final ClockStatus status;
  final bool manuellErfasst;
  final bool klaerung;
  final String? anmerkung;
  final String? ipKommen;
  final String? ipGehen;

  /// Geplante Schicht, der dieser Stempel zugeordnet ist (ZV-2.1). Null = frei
  /// gestempelt (gilt im Soll-Ist-Abgleich als „ungeplant anwesend").
  final String? shiftId;

  /// Ursprung des Stempels: `'app'` (Web/iOS/Android) oder `'kiosk'` (Tablet-
  /// Arbeitsmodus). `kioskClockPunch` setzt `'kiosk'`; App-Pfad `'app'`.
  final String? source;

  /// Geräte-/Session-Forensik (nur Kiosk-Pfad gefüllt): stempelndes Gerät bzw.
  /// die server-geprüfte PIN-Session (`kioskSessions/{sid}`).
  final String? deviceId;
  final String? sessionId;

  /// Korrektur-Historie am Datensatz (zusätzlich zum zentralen Audit-Log, ZV-3):
  /// wer die abgeschlossene/geklärte Buchung zuletzt korrigiert hat und warum.
  final String? korrigiertVonUid;
  final String? korrekturGrund;

  /// Verknüpfter erzeugter [WorkEntry] (beim Ausstempeln; Duplikat-Vermeidung).
  final String? workEntryId;

  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ClockEntry({
    this.id,
    this.orgId = '',
    this.userId = '',
    this.userName,
    this.siteId,
    this.siteName,
    required DateTime kommen,
    DateTime? gehen,
    int pauseMinuten = 0,
    int nettoMinutes = 0,
    this.status = ClockStatus.ongoing,
    this.manuellErfasst = false,
    this.klaerung = false,
    this.anmerkung,
    this.ipKommen,
    this.ipGehen,
    this.shiftId,
    this.source,
    this.deviceId,
    this.sessionId,
    this.korrigiertVonUid,
    this.korrekturGrund,
    this.workEntryId,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  })  : kommen = _normalize(kommen),
        gehen = gehen == null ? null : _normalize(gehen),
        pauseMinuten = pauseMinuten < 0 ? 0 : pauseMinuten,
        nettoMinutes = nettoMinutes < 0 ? 0 : nettoMinutes;

  /// Läuft die Buchung noch? (autoritativ über [status]).
  bool get isOngoing => status == ClockStatus.ongoing;

  static DateTime _normalize(DateTime value) =>
      value.isUtc ? value.toLocal() : value;

  static DateTime _parseDate(dynamic raw) {
    if (raw is Timestamp) return _normalize(raw.toDate());
    if (raw is DateTime) return _normalize(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      return _normalize(DateTime.parse(raw));
    }
    throw FormatException('ClockEntry: ungültiges kommen-Datum ($raw)');
  }

  static DateTime? _parseNullableDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is String && raw.trim().isEmpty) return null;
    return _parseDate(raw);
  }

  // ── snake_case (SharedPreferences / Callable-Payload) ──────────────────────
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'user_id': userId,
      'user_name': userName,
      'site_id': siteId,
      'site_name': siteName,
      'kommen': kommen.toIso8601String(),
      'gehen': gehen?.toIso8601String(),
      'pause_minuten': pauseMinuten,
      'netto_minutes': nettoMinutes,
      'status': status.value,
      'manuell_erfasst': manuellErfasst,
      'klaerung': klaerung,
      'anmerkung': anmerkung,
      'ip_kommen': ipKommen,
      'ip_gehen': ipGehen,
      'shift_id': shiftId,
      'source': source,
      'device_id': deviceId,
      'session_id': sessionId,
      'korrigiert_von_uid': korrigiertVonUid,
      'korrektur_grund': korrekturGrund,
      'work_entry_id': workEntryId,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory ClockEntry.fromMap(Map<String, dynamic> map) {
    return ClockEntry(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      userName: map['user_name'] as String?,
      siteId: map['site_id'] as String?,
      siteName: map['site_name'] as String?,
      kommen: _parseDate(map['kommen']),
      gehen: _parseNullableDate(map['gehen']),
      pauseMinuten: parse.toInt(map['pause_minuten']) ?? 0,
      nettoMinutes: parse.toInt(map['netto_minutes']) ?? 0,
      status: ClockStatus.fromValue(map['status']),
      manuellErfasst: parse.toBool(map['manuell_erfasst']) ?? false,
      klaerung: parse.toBool(map['klaerung']) ?? false,
      anmerkung: map['anmerkung'] as String?,
      ipKommen: map['ip_kommen'] as String?,
      ipGehen: map['ip_gehen'] as String?,
      shiftId: map['shift_id'] as String?,
      source: map['source'] as String?,
      deviceId: map['device_id'] as String?,
      sessionId: map['session_id'] as String?,
      korrigiertVonUid: map['korrigiert_von_uid'] as String?,
      korrekturGrund: map['korrektur_grund'] as String?,
      workEntryId: map['work_entry_id'] as String?,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: _parseNullableDate(map['created_at']),
      updatedAt: _parseNullableDate(map['updated_at']),
    );
  }

  // ── camelCase (Firestore) ──────────────────────────────────────────────────
  factory ClockEntry.fromFirestore(String id, Map<String, dynamic> map) {
    return ClockEntry(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      userName: map['userName'] as String?,
      siteId: map['siteId'] as String?,
      siteName: map['siteName'] as String?,
      kommen: _parseDate(map['kommen']),
      gehen: _parseNullableDate(map['gehen']),
      pauseMinuten: parse.toInt(map['pauseMinuten']) ?? 0,
      nettoMinutes: parse.toInt(map['nettoMinutes']) ?? 0,
      status: ClockStatus.fromValue(map['status']),
      manuellErfasst: parse.toBool(map['manuellErfasst']) ?? false,
      klaerung: parse.toBool(map['klaerung']) ?? false,
      anmerkung: map['anmerkung'] as String?,
      ipKommen: map['ipKommen'] as String?,
      ipGehen: map['ipGehen'] as String?,
      shiftId: map['shiftId'] as String?,
      source: map['source'] as String?,
      deviceId: map['deviceId'] as String?,
      sessionId: map['sessionId'] as String?,
      korrigiertVonUid: map['korrigiertVonUid'] as String?,
      korrekturGrund: map['korrekturGrund'] as String?,
      workEntryId: map['workEntryId'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: _parseNullableDate(map['createdAt']),
      updatedAt: _parseNullableDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'userId': userId,
      'userName': userName,
      'siteId': siteId,
      'siteName': siteName,
      'kommen': Timestamp.fromDate(kommen),
      'gehen': gehen == null ? null : Timestamp.fromDate(gehen!),
      'pauseMinuten': pauseMinuten,
      'nettoMinutes': nettoMinutes,
      'status': status.value,
      'manuellErfasst': manuellErfasst,
      'klaerung': klaerung,
      'anmerkung': anmerkung,
      'ipKommen': ipKommen,
      'ipGehen': ipGehen,
      'shiftId': shiftId,
      'source': source,
      'deviceId': deviceId,
      'sessionId': sessionId,
      'korrigiertVonUid': korrigiertVonUid,
      'korrekturGrund': korrekturGrund,
      'workEntryId': workEntryId,
      'createdByUid': createdByUid,
      // createdAt-Guard: NUR beim ersten Schreiben setzen (nicht an id koppeln).
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ClockEntry copyWith({
    String? id,
    String? orgId,
    String? userId,
    String? userName,
    String? siteId,
    String? siteName,
    DateTime? kommen,
    DateTime? gehen,
    int? pauseMinuten,
    int? nettoMinutes,
    ClockStatus? status,
    bool? manuellErfasst,
    bool? klaerung,
    String? anmerkung,
    String? ipKommen,
    String? ipGehen,
    String? shiftId,
    String? source,
    String? deviceId,
    String? sessionId,
    String? korrigiertVonUid,
    String? korrekturGrund,
    String? workEntryId,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearGehen = false,
    bool clearSiteId = false,
    bool clearSiteName = false,
    bool clearAnmerkung = false,
    bool clearIpGehen = false,
    bool clearShiftId = false,
    bool clearKorrigiertVonUid = false,
    bool clearKorrekturGrund = false,
    bool clearWorkEntryId = false,
  }) {
    return ClockEntry(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      siteName: clearSiteName ? null : (siteName ?? this.siteName),
      kommen: kommen ?? this.kommen,
      gehen: clearGehen ? null : (gehen ?? this.gehen),
      pauseMinuten: pauseMinuten ?? this.pauseMinuten,
      nettoMinutes: nettoMinutes ?? this.nettoMinutes,
      status: status ?? this.status,
      manuellErfasst: manuellErfasst ?? this.manuellErfasst,
      klaerung: klaerung ?? this.klaerung,
      anmerkung: clearAnmerkung ? null : (anmerkung ?? this.anmerkung),
      ipKommen: ipKommen ?? this.ipKommen,
      ipGehen: clearIpGehen ? null : (ipGehen ?? this.ipGehen),
      shiftId: clearShiftId ? null : (shiftId ?? this.shiftId),
      source: source ?? this.source,
      deviceId: deviceId ?? this.deviceId,
      sessionId: sessionId ?? this.sessionId,
      korrigiertVonUid:
          clearKorrigiertVonUid ? null : (korrigiertVonUid ?? this.korrigiertVonUid),
      korrekturGrund:
          clearKorrekturGrund ? null : (korrekturGrund ?? this.korrekturGrund),
      workEntryId: clearWorkEntryId ? null : (workEntryId ?? this.workEntryId),
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
