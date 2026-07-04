import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/app_user.dart';
import '../../../models/employee_profile.dart';
import '../../../providers/personal_provider.dart';
import '../../../providers/team_provider.dart';
import '../../../ui/ui.dart';
import '../../../widgets/info_row.dart';

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
