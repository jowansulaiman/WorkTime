import 'package:file_picker/file_picker.dart';

import '../../core/app_config.dart';
import '../../firebase_options.dart';
import '../../services/document_storage.dart';

/// Upload eines Kontakt-Avatars nach Firebase Storage. Isoliert die
/// `file_picker`/`firebase_storage`-Abhängigkeit vom Screen und ist nur
/// verfügbar, wenn Firebase konfiguriert und nicht im Offline-/Demo-Modus ist
/// (sonst würde `FirebaseStorage.instance` werfen).
abstract final class ContactAvatarUploader {
  /// Ob ein Upload möglich ist (Firebase konfiguriert, kein Offline-/Demo-Modus).
  static bool get isAvailable =>
      !AppConfig.disableAuthentication && DefaultFirebaseOptions.isConfigured;

  /// Bild wählen, hochladen und die Download-URL zurückgeben. `null`, wenn der
  /// Nutzer abbricht oder keine Bytes vorliegen.
  static Future<String?> pickAndUpload({
    required String orgId,
    required String contactId,
    DocumentStorage? storage,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    final ext = (file.extension ?? 'jpg').toLowerCase();
    final path = 'organizations/$orgId/contacts/$contactId/avatar.$ext';
    final store = storage ?? FirebaseDocumentStorage();
    await store.upload(
      path: path,
      bytes: bytes,
      contentType: _contentTypeFor(ext),
    );
    return store.getDownloadUrl(path);
  }

  static String _contentTypeFor(String ext) => switch (ext) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
