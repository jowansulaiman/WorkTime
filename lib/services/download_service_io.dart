import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Mobile/Desktop-Implementierung (alles mit dart:io): Bytes werden zuerst in
// eine echte Temp-Datei geschrieben und dann über das native Share-Sheet
// (share_plus) geteilt. Web hat eine eigene Datei (download_service_web.dart)
// mit Blob-Download.
//
// WICHTIG: NICHT `XFile.fromData` verwenden — eine reine In-Memory-XFile ohne
// Pfad wird von share_plus auf macOS/Desktop und iOS nicht zuverlässig ans
// Share-Sheet materialisiert (PDF-Export „funktioniert nicht"). Ein echter
// Datei-Pfad funktioniert plattformübergreifend.

Future<void> downloadFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final directory = await getTemporaryDirectory();
  final safeName = _sanitizeFileName(fileName);
  final file = File('${directory.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: mimeType, name: fileName)],
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

/// Entfernt für das Dateisystem unzulässige Zeichen aus dem Dateinamen
/// (Slashes, Doppelpunkte etc.), behält aber die Endung.
String _sanitizeFileName(String fileName) {
  final cleaned = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return cleaned.isEmpty ? 'export' : cleaned;
}
