import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../../ui/ui.dart';

/// Geteilte Darstellungshelfer für die Kontakt-Kategorie ([ContactType]).
/// Gehoben aus dem file-privaten `_typeIcon`/`_typeTone` in `contacts_screen.dart`,
/// damit Liste, Detailseite und Editor dieselbe Zuordnung teilen.

IconData contactTypeIcon(ContactType type) => switch (type) {
      ContactType.customer => Icons.person_outline,
      ContactType.supplier => Icons.local_shipping_outlined,
      ContactType.wholesaler => Icons.warehouse_outlined,
      ContactType.company => Icons.handshake_outlined,
      ContactType.serviceProvider => Icons.handyman_outlined,
      ContactType.authority => Icons.account_balance_outlined,
      ContactType.landlord => Icons.home_work_outlined,
      ContactType.bankInsurance => Icons.account_balance_wallet_outlined,
      ContactType.taxAdvisor => Icons.calculate_outlined,
      ContactType.other => Icons.contacts_outlined,
    };

AppStatusTone contactTypeTone(ContactType type) => switch (type) {
      ContactType.customer => AppStatusTone.primary,
      ContactType.supplier => AppStatusTone.info,
      ContactType.wholesaler => AppStatusTone.info,
      ContactType.company => AppStatusTone.secondary,
      ContactType.serviceProvider => AppStatusTone.tertiary,
      ContactType.authority => AppStatusTone.warning,
      ContactType.landlord => AppStatusTone.secondary,
      ContactType.bankInsurance => AppStatusTone.success,
      ContactType.taxAdvisor => AppStatusTone.tertiary,
      ContactType.other => AppStatusTone.neutral,
    };
