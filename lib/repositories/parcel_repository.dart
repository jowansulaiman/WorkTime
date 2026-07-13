import '../models/paketshop_settings.dart';
import '../models/parcel_customer.dart';
import '../models/parcel_shipment.dart';
import '../models/shelf_compartment.dart';

/// Abstraktion über den Datenzugriff des Paketshops (Pakete, Fächer,
/// Kunden-Namensregister).
///
/// Wie [InventoryRepository] hängt die High-Level-Schicht (`ParcelProvider`)
/// von dieser Abstraktion statt vom konkreten `FirestoreService` ab (DIP); in
/// Tests ersetzbar durch einen handgeschriebenen Fake. Reiner Cloud-
/// Datenzugriff — die Speicherstrategie (cloud/hybrid/local) liegt im Provider.
///
/// **Kein** Anonymisierungs-/Purge-Schreibpfad in v1 (Betreiber-Entscheidung
/// §0 des Plans: keine automatische Löschung). Gelöscht wird nur manuell auf
/// Wunsch über [deleteParcel]/[deleteCustomer] (Art. 17/21). Ein optionaler
/// Anonymisierungs-Lauf käme erst mit dem später aktivierbaren Schalter (P-11).
abstract interface class ParcelRepository {
  // --- Pakete (parcelShipments) ------------------------------------------
  Stream<List<ParcelShipment>> watchParcels(String orgId);

  /// Speichert ein Paket (Anlage oder Update) und gibt dessen Doc-ID zurück
  /// (bei Anlage die neu vergebene).
  Future<String> saveParcel(ParcelShipment shipment);

  Future<void> deleteParcel({required String orgId, required String id});

  // --- Fächer (shelfCompartments) ----------------------------------------
  Stream<List<ShelfCompartment>> watchCompartments(String orgId);

  Future<String> saveCompartment(ShelfCompartment compartment);

  Future<void> deleteCompartment({required String orgId, required String id});

  // --- Kunden-Namensregister (parcelCustomers) ---------------------------
  Stream<List<ParcelCustomer>> watchCustomers(String orgId);

  Future<String> saveCustomer(ParcelCustomer customer);

  /// Löscht einen Registereintrag (Widerspruch/Art. 17). Die Entkopplung des
  /// `parcelCustomerId` an offenen Paketen erledigt der Provider fachlich.
  Future<void> deleteCustomer({required String orgId, required String id});

  // --- Config-Singleton (config/paketshopSettings) -----------------------

  /// Liest die Paketshop-Einstellungen (überfällig-Frist, paketshopSiteId, …).
  /// `null`, wenn das Config-Doc (noch) nicht existiert → Aufrufer nimmt
  /// [PaketshopSettings.defaults].
  Future<PaketshopSettings?> fetchSettings(String orgId);

  /// Schreibt die Paketshop-Einstellungen (merge-sicher).
  Future<void> saveSettings(String orgId, PaketshopSettings settings);
}
