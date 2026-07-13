import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/theme_extensions.dart';

/// Inhalt des Slide-in-Navigationsmenüs (Signal-Teal-Redesign / V2). Wird im
/// `HomeScreen` als `Scaffold.drawer` (mobil, von links) und `Scaffold.endDrawer`
/// (Rail/Desktop, von rechts) verwendet und ersetzt den flachen `_ProfileHubTab`.
///
/// Bewusst **rein präsentational** (keine `Provider`-Zugriffe): Profil-Anzeige,
/// Berechtigungen und die anzuzeigenden Kennzahlen kommen als Parameter herein,
/// Aktionen als Callbacks. So ist das Menü isoliert (ohne Provider-Stack)
/// testbar; die Shell liefert Daten + Drawer-schließen-dann-pushen-Verhalten.
///
/// Klare Hierarchie statt einer langen Folge gleich gewichteter Karten:
/// **Arbeitsbereiche** · **Laden & Bestand** · **Verwaltung** ·
/// **Auswertungen** · **Konto & Hilfe**. Abmelden bleibt unabhängig von der
/// Scrollposition erreichbar.
class AppNavMenu extends StatelessWidget {
  const AppNavMenu({
    super.key,
    required this.user,
    required this.authDisabled,
    required this.onSignOut,
    required this.onOpenTime,
    required this.onOpenContacts,
    required this.onOpenShop,
    required this.onOpenMonthReport,
    required this.onOpenStatistics,
    required this.onOpenPersonal,
    required this.onOpenFinance,
    required this.onOpenInventory,
    required this.onOpenCustomerOrders,
    required this.onOpenOrderAnalytics,
    required this.onOpenScanner,
    required this.onOpenSettings,
    this.onOpenMeineAkte,
    this.onOpenKnowledge,
    this.showScanner = false,
    this.showAreas = false,
    this.siteName,
    this.dailyHours,
    this.vacationDays,
    this.selectedArea,
    this.onClose,
  });

  final AppUserProfile? user;
  final bool authDisabled;

  final VoidCallback onSignOut;

  /// Wechsel auf die aus der Bottomnav ausgelagerten Shell-Tabs (Branch-Wechsel,
  /// kein Push). Nur sichtbar, wenn [showAreas] und das jeweilige Recht passt.
  final VoidCallback onOpenTime;
  final VoidCallback onOpenContacts;
  final VoidCallback onOpenShop;

  final VoidCallback onOpenMonthReport;
  final VoidCallback onOpenStatistics;
  final VoidCallback onOpenPersonal;
  final VoidCallback onOpenFinance;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenCustomerOrders;
  final VoidCallback onOpenOrderAnalytics;
  final VoidCallback onOpenScanner;

  /// „Meine Personalakte" (PA-2.4) – Selbstsicht für jeden Nutzer. Optional
  /// (backward-compatible); nur gezeigt, wenn gesetzt.
  final VoidCallback? onOpenMeineAkte;

  /// „Wissen & Hilfe" (In-App-Doku). Optional (backward-compatible); nur gezeigt,
  /// wenn gesetzt.
  final VoidCallback? onOpenKnowledge;
  final VoidCallback onOpenSettings;

  /// Ob der Scanner-Eintrag gezeigt wird. Die Berechtigungsentscheidung trifft
  /// die Shell und reicht das Ergebnis hier herein — das Menü bleibt rein
  /// präsentational.
  final bool showScanner;

  /// Ob die Gruppe „Bereiche" (Zeit/Kontakte/Laden) gezeigt wird. Diese Tabs
  /// wurden aus der mobilen Bottomnav ausgelagert und sind nur dort nötig; in
  /// der Rail (endDrawer) stehen sie schon in der Seitenleiste → `false`.
  final bool showAreas;

  /// Name des Stammstandorts; `null` → „Kein Stammstandort".
  final String? siteName;

  /// Tägliche Soll-Stunden; `null` blendet den Chip aus.
  final double? dailyHours;

  /// Jahres-Urlaubstage; `null` blendet den Chip aus.
  final int? vacationDays;

  /// Aktiver Hauptbereich im mobilen Drawer (z. B. „Laden"). Rein visuell;
  /// die Navigation bleibt vollständig callback-gesteuert.
  final String? selectedArea;

  /// Optionaler expliziter Schließen-Knopf im Drawer-Kopf.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final isAdmin = user?.isAdmin ?? false;
    final canViewReports = user?.canViewReports ?? false;
    final canViewInventory = user?.canViewInventory ?? false;
    final canManageInventory = user?.canManageInventory ?? false;
    final canViewTimeTracking = user?.canViewTimeTracking ?? false;
    final canViewContacts = user?.canViewContacts ?? false;

    // „Bereiche": die aus der mobilen Bottomnav (Heute · Plan · Scanner ·
    // Anfragen · Mehr) ausgelagerten Tabs. Jeder Eintrag wechselt den Shell-
    // Branch; Sichtbarkeit folgt denselben Rechten wie der jeweilige Tab.
    final areaItems = <_MenuDestination>[
      if (canViewTimeTracking)
        _MenuDestination(
          icon: Icons.schedule_outlined,
          title: 'Zeit',
          subtitle: 'Arbeitszeiten erfassen & Stempeluhr',
          onTap: onOpenTime,
        ),
      if (canViewContacts)
        _MenuDestination(
          icon: Icons.contacts_outlined,
          title: 'Kontakte',
          subtitle: 'Kunden, Lieferanten & Partner',
          onTap: onOpenContacts,
        ),
      if (canViewInventory)
        _MenuDestination(
          icon: Icons.storefront_outlined,
          title: 'Laden',
          subtitle: 'Tagesgeschäft, Kasse & Verwaltung',
          onTap: onOpenShop,
        ),
    ];

    final reportItems = <_MenuDestination>[
      if (canViewReports) ...[
        _MenuDestination(
          icon: Icons.description_outlined,
          title: 'Monatsbericht',
          subtitle: 'Eigene Stunden oder Team-Bericht als PDF',
          onTap: onOpenMonthReport,
        ),
        _MenuDestination(
          icon: Icons.analytics_outlined,
          title: 'Statistiken',
          subtitle: 'Monats- und Jahresauswertungen einsehen',
          onTap: onOpenStatistics,
        ),
      ],
    ];

    final shopItems = <_MenuDestination>[
      if (canViewInventory)
        _MenuDestination(
          icon: Icons.inventory_2_outlined,
          title: 'Warenwirtschaft',
          subtitle: 'Bestand, Lieferanten und Bestellungen',
          onTap: onOpenInventory,
        ),
      if (showScanner && canManageInventory)
        _MenuDestination(
          icon: Icons.qr_code_scanner_outlined,
          title: 'Scanner',
          subtitle: 'Artikel per Barcode finden und buchen',
          onTap: onOpenScanner,
        ),
      if (canViewInventory)
        _MenuDestination(
          icon: Icons.shopping_bag_outlined,
          title: 'Kundenbestellungen',
          subtitle: 'Sonderbestellungen verwalten',
          onTap: onOpenCustomerOrders,
        ),
      if (canViewInventory)
        _MenuDestination(
          icon: Icons.insights_outlined,
          title: 'Bestell-Auswertung',
          subtitle: 'Bestellhäufigkeit nach Zeitraum',
          onTap: onOpenOrderAnalytics,
        ),
    ];

    final manageItems = <_MenuDestination>[
      if (isAdmin)
        _MenuDestination(
          icon: Icons.badge_outlined,
          title: 'Personal',
          subtitle: 'Aufträge, Gehälter, Finanzen & Statistiken',
          onTap: onOpenPersonal,
        ),
      if (isAdmin)
        _MenuDestination(
          icon: Icons.account_balance_outlined,
          title: 'Buchhaltung',
          subtitle: 'Kostenstellen, Buchungen, Budgets & DATEV',
          onTap: onOpenFinance,
        ),
    ];

    final accountItems = <_MenuDestination>[
      if (onOpenMeineAkte != null)
        _MenuDestination(
          icon: Icons.account_box_outlined,
          title: 'Meine Akte',
          subtitle: 'Stammdaten, Urlaub & Dokumente',
          onTap: onOpenMeineAkte!,
        ),
      _MenuDestination(
        icon: Icons.settings_outlined,
        title: 'Einstellungen',
        subtitle: 'Profil, Darstellung und Standardwerte',
        onTap: onOpenSettings,
      ),
      if (onOpenKnowledge != null)
        _MenuDestination(
          icon: Icons.menu_book_outlined,
          title: 'Wissen & Hilfe',
          subtitle: 'Anleitungen zu allen Bereichen',
          onTap: onOpenKnowledge!,
        ),
    ];

    return SafeArea(
      child: Column(
        children: [
          _ProfileHeader(
            user: user,
            siteName: siteName,
            dailyHours: dailyHours,
            vacationDays: vacationDays,
            onClose: onClose,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                spacing.xs,
                spacing.md,
                spacing.lg,
              ),
              children: [
                if (showAreas && areaItems.isNotEmpty) ...[
                  _MenuGroup(
                    title: 'Arbeitsbereiche',
                    items: areaItems,
                    selectedTitle: selectedArea,
                    emphasized: true,
                  ),
                  SizedBox(height: spacing.lg),
                ],
                if (shopItems.isNotEmpty) ...[
                  _MenuGroup(title: 'Laden & Bestand', items: shopItems),
                  SizedBox(height: spacing.lg),
                ],
                if (manageItems.isNotEmpty) ...[
                  _MenuGroup(title: 'Verwaltung', items: manageItems),
                  SizedBox(height: spacing.lg),
                ],
                if (reportItems.isNotEmpty) ...[
                  _MenuGroup(title: 'Auswertungen', items: reportItems),
                  SizedBox(height: spacing.lg),
                ],
                _MenuGroup(title: 'Konto & Hilfe', items: accountItems),
              ],
            ),
          ),
          _SignOutButton(authDisabled: authDisabled, onSignOut: onSignOut),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.siteName,
    required this.dailyHours,
    required this.vacationDays,
    required this.onClose,
  });

  final AppUserProfile? user;
  final String? siteName;
  final double? dailyHours;
  final int? vacationDays;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final name = user?.displayName ?? 'Profil';
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    final hasWorkDetails = dailyHours != null || vacationDays != null;
    final workDetails = <String>[
      if (dailyHours != null)
        '${dailyHours!.toStringAsFixed(1).replaceAll('.', ',')} h Soll/Tag',
      if (vacationDays != null) '$vacationDays Urlaubstage',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.md,
        spacing.md,
        spacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Menü',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: 'Menü schließen',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          SizedBox(height: spacing.s12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(spacing.s12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(context.radii.lg),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: Text(
                    initial,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: spacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: spacing.xxs),
                      Text(
                        [
                          if ((user?.role.label ?? '').isNotEmpty)
                            user!.role.label,
                          (siteName ?? '').trim().isEmpty
                              ? 'Kein Stammstandort'
                              : siteName!.trim(),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (hasWorkDetails) ...[
                        SizedBox(height: spacing.xs),
                        Text(
                          workDetails,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuDestination {
  const _MenuDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({
    required this.title,
    required this.items,
    this.selectedTitle,
    this.emphasized = false,
  });

  final String title;
  final List<_MenuDestination> items;
  final String? selectedTitle;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: spacing.xs, bottom: spacing.sm),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color:
                emphasized
                    ? colorScheme.primaryContainer.withValues(alpha: 0.18)
                    : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(context.radii.lg),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: spacing.md + 40,
                      endIndent: spacing.s12,
                    ),
                  _MenuTile(
                    item: items[i],
                    selected: items[i].title == selectedTitle,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item, required this.selected});

  final _MenuDestination item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    return ListTile(
      selected: selected,
      selectedTileColor: colorScheme.secondaryContainer.withValues(alpha: 0.65),
      contentPadding: EdgeInsets.symmetric(horizontal: spacing.s12),
      minVerticalPadding: spacing.sm,
      onTap: item.onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color:
              selected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(context.radii.md),
        ),
        child: Icon(
          item.icon,
          color:
              selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          size: context.iconSizes.sm,
        ),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
      subtitle: Text(
        item.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: context.iconSizes.sm,
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.authDisabled, required this.onSignOut});

  final bool authDisabled;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = context.spacing;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: OutlinedButton.icon(
        onPressed: onSignOut,
        icon: const Icon(Icons.logout_rounded),
        label: Text(authDisabled ? 'Profil wechseln' : 'Abmelden'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.error,
          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}
