import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

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
