import '../models/ad_media.dart';
import '../models/signage_display.dart';

/// Abstraktion über den Datenzugriff der digitalen Werbe-Displays (Store-TVs):
/// Werbebild-Bibliothek ([AdMedia]), Displays ([SignageDisplay]) und die
/// öffentliche Player-Projektion (`publicDisplays/{token}`).
///
/// Der [SignageProvider] hängt an dieser Abstraktion statt an der konkreten
/// `FirestoreService`-Klasse (DIP) und ersetzt sie in Tests durch einen
/// handgeschriebenen Fake.
abstract interface class SignageRepository {
  // --- Werbebild-Bibliothek -------------------------------------------------

  Stream<List<AdMedia>> watchMedia(String orgId);

  /// Frische Doc-Id für ein neues Werbebild – dient zugleich als Storage-
  /// Objektname, damit Metadaten-Doc und Storage-Objekt eine Id teilen.
  String newMediaId(String orgId);

  Future<void> saveMedia(AdMedia media);

  Future<void> deleteMedia({required String orgId, required String mediaId});

  // --- Displays -------------------------------------------------------------

  Stream<List<SignageDisplay>> watchDisplays(String orgId);

  Future<void> saveDisplay(SignageDisplay display);

  Future<void> deleteDisplay({
    required String orgId,
    required String displayId,
  });

  // --- Öffentliche Player-Projektion ---------------------------------------

  /// Schreibt die denormalisierte, öffentlich (login-frei) lesbare Projektion
  /// eines Displays nach `publicDisplays/{token}`. Der Fernseher liest genau
  /// dieses Dokument über seinen Token.
  Future<void> publishPublicDisplay(
    String token,
    Map<String, dynamic> projection,
  );

  /// Entfernt die öffentliche Projektion (Display gelöscht → Player wird leer).
  Future<void> unpublishPublicDisplay(String token);
}
