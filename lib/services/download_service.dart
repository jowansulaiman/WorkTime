// Plattformneutraler Vertrag für Datei-/PDF-Downloads. Die konkrete
// Implementierung wird per Conditional Export gewählt:
//   - dart:io vorhanden (Mobile/Desktop) → download_service_io.dart (share_plus)
//   - dart:html vorhanden (Web)          → download_service_web.dart (Blob)
//   - keins von beidem                   → download_service_stub.dart (UnsupportedError)
// Beide konkreten Dateien MÜSSEN dieselbe Signatur tragen
// (downloadFileBytes / downloadPdfBytes), sonst bricht der Import je Plattform.
export 'download_service_stub.dart'
    if (dart.library.io) 'download_service_io.dart'
    if (dart.library.html) 'download_service_web.dart';
