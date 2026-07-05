import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/app_user.dart';
import '../../../models/employee_profile.dart';
import '../../../providers/personal_provider.dart';
import '../../../providers/team_provider.dart';
import '../../../ui/ui.dart';
import '../../../widgets/info_row.dart';
import '../../team_management_screen.dart'
    show showMemberConfigurationSheet, showShiftPreferenceSheet;

/// Verwalten-Tab der Mitarbeiter-Detailseite — **AllTec-1:1**
/// (`employee_manage_tab`): (1) Aktiv-Status umschalten + Beschäftigungsstatus,
/// (2) Gefahrenzone, (3) technische Meta-IDs.
///
/// **WorkTime-Entscheidung:** „Mitarbeiter löschen" = **Deaktivieren-Alias**
/// (`TeamProvider.updateMember(isActive:false)`) — ein Mitarbeiter ist ein
/// Auth-gebundenes Login (users-Doc), kein reines HR-Objekt; sicher & reversibel.
class EmployeeVerwaltenTab extends StatelessWidget {
  const EmployeeVerwaltenTab({super.key, required this.userId});

  final String userId;

  static final _df = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final personal = context.watch<PersonalProvider>();

    AppUserProfile? member;
    for (final m in team.members) {
      if (m.uid == userId) {
        member = m;
        break;
      }
    }
    if (member == null) {
      return const EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Mitarbeiter nicht gefunden',
        message: 'Zu dieser Kennung existiert kein Mitarbeiter.',
      );
    }
    final m = member;
    final profile = personal.employeeProfileForUser(userId);
    final status = (profile ?? EmployeeProfile(orgId: '', userId: userId)).status;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Status & Zugang ─────────────────────────────────────────────
        AppSectionCard(
          title: 'Status & Zugang',
          icon: Icons.manage_accounts_outlined,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Zugang aktiv'),
                subtitle: const Text('Steuert Login & Sichtbarkeit'),
                value: m.isActive,
                onChanged: (v) =>
                    team.updateMember(m.copyWith(isActive: v)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<EmployeeStatus>(
                initialValue: status,
                decoration:
                    const InputDecoration(labelText: 'Beschäftigungsstatus'),
                items: [
                  for (final s in EmployeeStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) {
                  if (v == null || v == status) return;
                  final base =
                      profile ?? EmployeeProfile(orgId: '', userId: userId);
                  personal.saveEmployeeProfile(base.copyWith(status: v));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Rolle, Vertrag & Standorte (aus der aufgelösten Teamverwaltung;
        // öffnet die bewährten Editor-Sheets aus team_management_screen.dart) ──
        AppSectionCard(
          title: 'Rolle, Vertrag & Standorte',
          icon: Icons.badge_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rolle & Rechte, Arbeitsvertrag, Standort-Zuordnung und '
                'Qualifikationen dieses Mitarbeiters bearbeiten.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Konfiguration bearbeiten'),
                    onPressed: () => showMemberConfigurationSheet(context, m),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Schicht-Vorlieben'),
                    onPressed: () => showShiftPreferenceSheet(context, m),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ── Offboarding (PA-7.3): erscheint, sobald der Beschäftigungsstatus
        // nicht mehr „laufend" ist oder ein Austrittsdatum gesetzt wurde. ──
        if (!status.isCurrent || profile?.exitDate != null) ...[
          const SizedBox(height: 12),
          _OffboardingCard(member: m, profile: profile),
        ],
        const SizedBox(height: 12),
        // ── Gefahrenzone ────────────────────────────────────────────────
        AppSectionCard(
          title: 'Gefahrenzone',
          icon: Icons.warning_amber_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ein Mitarbeiter ist mit einem Login verknüpft und wird nicht '
                'endgültig gelöscht, sondern deaktiviert. Der Zugang bleibt '
                'erhalten und kann jederzeit reaktiviert werden.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.person_off_outlined),
                  label: Text(m.isActive
                      ? 'Mitarbeiter deaktivieren'
                      : 'Bereits deaktiviert'),
                  onPressed: !m.isActive
                      ? null
                      : () async {
                          final ok = await AppConfirmDialog.show(
                            context,
                            title: 'Mitarbeiter deaktivieren',
                            message:
                                '„${m.displayName}" deaktivieren? Der Login '
                                'bleibt bestehen und kann jederzeit wieder '
                                'aktiviert werden.',
                            confirmLabel: 'Deaktivieren',
                            icon: Icons.person_off_outlined,
                          );
                          if (ok) {
                            await team.updateMember(m.copyWith(isActive: false));
                          }
                        },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Technische Infos ────────────────────────────────────────────
        AppSectionCard(
          title: 'Technische Infos',
          icon: Icons.info_outline,
          child: Column(
            children: [
              InfoRow(label: 'Benutzer-ID', value: m.uid),
              InfoRow(label: 'Org-ID', value: m.orgId),
              InfoRow(label: 'Profil-ID', value: profile?.id ?? '—'),
              InfoRow(
                label: 'Erstellt am',
                value: profile?.createdAt != null
                    ? _df.format(profile!.createdAt!)
                    : '—',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Offboarding-Checkliste (PA-7.3): geführte Schritte beim Austritt —
/// Zugang deaktivieren (sperrt Login + entfernt aus Planung/Autoplan über die
/// bestehende `isActive`-Kopplung), Kiosk-PIN zurücksetzen, und der Hinweis auf
/// die DSGVO-Aufbewahrung der Dokumente (PA-8.1). Kein Auto-Vollzug — jeder
/// Schritt bleibt eine bewusste Admin-Aktion.
class _OffboardingCard extends StatefulWidget {
  const _OffboardingCard({required this.member, required this.profile});

  final AppUserProfile member;
  final EmployeeProfile? profile;

  @override
  State<_OffboardingCard> createState() => _OffboardingCardState();
}

class _OffboardingCardState extends State<_OffboardingCard> {
  bool _pinBusy = false;
  bool _pinDone = false;

  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();
    final personal = context.watch<PersonalProvider>();
    final theme = Theme.of(context);
    final m = team.members.firstWhere(
      (e) => e.uid == widget.member.uid,
      orElse: () => widget.member,
    );
    final exit = widget.profile?.exitDate;
    final docs = personal.documentsForUser(m.uid);
    final abgelaufen =
        docs.where((d) => d.retentionExpired(DateTime.now())).length;

    Widget step({
      required bool done,
      required String title,
      required String subtitle,
      Widget? action,
    }) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done
                ? theme.appColors.success
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: action,
        );

    return AppSectionCard(
      title: 'Offboarding',
      icon: Icons.logout_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exit != null
                ? 'Austritt zum ${_dateFmt.format(exit)}.'
                : 'Beschäftigungsverhältnis ist nicht mehr laufend.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          step(
            done: !m.isActive,
            title: 'Zugang deaktivieren',
            subtitle: m.isActive
                ? 'Sperrt Login, Planung und Kiosk-Anmeldung.'
                : 'Zugang ist deaktiviert.',
            action: m.isActive
                ? FilledButton.tonal(
                    onPressed: () =>
                        team.updateMember(m.copyWith(isActive: false)),
                    child: const Text('Deaktivieren'),
                  )
                : null,
          ),
          step(
            done: _pinDone,
            title: 'Kiosk-PIN zurücksetzen',
            subtitle: _pinDone
                ? 'PIN wurde gelöscht.'
                : 'Löscht die Tablet-Anmelde-PIN (Cloud-Modus).',
            action: _pinDone
                ? null
                : OutlinedButton(
                    onPressed: _pinBusy ? null : () => _resetPin(personal),
                    child: _pinBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Zurücksetzen'),
                  ),
          ),
          step(
            done: docs.isEmpty,
            title: 'Dokumente & Aufbewahrung (DSGVO)',
            subtitle: docs.isEmpty
                ? 'Keine Dokumente in der Akte.'
                : '${docs.length} Dokument(e) in der Akte'
                    '${abgelaufen > 0 ? ' — $abgelaufen mit abgelaufener Aufbewahrungsfrist (im Dokumente-Tab löschen)' : ' — Aufbewahrungsfristen laufen weiter'}.',
          ),
        ],
      ),
    );
  }

  Future<void> _resetPin(PersonalProvider personal) async {
    setState(() => _pinBusy = true);
    try {
      await personal.resetKioskPinFor(widget.member.uid);
      if (mounted) setState(() => _pinDone = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PIN-Reset fehlgeschlagen: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pinBusy = false);
    }
  }
}
