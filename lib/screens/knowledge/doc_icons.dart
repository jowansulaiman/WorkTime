import 'package:flutter/material.dart';

/// Loest die im `docs/manifest.json` hinterlegten Icon-Namen auf feste
/// [IconData] auf. Bewusst eine explizite Map (kein `IconData(codePoint)`),
/// damit der Flutter-Tree-Shaker die Icons behalten kann.
IconData docIcon(String name) {
  switch (name) {
    case 'rocket_launch':
      return Icons.rocket_launch_outlined;
    case 'today':
      return Icons.today_outlined;
    case 'schedule':
      return Icons.schedule_outlined;
    case 'calendar_month':
      return Icons.calendar_month_outlined;
    case 'notifications':
      return Icons.notifications_outlined;
    case 'contacts':
      return Icons.contacts_outlined;
    case 'storefront':
      return Icons.storefront_outlined;
    case 'point_of_sale':
      return Icons.point_of_sale_outlined;
    case 'lock':
      return Icons.lock_outline;
    case 'tablet_mac':
      return Icons.tablet_mac_outlined;
    case 'badge':
      return Icons.badge_outlined;
    case 'person':
      return Icons.person_outline;
    case 'public':
      return Icons.public_outlined;
    case 'architecture':
      return Icons.architecture_outlined;
    case 'security':
      return Icons.security_outlined;
    case 'functions':
      return Icons.functions_outlined;
    case 'verified':
      return Icons.verified_outlined;
    case 'menu_book':
    default:
      return Icons.menu_book_outlined;
  }
}
