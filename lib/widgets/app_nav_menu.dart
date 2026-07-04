import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/theme_extensions.dart';
import '../ui/app_hero_card.dart';
import '../ui/app_quick_action.dart';

/// Inhalt des Slide-in-Navigationsmenüs (Signal-Teal-Redesign / V2). Wird im
/// `HomeScreen` als `Scaffold.drawer` (mobil, von links) und `Scaffold.endDrawer`
/// (Rail/Desktop, von rechts) verwendet und ersetzt den flachen `_ProfileHubTab`.
///
/// Bewusst **rein präsentational** (keine `Provider`-Zugriffe): Profil-Anzeige,
/// Berechtigungen und die anzuzeigenden Kennzahlen kommen als Parameter herein,
/// Aktionen als Callbacks. So ist das Menü isoliert (ohne Provider-Stack)
/// testbar; die Shell liefert Daten + Drawer-schließen-dann-pushen-Verhalten.
///
/// Gruppierung (behebt die zuvor flache, ununterscheidbare Kachel-Verteilung):
/// **Auswertungen** (`canViewReports`) · **Verwaltung** (Team `isAdmin`, Waren
/// `canViewInventory`) · **App** (Einstellungen, immer) · Footer Abmelden.
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
    required this.onOpenTeam,
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
  final VoidCallback onOpenTeam;
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

  /// Ob der Scanner-Eintrag gezeigt wird. Die „nur Handy"-Entscheidung
  /// (Plattform + Breite) trifft die Shell und reicht das Ergebnis hier herein —
  /// das Menü bleibt rein präsentational.
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
    final areaItems = <Widget>[
      if (canViewTimeTracking)
        AppQuickActionTile(
          icon: Icons.schedule_outlined,
          title: 'Zeit',
          subtitle: 'Arbeitszeiten erfassen & Stempeluhr',
          onTap: onOpenTime,
        ),
      if (canViewContacts)
        AppQuickActionTile(
          icon: Icons.contacts_outlined,
          title: 'Kontakte',
          subtitle: 'Kunden, Lieferanten & Partner',
          onTap: onOpenContacts,
        ),
      if (canViewInventory)
        AppQuickActionTile(
          icon: Icons.storefront_outlined,
          title: 'Laden',
          subtitle: 'Laden-Übersicht & Geschäftsbereiche',
          onTap: onOpenShop,
        ),
    ];

    final reportItems = <Widget>[
      if (canViewReports) ...[
        AppQuickActionTile(
          icon: Icons.description_outlined,
          title: 'Monatsbericht',
          subtitle: 'Eigene Stunden oder Team-Bericht als PDF',
          onTap: onOpenMonthReport,
        ),
        AppQuickActionTile(
          icon: Icons.analytics_outlined,
          title: 'Statistiken',
          subtitle: 'Monats- und Jahresauswertungen einsehen',
          onTap: onOpenStatistics,
        ),
      ],
    ];

    final manageItems = <Widget>[
      if (isAdmin)
        AppQuickActionTile(
          icon: Icons.badge_outlined,
          title: 'Personal',
          subtitle: 'Aufträge, Gehälter, Finanzen & Statistiken',
          onTap: onOpenPersonal,
        ),
      if (isAdmin)
        AppQuickActionTile(
          icon: Icons.account_balance_outlined,
          title: 'Buchhaltung',
          subtitle: 'Kostenstellen, Buchungen, Budgets & DATEV',
          onTap: onOpenFinance,
        ),
      if (isAdmin)
        AppQuickActionTile(
          icon: Icons.groups_outlined,
          title: 'Teamverwaltung',
          subtitle: 'Mitarbeiter, Standorte und Rollen pflegen',
          onTap: onOpenTeam,
        ),
      if (canViewInventory)
        AppQuickActionTile(
          icon: Icons.inventory_2_outlined,
          title: 'Warenwirtschaft',
          subtitle: 'Bestand, Lieferanten und Bestellungen',
          onTap: onOpenInventory,
        ),
      if (showScanner && canManageInventory)
        AppQuickActionTile(
          icon: Icons.qr_code_scanner_outlined,
          title: 'Scanner',
          subtitle: 'Artikel per Barcode finden und buchen',
          onTap: onOpenScanner,
        ),
      if (canViewInventory)
        AppQuickActionTile(
          icon: Icons.shopping_bag_outlined,
          title: 'Kundenbestellungen',
          subtitle: 'Sonderbestellungen von Kunden verwalten',
          onTap: onOpenCustomerOrders,
        ),
      if (canViewInventory)
        AppQuickActionTile(
          icon: Icons.insights_outlined,
          title: 'Bestell-Auswertung',
          subtitle: 'Wie oft welcher Artikel bestellt wird',
          onTap: onOpenOrderAnalytics,
        ),
    ];

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(spacing.md),
        children: [
          _ProfileHeader(
            user: user,
            siteName: siteName,
            dailyHours: dailyHours,
            vacationDays: vacationDays,
          ),
          SizedBox(height: spacing.lg),
          if (showAreas && areaItems.isNotEmpty) ...[
            _MenuGroup(title: 'Bereiche', children: areaItems),
            SizedBox(height: spacing.md),
          ],
          if (reportItems.isNotEmpty) ...[
            _MenuGroup(title: 'Auswertungen', children: reportItems),
            SizedBox(height: spacing.md),
          ],
          if (manageItems.isNotEmpty) ...[
            _MenuGroup(title: 'Verwaltung', children: manageItems),
            SizedBox(height: spacing.md),
          ],
          _MenuGroup(
            title: 'App',
            children: [
              if (onOpenMeineAkte != null)
                AppQuickActionTile(
                  icon: Icons.badge_outlined,
                  title: 'Meine Akte',
                  subtitle: 'Eigene Stammdaten, Urlaub & Dokumente',
                  onTap: onOpenMeineAkte!,
                ),
              AppQuickActionTile(
                icon: Icons.settings_outlined,
                title: 'Einstellungen',
                subtitle: 'Profil, Theme und Standardwerte ändern',
                onTap: onOpenSettings,
              ),
              if (onOpenKnowledge != null)
                AppQuickActionTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Wissen & Hilfe',
                  subtitle: 'Anleitungen zu jedem Bereich der App',
                  onTap: onOpenKnowledge!,
                ),
            ],
          ),
          SizedBox(height: spacing.lg),
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
  });

  final AppUserProfile? user;
  final String? siteName;
  final double? dailyHours;
  final int? vacationDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final name = user?.displayName ?? 'Profil';
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return AppHeroCard(
      tone: AppHeroTone.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                child: Text(
                  initial,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: spacing.xxs),
                    Text(
                      user?.role.label ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              _HeaderChip(
                icon: Icons.storefront_outlined,
                label: (siteName == null || siteName!.trim().isEmpty)
                    ? 'Kein Stammstandort'
                    : siteName!,
              ),
              if (dailyHours != null)
                _HeaderChip(
                  icon: Icons.schedule_outlined,
                  label: '${dailyHours!.toStringAsFixed(1)} h Soll/Tag',
                ),
              if (vacationDays != null)
                _HeaderChip(
                  icon: Icons.beach_access_outlined,
                  label: '$vacationDays Urlaubstage',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pillen-Chip wie [InfoChip], aber mit ellipsierendem Text (`Flexible`) — der
/// Profil-Header steht im schmalen Drawer (~270–304px), wo lange Standortnamen
/// sonst überlaufen. `Flexible` ist hier sicher, da der Chip ausschliesslich im
/// `Wrap` (gebundene maxWidth) verwendet wird.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing.sm),
          children[i],
        ],
      ],
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
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onSignOut,
        icon: const Icon(Icons.logout),
        label: Text(authDisabled ? 'Profil wechseln' : 'Abmelden'),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.errorContainer,
          foregroundColor: colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
