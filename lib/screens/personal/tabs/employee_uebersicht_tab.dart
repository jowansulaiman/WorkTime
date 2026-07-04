import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/app_user.dart';
import '../../../models/employee_profile.dart';
import '../../../providers/personal_provider.dart';
import '../../../ui/ui.dart';
import '../../../widgets/info_row.dart';
import '../../../widgets/summary_card_row.dart';

/// Übersicht-Tab der Mitarbeiter-Detailseite — **AllTec-1:1** (`employee_overview_tab`):
/// Status-Badges, vier KPI-Zählkarten (Quali/Ausbildung/Kinder/Dokumente) und
/// darunter thematisch gruppierte Info-Karten. Rein lesend; Bearbeitung läuft
/// über die Fach-Tabs (Stammdaten/Gehalt/…). „Letzte Notizen" folgt mit M8.
class EmployeeUebersichtTab extends StatelessWidget {
  const EmployeeUebersichtTab({
    super.key,
    required this.userId,
    required this.member,
  });

  final String userId;
  final AppUserProfile? member;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final profile = personal.employeeProfileForUser(userId);
    final df = DateFormat('dd.MM.yyyy', 'de_DE');

    final qualis = personal.qualificationsForUser(userId).length;
    final ausbildungen = personal.ausbildungenForUser(userId).length;
    final kinder = personal.childrenForUser(userId).length;
    final dokumente = personal.documentsForUser(userId).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusBadges(profile: profile, memberActive: member?.isActive ?? true),
        const SizedBox(height: 16),
        SummaryCardRow(
          items: [
            SummaryCardItem(
              label: 'Qualifikationen',
              value: '$qualis',
              icon: Icons.verified_outlined,
            ),
            SummaryCardItem(
              label: 'Ausbildungen',
              value: '$ausbildungen',
              icon: Icons.school_outlined,
            ),
            SummaryCardItem(
              label: 'Kinder',
              value: '$kinder',
              icon: Icons.child_care_outlined,
            ),
            SummaryCardItem(
              label: 'Dokumente',
              value: '$dokumente',
              icon: Icons.folder_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (profile == null)
          const EmptyState(
            icon: Icons.badge_outlined,
            title: 'Noch keine Stammakte',
            message: 'Für diesen Mitarbeiter ist noch keine Personalakte '
                'hinterlegt. Über den Tab „Stammdaten" anlegen.',
          )
        else ...[
          AppSectionCard(
            title: 'Persönliche Daten',
            icon: Icons.person_outline,
            child: Column(
              children: [
                InfoRow(label: 'Personalnummer', value: _v(profile.personnelNumber)),
                InfoRow(
                  label: 'Geburtsdatum',
                  value: profile.birthDate != null
                      ? df.format(profile.birthDate!)
                      : '—',
                ),
                InfoRow(label: 'Nationalität', value: _v(profile.nationality)),
                InfoRow(
                  label: 'Familienstand',
                  value: profile.maritalStatus?.label ?? '—',
                ),
                InfoRow(label: 'Status', value: profile.status.label),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            title: 'Anschrift',
            icon: Icons.home_outlined,
            child: Column(
              children: [
                InfoRow(
                  label: 'Straße',
                  value: _join([profile.street, profile.houseNumber], ' '),
                ),
                InfoRow(
                  label: 'PLZ / Ort',
                  value: _join([profile.postalCode, profile.city], ' '),
                ),
                if (profile.addressExtra != null &&
                    profile.addressExtra!.isNotEmpty)
                  InfoRow(label: 'Zusatz', value: profile.addressExtra!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            title: 'Beschäftigung',
            icon: Icons.work_outline,
            child: Column(
              children: [
                InfoRow(
                  label: 'Eintritt',
                  value: profile.hireDate != null
                      ? df.format(profile.hireDate!)
                      : '—',
                ),
                InfoRow(
                  label: 'Probezeit bis',
                  value: profile.probationEnd != null
                      ? df.format(profile.probationEnd!)
                      : '—',
                ),
                InfoRow(
                  label: 'Befristet bis',
                  value: profile.limitedUntil != null
                      ? df.format(profile.limitedUntil!)
                      : '—',
                ),
                InfoRow(
                  label: 'Austritt',
                  value: profile.exitDate != null
                      ? df.format(profile.exitDate!)
                      : '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            title: 'Kontakt',
            icon: Icons.contact_mail_outlined,
            child: Column(
              children: [
                InfoRow(label: 'Dienstlich (E-Mail)', value: _v(member?.email)),
                InfoRow(label: 'Telefon (privat)', value: _v(profile.privatePhone)),
                InfoRow(label: 'Mobil (privat)', value: _v(profile.privateMobile)),
                InfoRow(label: 'E-Mail (privat)', value: _v(profile.privateEmail)),
              ],
            ),
          ),
        ],
        if (personal.notesForUser(userId).isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionCard(
            title: 'Letzte Notizen',
            icon: Icons.note_outlined,
            child: Column(
              children: [
                for (final n in personal.notesForUser(userId).take(3))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: Text(n.text),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _v(String? value) =>
      (value == null || value.trim().isEmpty) ? '—' : value.trim();

  static String _join(List<String?> parts, String sep) {
    final joined = parts
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .join(sep);
    return joined.isEmpty ? '—' : joined;
  }
}

/// Reihe aus Status-Badges (Beschäftigungsstatus + Inaktiv), tonbasiert.
class _StatusBadges extends StatelessWidget {
  const _StatusBadges({required this.profile, required this.memberActive});

  final EmployeeProfile? profile;
  final bool memberActive;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    if (profile != null) {
      badges.add(AppStatusBadge(
        label: profile!.status.label,
        tone: _statusTone(profile!.status),
      ));
      if (profile!.limitedUntil != null) {
        badges.add(const AppStatusBadge(label: 'Befristet', tone: AppStatusTone.info));
      }
    } else {
      badges.add(AppStatusBadge(
        label: memberActive ? 'Aktiv' : 'Inaktiv',
        tone: memberActive ? AppStatusTone.success : AppStatusTone.neutral,
      ));
    }
    if (!memberActive) {
      badges.add(const AppStatusBadge(label: 'Zugang inaktiv', tone: AppStatusTone.neutral));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: badges);
  }

  static AppStatusTone _statusTone(EmployeeStatus status) => switch (status) {
        EmployeeStatus.aktiv => AppStatusTone.success,
        EmployeeStatus.probezeit => AppStatusTone.warning,
        EmployeeStatus.gekuendigt => AppStatusTone.error,
        EmployeeStatus.ausgeschieden => AppStatusTone.neutral,
        EmployeeStatus.ruhend => AppStatusTone.info,
      };
}
