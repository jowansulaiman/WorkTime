import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

// Mobile/Desktop-Implementierung (alles mit dart:io): Bytes werden über das
// native Share-Sheet (share_plus) geteilt. Web hat eine eigene Datei
// (download_service_web.dart) mit Blob-Download.

Future<void> downloadFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  return Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        mimeType: mimeType,
        name: fileName,
      ),
    ],
    subject: fileName,
  );
}

Future<void> downloadPdfBytes({
  required Uint8List bytes,
  required String fileName,
}) {
  return downloadFileBytes(
    bytes: bytes,
    fileName: fileName,
    mimeType: 'application/pdf',
  );
}
