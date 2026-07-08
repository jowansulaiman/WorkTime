import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Seam für den **Binär-Teil** der Personalakte-Dokumente (PA-3): Upload/
/// Download/Delete gegen Firebase Storage. Als Interface, damit Tests eine
/// In-Memory-Fake-Implementierung injizieren können (kein echtes Storage im
/// Test) und die Provider-Logik (Metadaten, Audit, Rollback) rein bleibt.
abstract class DocumentStorage {
  /// Lädt [bytes] nach [path] hoch. [onProgress] liefert 0..1 (falls die
  /// Plattform Fortschritt meldet).
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  });

  /// Lädt die Datei unter [path] herunter (bis [maxSizeBytes]); `null`, wenn es
  /// die Datei nicht gibt.
  Future<Uint8List?> download(String path, {int maxSizeBytes});

  /// Entfernt die Datei unter [path] (best-effort; wirft bei echten Fehlern).
  Future<void> delete(String path);

  /// Öffentlich abrufbare Download-URL der Datei unter [path] (z. B. für
  /// `NetworkImage` bei Kontakt-Avataren).
  Future<String> getDownloadUrl(String path);
}

/// Firebase-Storage-gestützte Umsetzung (Produktivpfad). Kapselt die einzige
/// `firebase_storage`-Abhängigkeit — Tests importieren diese Datei nie.
class FirebaseDocumentStorage implements DocumentStorage {
  FirebaseDocumentStorage({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _storage.ref(path);
    final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
    if (onProgress != null) {
      task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total > 0) {
          onProgress(snapshot.bytesTransferred / total);
        }
      });
    }
    await task;
  }

  @override
  Future<Uint8List?> download(
    String path, {
    int maxSizeBytes = 15 * 1024 * 1024,
  }) {
    return _storage.ref(path).getData(maxSizeBytes);
  }

  @override
  Future<void> delete(String path) => _storage.ref(path).delete();

  @override
  Future<String> getDownloadUrl(String path) =>
      _storage.ref(path).getDownloadURL();
}
