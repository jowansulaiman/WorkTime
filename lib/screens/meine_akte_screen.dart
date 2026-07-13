import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/employment_contract.dart';
import '../models/payroll_record.dart';
import '../providers/auth_provider.dart';
import '../providers/personal_provider.dart';
import '../providers/team_provider.dart';
import '../services/export_service.dart';
import '../ui/ui.dart';
import '../widgets/employee_documents_card.dart';
import '../widgets/meine_qualifikationen_card.dart';

/// „Meine Personalakte" (PA-2.4) – die Selbstsicht für Mitarbeiter auf ihre
/// EIGENEN Daten: Stammdaten (read-only), Urlaubsanspruch/-rest und Dokumente
/// (ansehen/downloaden). Alle Daten kommen aus den self-scoped Streams des
/// [PersonalProvider] (M7a/PA-2.3/PA-3), abgesichert durch die Self-Read-Rules;
/// Änderungen bleiben der Verwaltung vorbehalten.
class MeineAkteScreen extends StatelessWidget {
  const MeineAkteScreen({super.key, this.parentLabel = 'Profil'});

  final String parentLabel;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final spacing = context.spacing;

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Meine Akte'),
        ],
        actions: [
          if (profile != null)
            IconButton(
              tooltip: 'Meine Daten exportieren (Art. 15 DSGVO)',
              icon: const Icon(Icons.download_for_offline_outlined),
              onPressed: () => _exportSelbstauskunft(context, profile),
            ),
        ],
      ),
      body: profile == null
          ? const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Nicht angemeldet',
              message: 'Bitte melde dich an, um deine Personalakte zu sehen.',
            )
          : ListView(
              padding: MobileBreakpoints.screenPadding(context),
              children: [
                _HeaderCard(name: profile.settings.name.isEmpty
                    ? profile.email
                    : profile.settings.name),
                SizedBox(height: spacing.lg),
                _StammdatenCard(userId: profile.uid),
                SizedBox(height: spacing.lg),
                _UrlaubCard(userId: profile.uid),
                SizedBox(height: spacing.lg),
                _LohnabrechnungenCard(
                  employeeName: profile.settings.name.isEmpty
                      ? profile.email
                      : profile.settings.name,
                ),
                SizedBox(height: spacing.lg),
                MeineQualifikationenCard(userId: profile.uid),
                SizedBox(height: spacing.lg),
                EmployeeDocumentsCard(userId: profile.uid, canManage: false),
                SizedBox(height: spacing.lg),
              ],
            ),
    );
  }
}

/// Art.-15-Selbstauskunft (PA-8.2): sammelt die eigenen, per Self-Read
/// verfügbaren Daten aus den Providern und exportiert sie als PDF.
Future<void> _exportSelbstauskunft(
  BuildContext context,
  AppUserProfile user,
) async {
  final personal = context.read<PersonalProvider>();
  final team = context.read<TeamProvider>();
  final name =
      user.settings.name.isEmpty ? user.email : user.settings.name;
  try {
    await ExportService.exportSelbstauskunftPdf(
      employeeName: name,
      profile: personal.employeeProfileForUser(user.uid),
      contract: team.contracts
          .where((c) => c.userId == user.uid)
          .fold<EmploymentContract?>(
              null,
              (best, c) => best == null || c.validFrom.isAfter(best.validFrom)
                  ? c
                  : best),
      urlaub: personal.urlaubsReportFor(user.uid, DateTime.now().year),
      payrolls: personal.payrollRecords
          .where((r) => r.userId == user.uid)
          .toList(growable: false),
      documents: personal.documentsForUser(user.uid),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export fehlgeschlagen: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return AppHeroCard(
      child: Row(
        children: [
          Icon(Icons.badge_outlined,
              color: theme.colorScheme.primary, size: 32),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleMedium),
                Text('Deine persönliche Personalakte',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StammdatenCard extends StatelessWidget {
  const _StammdatenCard({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final profile = personal.employeeProfileForUser(userId);

    return AppSectionCard(
      title: 'Meine Stammdaten',
      icon: Icons.contact_page_outlined,
      child: profile == null
          ? Text(
              'Es sind noch keine Stammdaten hinterlegt. Wende dich für '
              'Änderungen an die Verwaltung.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          : Column(
              children: [
                _row(context, 'Anschrift', [
                  [profile.street ?? '', profile.houseNumber ?? '']
                      .where((e) => e.trim().isNotEmpty)
                      .join(' '),
                  [profile.postalCode ?? '', profile.city ?? '']
                      .where((e) => e.trim().isNotEmpty)
                      .join(' '),
                ].where((e) => e.trim().isNotEmpty).join(', ')),
                _row(
                    context,
                    'Telefon',
                    (profile.privateMobile ?? '').isNotEmpty
                        ? profile.privateMobile!
                        : (profile.privatePhone ?? '')),
                _row(context, 'E-Mail (privat)', profile.privateEmail ?? ''),
                _row(context, 'Personalnummer', profile.personnelNumber ?? ''),
                Padding(
                  padding: EdgeInsets.only(top: context.spacing.sm),
                  child: Text(
                    'Änderungen bitte an die Verwaltung melden.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _LohnabrechnungenCard extends StatefulWidget {
  const _LohnabrechnungenCard({required this.employeeName});
  final String employeeName;

  @override
  State<_LohnabrechnungenCard> createState() => _LohnabrechnungenCardState();
}

class _LohnabrechnungenCardState extends State<_LohnabrechnungenCard> {
  static const _monate = [
    '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli',
    'August', 'September', 'Oktober', 'November', 'Dezember',
  ];
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final records = [...personal.payrollRecords]
      ..sort((a, b) {
        final byYear = b.periodYear.compareTo(a.periodYear);
        return byYear != 0 ? byYear : b.periodMonth.compareTo(a.periodMonth);
      });

    return AppSectionCard(
      title: 'Meine Lohnabrechnungen',
      icon: Icons.receipt_long_outlined,
      child: records.isEmpty
          ? Text(
              'Es liegen noch keine freigegebenen Lohnabrechnungen vor.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          : Column(
              children: [
                for (final r in records)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.euro_outlined),
                    title: Text('${_monate[r.periodMonth]} ${r.periodYear}'),
                    subtitle: Text(
                        'Netto ${_euro(r.netCents)} · ${r.status.label}'),
                    trailing: _busyId == r.id
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            icon: const Icon(Icons.download_outlined),
                            tooltip: 'Als PDF herunterladen',
                            onPressed: () => _download(r),
                          ),
                  ),
              ],
            ),
    );
  }

  Future<void> _download(PayrollRecord record) async {
    setState(() => _busyId = record.id);
    try {
      await ExportService.exportPayrollPdf(
        record: record,
        employeeName: widget.employeeName,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download fehlgeschlagen: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _euro(int cents) => '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
}

class _UrlaubCard extends StatelessWidget {
  const _UrlaubCard({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<PersonalProvider>();
    final jahr = DateTime.now().year;
    final report = personal.urlaubsReportFor(userId, jahr);
    final spacing = context.spacing;

    String tage(double v) => v == v.roundToDouble()
        ? '${v.toInt()}'
        : v.toStringAsFixed(1);

    return AppSectionCard(
      title: 'Mein Urlaub $jahr',
      icon: Icons.beach_access_outlined,
      child: Row(
        children: [
          Expanded(
            child: AppMetricCard(
              label: 'Anspruch',
              value: '${tage(report.anspruchGesamt)} Tage',
              icon: Icons.event_available_outlined,
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: AppMetricCard(
              label: 'Resturlaub',
              value: '${tage(report.resturlaub)} Tage',
              icon: Icons.beach_access_outlined,
            ),
          ),
        ],
      ),
    );
  }
}
