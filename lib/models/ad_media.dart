import '../core/firestore_date_parser.dart';
import '../core/firestore_num_parser.dart' as parse;

/// Ein hochgeladenes Werbebild (Bibliothek der digitalen Anzeige-Displays,
/// Store-Fernseher). Liegt org-skopiert in der Collection `adMedia`; die
/// Binärdatei selbst in Firebase Storage unter [storagePath].
///
/// [downloadUrl] trägt ein Firebase-Storage-Bearer-Token und ist daher direkt
/// von einem NICHT angemeldeten Fernseher (`Image.network`/`<img>`) ladbar –
/// so muss der Player-Lesepfad keine Storage-Rules erfüllen.
///
/// Zwei-Serialisierungs-Regel: [toFirestoreMap]/[fromFirestore] (camelCase,
/// Timestamp) für Firestore + Fakes; [toMap]/[fromMap] (snake_case, ISO) für
/// SharedPreferences/Callables.
class AdMedia {
  const AdMedia({
    this.id,
    required this.orgId,
    required this.title,
    required this.storagePath,
    required this.downloadUrl,
    this.contentType = 'image/jpeg',
    this.fileSize = 0,
    this.createdByUid,
    this.createdAt,
  });

  /// Doc-Id (== Storage-Objektname). Bei Neuanlage vom Repository vergeben.
  final String? id;
  final String orgId;

  /// Sprechender Name für die Verwaltung (nicht am Fernseher sichtbar).
  final String title;

  /// Voller Storage-Objektpfad (zum Löschen/Ersetzen) – NICHT die URL.
  final String storagePath;

  /// Tokenisierte Download-URL (öffentlich ladbar über das Storage-Bearer-Token).
  final String downloadUrl;
  final String contentType;
  final int fileSize;
  final String? createdByUid;
  final DateTime? createdAt;

  factory AdMedia.fromFirestore(String id, Map<String, dynamic> map) {
    return AdMedia(
      id: id,
      orgId: (map['orgId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      storagePath: (map['storagePath'] ?? '').toString(),
      downloadUrl: (map['downloadUrl'] ?? '').toString(),
      contentType: (map['contentType'] ?? 'image/jpeg').toString(),
      fileSize: parse.toInt(map['fileSize']) ?? 0,
      createdByUid: map['createdByUid'] as String?,
      createdAt: FirestoreDateParser.readDate(map['createdAt']),
    );
  }

  factory AdMedia.fromMap(Map<String, dynamic> map) {
    return AdMedia(
      id: map['id']?.toString(),
      orgId: (map['org_id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      storagePath: (map['storage_path'] ?? '').toString(),
      downloadUrl: (map['download_url'] ?? '').toString(),
      contentType: (map['content_type'] ?? 'image/jpeg').toString(),
      fileSize: parse.toInt(map['file_size']) ?? 0,
      createdByUid: map['created_by_uid'] as String?,
      createdAt: FirestoreDateParser.readLocalDate(map['created_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'orgId': orgId,
      'title': title.trim(),
      // Abgeleiteter Sortierschlüssel (analog Contact.nameLower) → der Stream
      // sortiert per orderBy('titleLower') ohne Composite-Index und ohne den
      // serverTimestamp-null-Ordering-Footgun.
      'titleLower': title.trim().toLowerCase(),
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'contentType': contentType,
      'fileSize': fileSize,
      'createdByUid': createdByUid,
      // createdAt wird beim Anlegen im Repository via serverTimestamp gesetzt.
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'title': title,
      'storage_path': storagePath,
      'download_url': downloadUrl,
      'content_type': contentType,
      'file_size': fileSize,
      'created_by_uid': createdByUid,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  AdMedia copyWith({
    String? id,
    String? orgId,
    String? title,
    String? storagePath,
    String? downloadUrl,
    String? contentType,
    int? fileSize,
    String? createdByUid,
    DateTime? createdAt,
  }) {
    return AdMedia(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      title: title ?? this.title,
      storagePath: storagePath ?? this.storagePath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      contentType: contentType ?? this.contentType,
      fileSize: fileSize ?? this.fileSize,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
