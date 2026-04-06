import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreDateParser {
  const FirestoreDateParser._();

  static DateTime? readDate(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static DateTime? readLocalDate(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
