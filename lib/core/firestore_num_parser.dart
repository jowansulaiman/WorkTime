/// Sichere Konvertierung von Firestore-Werten zu num/int/double/bool.
///
/// Firestore kann Felder je nach Client und Plattform als [num],
/// [String], [bool] oder [null] liefern. Diese Helfer vermeiden
/// harte `as`-Casts, die bei unerwarteten Typen crashen.
double? toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? toInt(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? toBool(dynamic value) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  if (value is num) return value != 0;
  return null;
}

/// Konvertiert einen dynamischen Wert sicher in eine
/// [Map<String, dynamic>]. Gibt eine leere Map zurueck, falls der
/// Wert kein Map-Typ ist.
Map<String, dynamic> toMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}
