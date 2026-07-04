import 'package:flutter/material.dart';

import '../../../widgets/employee_documents_card.dart';

/// Dokumente-Tab der Mitarbeiter-Detailseite — **AllTec-1:1**: nutzt die
/// bestehende [EmployeeDocumentsCard] (Upload/Download/Löschen, Kategorien,
/// Aufbewahrungsfrist) wieder. Der Detail-Screen ist admin-only → `canManage`.
class EmployeeDokumenteTab extends StatelessWidget {
  const EmployeeDokumenteTab({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EmployeeDocumentsCard(userId: userId, canManage: true),
      ],
    );
  }
}
