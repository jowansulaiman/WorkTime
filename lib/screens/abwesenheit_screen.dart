import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/urlaub_calculator.dart';
import '../providers/auth_provider.dart';
import '../providers/personal_provider.dart';
import '../ui/ui.dart';

/// Org-weite **Abwesenheits-/Urlaubskonto-Übersicht** (Plan §6.7, admin-only).
///
/// Bündelt das je-Mitarbeiter im Detail verstreute Urlaubskonto an einer Stelle:
/// pro MA eine aufklappbare [AppKontoTile] mit Resturlaub-Kennzahl + +/−/=-
/// Aufstellung und §9-Hinweis (Krankheit im genehmigten Urlaub). Wird per
/// `Navigator.push` aus dem Personal-Bereich geöffnet.
class AbwesenheitScreen extends StatefulWidget {
  const AbwesenheitScreen({super.key, this.parentLabel = 'Personal'});

  final String parentLabel;

  @override
  State<AbwesenheitScreen> createState() => _AbwesenheitScreenState();
}

class _AbwesenheitScreenState extends State<AbwesenheitScreen> {
  late int _jahr = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().profile?.isAdmin ?? false;
    final spacing = context.spacing;
    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const BreadcrumbItem(label: 'Abwesenheit'),
        ],
      ),
      body: !isAdmin
          ? const EmptyState(
              icon: Icons.lock_outline,
              title: 'Kein Zugriff',
              message: 'Die Abwesenheits-Übersicht ist Administratoren '
                  'vorbehalten.',
            )
          : _buildBody(context, spacing),
    );
  }

  Widget _buildBody(BuildContext context, AppSpacing spacing) {
    final personal = context.watch<PersonalProvider>();
    final members = personal.members;
    if (members.isEmpty) {
      return const EmptyState(
        icon: Icons.beach_access_outlined,
        title: 'Keine Mitarbeiter',
        message: 'Lege im Teambereich Mitarbeiter an, um Urlaubskonten zu '
            'sehen.',
      );
    }

    final mitKrankheitImUrlaub = members
        .where((m) => personal.krankheitImUrlaubFor(m.uid, _jahr).isNotEmpty)
        .length;

    return ListView(
      padding: EdgeInsets.all(spacing.md),
      children: [
        _JahrWaehler(
          jahr: _jahr,
          onChanged: (j) => setState(() => _jahr = j),
        ),
        SizedBox(height: spacing.sm),
        if (mitKrankheitImUrlaub > 0) ...[
          AppStatusBanner(
            icon: Icons.healing_outlined,
            tone: AppStatusTone.warning,
            message: '$mitKrankheitImUrlaub Mitarbeiter mit Krankheit im '
                'genehmigten Urlaub (§9 BUrlG) – Gutschrift im Detail prüfen.',
          ),
          SizedBox(height: spacing.md),
        ],
        for (final member in members) ...[
          _UrlaubKontoEintrag(
            name: member.displayName.isEmpty ? member.email : member.displayName,
            report: personal.urlaubsReportFor(member.uid, _jahr),
            krankheitTage: personal
                .krankheitImUrlaubFor(member.uid, _jahr)
                .fold<double>(0, (s, k) => s + k.tage),
          ),
          SizedBox(height: spacing.sm),
        ],
      ],
    );
  }
}

class _JahrWaehler extends StatelessWidget {
  const _JahrWaehler({required this.jahr, required this.onChanged});

  final int jahr;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Vorjahr',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(jahr - 1),
        ),
        Text(
          'Urlaubsjahr $jahr',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        IconButton(
          tooltip: 'Folgejahr',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(jahr + 1),
        ),
      ],
    );
  }
}

/// Eine Urlaubskonto-Kachel je Mitarbeiter, baut die +/−/=-Zeilen aus dem
/// [UrlaubsReport] und reicht sie an die wiederverwendbare [AppKontoTile].
class _UrlaubKontoEintrag extends StatelessWidget {
  const _UrlaubKontoEintrag({
    required this.name,
    required this.report,
    required this.krankheitTage,
  });

  final String name;
  final UrlaubsReport report;
  final double krankheitTage;

  static String _t(double d) {
    final s = (d == d.roundToDouble())
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(1).replaceAll('.', ',');
    return '$s Tage';
  }

  @override
  Widget build(BuildContext context) {
    final zeilen = <KontoZeile>[
      KontoZeile('Jahresanspruch', _t(report.anspruchJahr)),
      if (report.vortragVorjahr != 0)
        KontoZeile('+ Vortrag Vorjahr', _t(report.vortragVorjahr)),
      if (report.vortragVerfallen != 0)
        KontoZeile('− verfallen', '-${_t(report.vortragVerfallen)}',
            ton: KontoZeileTon.warnung),
      KontoZeile('= Gesamtanspruch', _t(report.anspruchGesamt),
          summe: true, dividerDavor: true),
      KontoZeile('− genommen', '-${_t(report.genommen)}'),
      if (report.geplant != 0)
        KontoZeile('− geplant (offen)', '-${_t(report.geplant)}',
            ton: KontoZeileTon.gedaempft),
      KontoZeile('= Resturlaub', _t(report.resturlaub),
          summe: true,
          dividerDavor: true,
          ton: report.resturlaub < 0
              ? KontoZeileTon.warnung
              : KontoZeileTon.gut),
    ];

    return AppKontoTile(
      icon: Icons.beach_access_outlined,
      title: name,
      kennzahl: _t(report.resturlaub),
      kennzahlTon:
          report.resturlaub < 0 ? KontoZeileTon.warnung : KontoZeileTon.gut,
      untertitel: 'Resturlaub',
      zeilen: zeilen,
      banner: krankheitTage > 0
          ? AppStatusBanner(
              icon: Icons.healing_outlined,
              tone: AppStatusTone.warning,
              message: 'Krankheit im genehmigten Urlaub (§9 BUrlG): '
                  '${_t(krankheitTage)} nicht anrechenbar.',
            )
          : null,
    );
  }
}
