import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Wie ein Werbebild in den Bildschirm eingepasst wird.
enum SignageFit {
  /// Bild füllt den ganzen Bildschirm (ggf. beschnitten). Default für Werbung.
  cover,

  /// Bild vollständig sichtbar (ggf. mit schwarzen Rändern / Letterboxing).
  contain;

  /// Stabiler Wire-Wert (snake_case-frei, hier ohnehin einwortig). Niemals
  /// umbenennen (siehe [fromValue]-Default).
  String get value => switch (this) {
        SignageFit.cover => 'cover',
        SignageFit.contain => 'contain',
      };

  String get label => switch (this) {
        SignageFit.cover => 'Bildschirm füllen',
        SignageFit.contain => 'Ganz zeigen',
      };

  static SignageFit fromValue(String? value) => switch (value) {
        'contain' => SignageFit.contain,
        _ => SignageFit.cover,
      };
}

/// Übergangs-Animation zwischen zwei Werbebildern (bzw. Effekt während der
/// Standzeit). Pro Display wählbar; der öffentliche Player wendet sie an.
enum SignageTransition {
  /// Sanftes Überblenden (Crossfade). Default.
  fade,

  /// Neues Bild schiebt von rechts herein.
  slide,

  /// Neues Bild zoomt auf (Scale + Fade).
  zoom,

  /// Ken-Burns: das Bild zoomt während der Standzeit langsam heran
  /// (mit Überblenden beim Wechsel) — klassischer Werbe-Look.
  kenBurns,

  /// Kein Effekt (harter Schnitt).
  none;

  /// Stabiler Wire-Wert (snake_case). Niemals umbenennen (siehe [fromValue]).
  String get value => switch (this) {
        SignageTransition.fade => 'fade',
        SignageTransition.slide => 'slide',
        SignageTransition.zoom => 'zoom',
        SignageTransition.kenBurns => 'ken_burns',
        SignageTransition.none => 'none',
      };

  String get label => switch (this) {
        SignageTransition.fade => 'Überblenden',
        SignageTransition.slide => 'Schieben',
        SignageTransition.zoom => 'Zoomen',
        SignageTransition.kenBurns => 'Ken Burns (langsamer Zoom)',
        SignageTransition.none => 'Hart schneiden',
      };

  static SignageTransition fromValue(String? value) => switch (value) {
        'slide' => SignageTransition.slide,
        'zoom' => SignageTransition.zoom,
        'ken_burns' => SignageTransition.kenBurns,
        'none' => SignageTransition.none,
        _ => SignageTransition.fade,
      };
}

/// Ein digitales Werbe-Display (Store-Fernseher). Trägt eine geordnete Playlist
/// von [AdMedia]-Ids ([mediaIds]) und die Anzeigedauer je Bild ([slideSeconds]).
///
/// Der Fernseher öffnet die öffentliche Player-URL `/anzeige/<pairingToken>`
/// und liest die denormalisierte, login-frei lesbare Projektion aus
/// `publicDisplays/{pairingToken}` (siehe [PublicDisplayData]). [pairingToken]
/// ist ein unratbares Bearer-Secret – wer ihn kennt, sieht nur die Werbung
/// dieses einen Displays (kein LIST der Collection).
class SignageDisplay {
  const SignageDisplay({
    this.id,
    required this.orgId,
    required this.name,
    this.siteId,
    required this.pairingToken,
    this.slideSeconds = 8,
    this.fit = SignageFit.cover,
    this.transition = SignageTransition.fade,
    this.mediaIds = const [],
    this.isActive = true,
    this.createdByUid,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String orgId;
  final String name;

  /// Optionaler Standort (Laden), an dem der Fernseher hängt – nur Zuordnung.
  final String? siteId;

  /// Unratbares Bearer-Secret für die öffentliche Player-URL.
  final String pairingToken;

  /// Anzeigedauer je Bild in Sekunden (mindestens 3).
  final int slideSeconds;
  final SignageFit fit;

  /// Übergangs-Animation zwischen den Bildern.
  final SignageTransition transition;

  /// Geordnete Playlist: [AdMedia]-Ids in Abspielreihenfolge.
  final List<String> mediaIds;
  final bool isActive;
  final String? createdByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get slideCount => mediaIds.length;

  factory SignageDisplay.fromFirestore(String id, Map<String, dynamic> map) {
    return SignageDisplay(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      siteId: map['siteId'] as String?,
      pairingToken: (map['pairingToken'] ?? '').toString(),
      slideSeconds: parse.toInt(map['slideSeconds']) ?? 8,
      fit: SignageFit.fromValue(map['fit'] as String?),
      transition: SignageTransition.fromValue(map['transition'] as String?),
      mediaIds: _stringList(map['mediaIds']),
      isActive: parse.toBool(map['isActive']) ?? true,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
      updatedAt: FirestoreDateParser.readDate(map['updatedAt']),
    );
  }

  factory SignageDisplay.fromMap(Map<String, dynamic> map) {
    return SignageDisplay(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      siteId: map['site_id'] as String?,
      pairingToken: (map['pairing_token'] ?? '').toString(),
      slideSeconds: parse.toInt(map['slide_seconds']) ?? 8,
      fit: SignageFit.fromValue(map['fit'] as String?),
      transition: SignageTransition.fromValue(map['transition'] as String?),
      mediaIds: _stringList(map['media_ids']),
      isActive: parse.toBool(map['is_active']) ?? true,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
      updatedAt: FirestoreDateParser.readLocalDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'name': name.trim(),
      // Abgeleiteter Sortierschlüssel (analog Contact.nameLower) → orderBy ohne
      // Composite-Index und ohne serverTimestamp-null-Ordering-Footgun.
      'nameLower': name.trim().toLowerCase(),
      'siteId': _trimmedOrNull(siteId),
      'pairingToken': pairingToken,
      'slideSeconds': slideSeconds,
      'fit': fit.value,
      'transition': transition.value,
      'mediaIds': mediaIds,
      'isActive': isActive,
      'createdByUid': createdByUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'name': name,
      'site_id': siteId,
      'pairing_token': pairingToken,
      'slide_seconds': slideSeconds,
      'fit': fit.value,
      'transition': transition.value,
      'media_ids': mediaIds,
      'is_active': isActive,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  SignageDisplay copyWith({
    String? id,
    String? orgId,
    String? name,
    String? siteId,
    String? pairingToken,
    int? slideSeconds,
    SignageFit? fit,
    SignageTransition? transition,
    List<String>? mediaIds,
    bool? isActive,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearSiteId = false,
  }) {
    return SignageDisplay(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
      pairingToken: pairingToken ?? this.pairingToken,
      slideSeconds: slideSeconds ?? this.slideSeconds,
      fit: fit ?? this.fit,
      transition: transition ?? this.transition,
      mediaIds: mediaIds ?? this.mediaIds,
      isActive: isActive ?? this.isActive,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((entry) => entry?.toString() ?? '')
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

/// Eine einzelne Werbe-Folie, wie sie der öffentliche Player liest (Bild-URL +
/// Standzeit). Eingebettet in [PublicDisplayData.slides].
class PublicDisplaySlide {
  const PublicDisplaySlide({
    required this.url,
    required this.seconds,
    this.title = '',
  });

  final String url;
  final int seconds;
  final String title;

  factory PublicDisplaySlide.fromMap(Map<String, dynamic> map) {
    return PublicDisplaySlide(
      url: (map['url'] ?? '').toString(),
      seconds: parse.toInt(map['seconds']) ?? 8,
      title: (map['title'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'seconds': seconds,
      'title': title,
    };
  }
}

/// Die denormalisierte, login-frei lesbare Projektion eines Displays, die der
/// öffentliche Player (`/anzeige/<token>`) aus `publicDisplays/{token}` liest.
///
/// Bewusst getrennt von [SignageDisplay]: sie enthält bereits die aufgelösten
/// Bild-URLs (kein zweiter Read auf `adMedia`) und keine internen Ids/Felder.
/// Wird ausschließlich vom Admin-Client geschrieben (mirror), vom Fernseher nur
/// gelesen. Keys sind camelCase (direkter Firestore-Doc, kein Callable).
class PublicDisplayData {
  const PublicDisplayData({
    required this.name,
    required this.slideSeconds,
    required this.fit,
    required this.transition,
    required this.isActive,
    required this.slides,
  });

  final String name;
  final int slideSeconds;
  final SignageFit fit;
  final SignageTransition transition;
  final bool isActive;
  final List<PublicDisplaySlide> slides;

  factory PublicDisplayData.fromMap(Map<String, dynamic> map) {
    final rawSlides = map['slides'];
    return PublicDisplayData(
      name: (map['name'] ?? '').toString(),
      slideSeconds: parse.toInt(map['slideSeconds']) ?? 8,
      fit: SignageFit.fromValue(map['fit'] as String?),
      transition: SignageTransition.fromValue(map['transition'] as String?),
      isActive: parse.toBool(map['isActive']) ?? true,
      slides: rawSlides is List
          ? rawSlides
              .whereType<Map>()
              .map((entry) =>
                  PublicDisplaySlide.fromMap(entry.cast<String, dynamic>()))
              .where((slide) => slide.url.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }
}
