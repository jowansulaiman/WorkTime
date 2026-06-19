import 'dart:typed_data';

// Echter Stub: wird nur ausgewählt, wenn weder dart:io (Mobile/Desktop) noch
// dart:html (Web) verfügbar ist. Auf den unterstützten Flutter-Plattformen
// greift immer eine der konkreten Implementierungen
// (download_service_io.dart bzw. download_service_web.dart). Dieser Pfad ist
// die dokumentierte „nicht unterstützt"-Grenze des plattformneutralen Vertrags.

Future<void> downloadFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  throw UnsupportedError(
    'Datei-Download wird auf dieser Plattform nicht unterstützt.',
  );
}

Future<void> downloadPdfBytes({
  required Uint8List bytes,
  required String fileName,
}) {
  throw UnsupportedError(
    'PDF-Download wird auf dieser Plattform nicht unterstützt.',
  );
}
