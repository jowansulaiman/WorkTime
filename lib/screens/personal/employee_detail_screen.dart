import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/employee_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/personal_provider.dart';
import '../../providers/team_provider.dart';
import '../../ui/ui.dart';
import 'tabs/employee_ausbildungen_tab.dart';
import 'tabs/employee_dokumente_tab.dart';
import 'tabs/employee_gehalt_tab.dart';
import 'tabs/employee_kinder_tab.dart';
import 'tabs/employee_notizen_tab.dart';
import 'tabs/employee_qualifikationen_tab.dart';
import 'tabs/employee_stammdaten_tab.dart';
import 'tabs/employee_uebersicht_tab.dart';
import 'tabs/employee_verwalten_tab.dart';

/// Mitarbeiter-Detailseite — **AllTec-1:1**: Kopf-Visitenkarte + eine scrollbare
/// TabBar mit 9 Tabs (Icon + Text), analog `EmployeeDetailPage` aus AllTec.
///
/// Deep-linkbar über `/personal/{uid}` (admin-only — gated in
/// [RoutePermissions.isLocationAllowed] per `/personal/`-Prefix und im
/// `_gateRedirect`). Die Tab-Inhalte werden in den Meilensteinen M4–M9 gefüllt;
/// dieses Gerüst liefert Kopf, Navigation und Lade-/Not-Found-Zustände.
/// Vollständiger Fahrplan: `plan/personal-alltec-1zu1.md`.
class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({
    super.key,
    required this.userId,
    this.parentLabel = 'Personal',
  });

  /// uid des Mitarbeiters (Path-Parameter `:id`).
  final String userId;

  /// Rücksprung-Beschriftung im Breadcrumb (Standard: die Personal-Liste).
  final String parentLabel;

  /// Tab-Reihenfolge **exakt wie AllTec** (`employee_detail_page.dart`).
  static const List<_DetailTab> _tabs = <_DetailTab>[
    _DetailTab('Übersicht', Icons.dashboard_outlined),
    _DetailTab('Stammdaten', Icons.person_outlined),
    _DetailTab('Gehalt', Icons.euro_outlined),
    _DetailTab('Qualifikationen', Icons.verified_outlined),
    _DetailTab('Ausbildungen', Icons.school_outlined),
    _DetailTab('Kinder', Icons.child_care_outlined),
    _DetailTab('Dokumente', Icons.folder_outlined),
    _DetailTab('Notizen', Icons.note_outlined),
    _DetailTab('Verwalten', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final viewer = context.watch<AuthProvider>().profile;
    final team = context.watch<TeamProvider>();
    final personal = context.watch<PersonalProvider>();

    final breadcrumbs = <BreadcrumbItem>[
      BreadcrumbItem(
        label: parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Mitarbeiter'),
    ];

    // Admin-Gate (spiegelt das URL-Gate; schützt auch den imperativen Push).
    if (viewer == null || !viewer.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }

    final AppUserProfile? member = _memberFor(team.members, userId);
    final EmployeeProfile? empProfile = personal.employeeProfileForUser(userId);

    // Cold-Start / Deep-Link: Stammdaten evtl. noch nicht geladen
    // (updateSession ist fire-and-forget) → Lade- statt Not-Found-Zustand.
    if (member == null && empProfile == null) {
      if (team.members.isEmpty) {
        return Scaffold(
          appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Mitarbeiter nicht gefunden',
          message: 'Zu dieser Kennung existiert kein Mitarbeiter in dieser '
              'Organisation.',
        ),
      );
    }

    final name = member?.displayName ?? 'Mitarbeiter';

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: <BreadcrumbItem>[
            BreadcrumbItem(
              label: parentLabel,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            BreadcrumbItem(label: name),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _EmployeeVCard(member: member, name: name),
            ),
            TabBar(
              isScrollable: true,
              tabs: [
                for (final t in _tabs) Tab(icon: Icon(t.icon), text: t.label),
              ],
            ),
            Expanded(
              child: TabBarView(
                // Reihenfolge exakt wie _tabs / AllTec. Gefüllte Tabs (M4):
                // Übersicht, Kinder, Dokumente; der Rest folgt in M5–M9.
                children: [
                  EmployeeUebersichtTab(userId: userId, member: member),
                  EmployeeStammdatenTab(userId: userId),
                  EmployeeGehaltTab(userId: userId),
                  EmployeeQualifikationenTab(userId: userId),
                  EmployeeAusbildungenTab(userId: userId),
                  EmployeeKinderTab(userId: userId),
                  EmployeeDokumenteTab(userId: userId),
                  EmployeeNotizenTab(userId: userId),
                  EmployeeVerwaltenTab(userId: userId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static AppUserProfile? _memberFor(List<AppUserProfile> members, String uid) {
    for (final m in members) {
      if (m.uid == uid) return m;
    }
    return null;
  }
}

/// Ein Tab-Deskriptor (Beschriftung + Icon), 1:1 zu AllTecs `Tab(icon:, text:)`.
class _DetailTab {
  const _DetailTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Kompakte Visitenkarte des Mitarbeiters (analog AllTec `_EmployeeVCard`):
/// Avatar mit Initialen, Name, Rolle und Kontakt-/Status-Zeile.
class _EmployeeVCard extends StatelessWidget {
  const _EmployeeVCard({required this.member, required this.name});

  final AppUserProfile? member;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = member?.isActive ?? true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: member?.photoUrl != null
                  ? NetworkImage(member!.photoUrl!)
                  : null,
              child: member?.photoUrl == null
                  ? Text(_initials(name), style: theme.textTheme.titleLarge)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleLarge),
                  if (member?.email.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.email_outlined,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              member!.email,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppStatusBadge(
              label: active ? 'Aktiv' : 'Inaktiv',
              tone: active ? AppStatusTone.success : AppStatusTone.neutral,
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String value) {
    final parts =
        value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}
