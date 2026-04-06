import 'package:flutter/foundation.dart';

import '../services/database_service.dart';

enum DataStorageLocation { hybrid, cloud, local }

/// Kategorisiert Daten nach ihrem Hybrid-Speicherverhalten.
///
/// Im Hybrid-Modus gilt:
/// - [structural]: Kleine, selten aendernde Stammdaten (Teams, Sites, etc.).
///   Diese werden ausschliesslich in der Cloud gespeichert und von Firestore
///   Offline-Persistence automatisch lokal gecacht. Kein manuelles
///   SharedPreferences-Caching noetig → spart Writes und bleibt im
///   Firebase-Spark-Freitarif.
/// - [userContent]: Benutzerspezifische, haeufig gelesene Daten (WorkEntries,
///   Shifts, Templates). Diese werden zusaetzlich manuell in SharedPreferences
///   gecacht fuer schnelleren Offline-Start.
enum HybridDataCategory {
  structural,
  userContent,
}

class StorageModeProvider extends ChangeNotifier {
  DataStorageLocation _location = DataStorageLocation.hybrid;
  bool _initialized = false;

  DataStorageLocation get location => _location;
  bool get initialized => _initialized;
  bool get isLocalOnly => _location == DataStorageLocation.local;
  bool get isHybrid => _location == DataStorageLocation.hybrid;
  bool get usesCloudStorage => _location != DataStorageLocation.local;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    final rawLocation = await DatabaseService.loadDataStorageLocation();
    _location = switch (rawLocation) {
      'local' => DataStorageLocation.local,
      'cloud' => DataStorageLocation.cloud,
      _ => DataStorageLocation.hybrid,
    };
    _initialized = true;
    notifyListeners();
  }

  Future<void> setLocation(DataStorageLocation location) async {
    if (_initialized && _location == location) {
      return;
    }
    _location = location;
    _initialized = true;
    await DatabaseService.saveDataStorageLocation(location.name);
    notifyListeners();
  }
}
