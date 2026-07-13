import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/cash_state.dart';
import '../core/daily_closing.dart';
import '../core/money.dart';
import '../models/cash_closing.dart';
import '../models/cash_count.dart';
import '../models/third_party_cash.dart';
import '../models/finance_models.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/cash_count_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

/// **Kassenabschluss (Kassen-Modul M3 / P2.0).** Für **Admin und Teamleitung**:
/// zeigt den rechnerischen Kassenzustand, nimmt Zählungen auf (Kassensturz mit
/// Soll/Ist/Differenz), schreibt Geschäftstage fest (`CashClosing`, admin-only)
/// und bietet danach die Journal-Buchung an (admin-only).
///
/// Der **Gebucht-Status** wird für die Teamleitung aus `cashClosings`
/// (`bookedToFinance`) gelesen — NICHT aus `journalEntries` (die sind
/// admin-only, §7.2). Die Konten-Auswahl + Buchung bleibt admin-gebunden.
///
/// **Richtwert** — Kassendaten sind Swagger-unverifiziert; der Steuerberater
/// prüft vor der Verbuchung.
class DailyClosingScreen extends StatefulWidget {
  const DailyClosingScreen({super.key, this.parentLabel = 'Buchhaltung'});

  final String parentLabel;

  @override
  State<DailyClosingScreen> createState() => _DailyClosingScreenState();
}

class _DailyClosingScreenState extends State<DailyClosingScreen> {
  String? _siteId;
  bool _loading = false;
  bool _booking = false;
  String? _error;
  List<DailyClosing> _closings = const [];
  List<CashClosing> _cashClosings = const [];
  List<CashCount> _cashCounts = const [];
  CashState? _cashState;
  final Map<int, String?> _accountByRate = {};
  bool _started = false;

  Future<void> _load(String siteId) async {
    setState(() {
      _siteId = siteId;
      _loading = true;
      _error = null;
    });
    try {
      final inventory = context.read<InventoryProvider>();
      final closings =
          await inventory.loadDailyClosings(siteId: siteId, windowDays: 31);
      final cashClosings = await inventory.loadCashClosings(siteId: siteId);
      final cashCounts = await inventory.loadCashCounts(siteId: siteId);
      final cashState = await inventory.loadCashState(siteId: siteId);
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _closings = closings;
        _cashClosings = cashClosings;
        _cashCounts = cashCounts;
        _cashState = cashState;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _error = 'Tagesabschluss konnte nicht geladen werden.';
        _loading = false;
      });
    }
  }

  CashClosing? _closingFor(String businessDay) {
    for (final c in _cashClosings) {
      if (c.businessDay == businessDay && c.siteId == _siteId) return c;
    }
    return null;
  }

  /// Jüngste Zählung dieses Geschäftstags (für den Abschluss-Snapshot). Deren
  /// eigener `expectedCents`/`differenceCents` wurde beim Zählen gegen das
  /// damalige Soll festgehalten — die richtige Referenz für den Tag, nicht der
  /// globale (heutige) Kassenzustand.
  CashCount? _latestCountFor(String businessDay) {
    CashCount? latest;
    for (final c in _cashCounts) {
      if (c.businessDay != businessDay || c.siteId != _siteId) continue;
      if (latest == null || c.countedAt.isAfter(latest.countedAt)) latest = c;
    }
    return latest;
  }

  String? _suggestAccount(int rate, List<CostType> types) {
    final rateStr = '$rate';
    for (final t in types) {
      if (!t.isActive) continue;
      final hay = '${t.number} ${t.name}'.toLowerCase();
      if (hay.contains(rateStr) &&
          (hay.contains('erlös') ||
              hay.contains('erlos') ||
              hay.contains('umsatz'))) {
        return t.id;
      }
    }
    return null;
  }

  /// Zählung erfassen (Leitung sieht das Soll). Schreibt eine `CashCount` mit
  /// Soll/Differenz-Snapshot und lädt den Kassenzustand neu.
  Future<void> _count() async {
    final siteId = _siteId;
    if (siteId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final inventory = context.read<InventoryProvider>();
    final expected = _cashState?.sollCents; // null ⇒ nicht verankert
    // Fremdgeld-Arten dieser Filiale (falls aktiviert) → getrennte Sektion.
    // Zusätzlich die Kassenführung (Fremdgeld in der Lade?) als Umschalter-Default.
    List<ThirdPartyCashType> thirdPartyTypes = const [];
    var thirdPartyInTill = false;
    for (final s in context.read<TeamProvider>().sites) {
      if (s.id == siteId) {
        thirdPartyTypes = s.activeThirdPartyCashTypes;
        thirdPartyInTill = s.thirdPartyCashInTill;
        break;
      }
    }
    final input = await showCashCountSheet(
      context,
      expectedCents: expected,
      thirdPartyTypes: thirdPartyTypes,
      thirdPartyInTill: thirdPartyInTill,
      subtitle: expected == null
          ? 'Noch keine Anker-Zählung — es wird nur der gezählte Betrag '
              'gespeichert.'
          : 'Der rechnerische Sollbestand wird mit deiner Zählung verglichen.',
    );
    if (input == null) return;
    final now = DateTime.now();
    final businessDay = _dayString(now);
    try {
      await inventory.saveCashCount(CashCount(
        orgId: '',
        siteId: siteId,
        businessDay: businessDay,
        countedAt: now,
        countedCents: input.countedCents,
        expectedCents: expected,
        differenceCents:
            expected == null ? null : input.countedCents - expected,
        note: input.note,
        thirdParty: input.thirdParty,
        createdByUid: '',
      ));
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Zählung gespeichert.')));
      await _load(siteId);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Zählung konnte nicht gespeichert werden.')));
    }
  }

  /// Tag festschreiben (admin-only): baut den `CashClosing`-Snapshot aus dem
  /// Tagesabschluss + aktuellem Kassenzustand und persistiert ihn.
  Future<void> _close(DailyClosing closing) async {
    final siteId = _siteId;
    if (siteId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final inventory = context.read<InventoryProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tag ${closing.businessDay} abschließen?'),
        content: const Text(
          'Der Tagesabschluss wird als unveränderlicher Snapshot '
          'festgeschrieben. Danach kannst du ihn ins Finanzjournal buchen.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Abschließen')),
        ],
      ),
    );
    if (confirmed != true) return;
    // Zählung DIESES Tages einbetten (falls vorhanden); ihr eigener Soll-Snapshot
    // ist die tagesrichtige Referenz, nicht der globale Kassenzustand.
    final zaehlung = _latestCountFor(closing.businessDay);
    try {
      await inventory.closeBusinessDay(CashClosing.fromDailyClosing(
        closing: closing,
        orgId: '',
        closedByUid: '',
        cashExpectedCents: zaehlung?.expectedCents,
        zaehlung: zaehlung,
      ));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Tag ${closing.businessDay} festgeschrieben.')));
      await _load(siteId);
    } on StateError catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(e.message.replaceFirst('Bad state: ', ''))));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Abschluss fehlgeschlagen.')));
    }
  }

  Future<void> _book(DailyClosing closing, FinanceProvider finance) async {
    final siteId = _siteId;
    if (siteId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final inventory = context.read<InventoryProvider>();
    final mapping = <int, String>{};
    for (final b in closing.taxBuckets) {
      final rate = b.ratePercent;
      if (rate == null) continue;
      final acc = _accountByRate[rate];
      if (acc != null && acc.isNotEmpty) mapping[rate] = acc;
    }
    if (mapping.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Bitte erst je USt-Satz ein Erlöskonto wählen.')));
      return;
    }
    setState(() => _booking = true);
    try {
      final posting = await finance.postDailyClosing(closing,
          revenueCostTypeIdByRate: mapping);
      final n = posting.entries;
      final cashClosing = _closingFor(closing.businessDay);
      // Kassendifferenz (M6, §8a) gleich mitbuchen — Fehlbetrag → Kosten,
      // Überschuss → Gutschrift, idempotent. SEPARAT gekapselt wie
      // markClosingBooked: schlägt nur die Differenz-Buchung fehl, bleibt die
      // Umsatzbuchung dennoch gültig (keine „fehlgeschlagen"-Meldung).
      var diffBooked = false;
      if (cashClosing != null) {
        try {
          diffBooked = await finance.postCashDifference(cashClosing);
        } catch (_) {
          diffBooked = false;
        }
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('$n Zeile(n) für ${closing.businessDay} gebucht'
              '${diffBooked ? ' (inkl. Kassendifferenz)' : ''}.')));
      // DATEV-2: USt-Sätze mit Umsatz aber ohne Erlöskonto NICHT still
      // verschlucken — ehrlicher Hinweis, dass diese Beträge fehlen.
      if (posting.skippedRates.isNotEmpty && mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text(
                'Nicht gebucht: kein Erlöskonto für '
                '${posting.skippedRates.map((r) => '$r%').join(', ')} USt — '
                'bitte Konto zuordnen.')));
      }
      // Abschluss (falls vorhanden) als gebucht markieren — Gebucht-Badge der
      // Teamleitung liest cashClosings, nicht das admin-only Journal. Der
      // Markierungs-Schritt ist SEPARAT gekapselt: schlägt nur er fehl, ist
      // die Journal-Buchung dennoch erfolgt — keine „fehlgeschlagen"-Meldung.
      // H11: NUR markieren, wenn das Journal wirklich im autoritativen
      // Speicher liegt — landete es im hybriden Offline-Fallback nur lokal,
      // gaelte der Abschluss sonst cloud-weit als gebucht, obwohl die
      // Buchung nirgends fuer Buchhaltung/DATEV sichtbar ist.
      if (!posting.cloudComplete && n > 0 && mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Journal offline nur lokal gespeichert — der Abschluss wird '
                'erst nach erfolgreicher Synchronisierung als gebucht '
                'markiert.')));
      }
      if (posting.cloudComplete &&
          n > 0 &&
          cashClosing?.id != null &&
          !cashClosing!.bookedToFinance) {
        try {
          await inventory.markClosingBooked(closingId: cashClosing.id!);
        } catch (_) {
          if (mounted) {
            messenger.showSnackBar(const SnackBar(
                content: Text(
                    'Gebucht — Gebucht-Markierung folgt beim nächsten Laden.')));
          }
        }
      }
      await _load(siteId);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Buchung fehlgeschlagen.')));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Tagesabschluss (Kasse)'),
    ];
    // Zugriff: Admin ODER Teamleitung (deckungsgleich mit den posReceipts-Rules).
    final canView = profile != null && (profile.isAdmin || profile.isTeamLead);
    if (!canView) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Leitung/Admin.')),
      );
    }
    final isAdmin = profile.isAdmin;

    final finance = context.watch<FinanceProvider>();
    final sites = [
      for (final s in context.watch<TeamProvider>().sites)
        if (s.id != null) (id: s.id!, name: s.name),
    ];
    if (_siteId == null && sites.isNotEmpty) _siteId = sites.first.id;
    if (!_started && _siteId != null) {
      _started = true;
      final siteId = _siteId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(siteId);
      });
    }

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: breadcrumbs,
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _siteId == null ? null : () => _load(_siteId!),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (sites.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<String>(
                    value: _siteId,
                    onChanged: (v) {
                      if (v != null) _load(v);
                    },
                    items: [
                      for (final s in sites)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                  ),
                ),
              ),
            Expanded(
                child: _buildBody(context, finance, sites.isEmpty, isAdmin)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    FinanceProvider finance,
    bool noSites,
    bool isAdmin,
  ) {
    if (noSites) {
      return const EmptyState(
          icon: Icons.store_outlined,
          title: 'Keine Standorte',
          message: 'Lege zuerst Standorte an.');
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Fehlgeschlagen',
        message: _error!,
        action: FilledButton.tonal(
          onPressed: _siteId == null ? null : () => _load(_siteId!),
          child: const Text('Erneut versuchen'),
        ),
      );
    }
    if (_loading && _closings.isEmpty && _cashState == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Distinct USt-Sätze über alle Tage einsammeln + Konto vorbelegen.
    final rates = <int>{};
    for (final c in _closings) {
      for (final b in c.taxBuckets) {
        if (b.ratePercent != null) rates.add(b.ratePercent!);
      }
    }
    final sortedRates = rates.toList()..sort((a, b) => b.compareTo(a));
    for (final r in sortedRates) {
      _accountByRate.putIfAbsent(
        r,
        () => finance.datevConfig.revenueAccountByRate[r] ??
            _suggestAccount(r, finance.costTypes),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _CashStateCard(state: _cashState, onCount: _count),
        const SizedBox(height: 12),
        if (isAdmin && sortedRates.isNotEmpty) ...[
          _AccountsCard(
            rates: sortedRates,
            accountByRate: _accountByRate,
            costTypes: finance.costTypes,
            onChanged: (rate, value) =>
                setState(() => _accountByRate[rate] = value),
            onSave: () => _saveAccounts(finance),
          ),
          const SizedBox(height: 12),
        ],
        if (_closings.isEmpty)
          const EmptyState(
              icon: Icons.point_of_sale_outlined,
              title: 'Kein Kassenabgleich',
              message: 'Für die letzten 31 Tage liegen keine Belege vor.')
        else
          for (final c in _closings) ...[
            _ClosingCard(
              closing: c,
              cashClosing: _closingFor(c.businessDay),
              isAdmin: isAdmin,
              onClose: _booking ? null : () => _close(c),
              onBook: _booking ? null : () => _book(c, finance),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Future<void> _saveAccounts(FinanceProvider finance) async {
    final messenger = ScaffoldMessenger.of(context);
    final mapping = <int, String>{
      for (final e in _accountByRate.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    try {
      await finance.saveDatevConfig(
          finance.datevConfig.copyWith(revenueAccountByRate: mapping));
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Erlöskonten gemerkt.')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Speichern fehlgeschlagen.')));
    }
  }

  String _dayString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Kassenzustand-Karte: rechnerischer Bargeld-Sollbestand + letzte Zählung.
class _CashStateCard extends StatelessWidget {
  const _CashStateCard({required this.state, required this.onCount});

  final CashState? state;
  final VoidCallback onCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = state;
    final verankert = s?.verankert ?? false;
    final letzte = s?.letzteZaehlung;
    return SectionCard(
      title: 'Kassenzustand',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (verankert) ...[
            Text('Rechnerischer Bargeldbestand',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              Money.formatCents(s!.sollCents),
              style: theme.textTheme.headlineMedium,
            ),
            if (letzte != null) ...[
              const SizedBox(height: 4),
              Text(
                'Zuletzt gezählt am '
                '${DateFormat('d. MMM, HH:mm', 'de_DE').format(letzte.countedAt)} '
                '(${Money.formatCents(letzte.countedCents)})',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (letzte.thirdParty.isNotEmpty)
                Text(
                  'davon getrennt Fremdgeld: '
                  '${Money.formatCents(letzte.thirdPartyTotalCents)} '
                  '(Treuhand, kein Umsatz)',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ] else
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: theme.appColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Noch keine Zählung im Zeitfenster — bitte Kasse zählen, '
                    'um den Sollbestand zu verankern.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onCount,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Kasse zählen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsCard extends StatelessWidget {
  const _AccountsCard({
    required this.rates,
    required this.accountByRate,
    required this.costTypes,
    required this.onChanged,
    required this.onSave,
  });

  final List<int> rates;
  final Map<int, String?> accountByRate;
  final List<CostType> costTypes;
  final void Function(int rate, String? value) onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Erlöskonten je USt-Satz',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Konto je Satz wählen (Richtwert — Steuerberater prüft).'),
            ),
          ),
          for (final rate in rates)
            Row(
              children: [
                SizedBox(width: 56, child: Text('$rate %')),
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: accountByRate[rate],
                    hint: const Text('— Konto wählen —'),
                    onChanged: (v) => onChanged(rate, v),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— kein Konto —')),
                      for (final t in costTypes)
                        if (t.id != null && t.isActive)
                          DropdownMenuItem(
                              value: t.id,
                              child: Text('${t.number} ${t.name}',
                                  overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Konten merken'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({
    required this.closing,
    required this.cashClosing,
    required this.isAdmin,
    required this.onClose,
    required this.onBook,
  });

  final DailyClosing closing;
  final CashClosing? cashClosing;
  final bool isAdmin;
  final VoidCallback? onClose;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final festgeschrieben = cashClosing != null;
    final gebucht = cashClosing?.bookedToFinance ?? false;
    final diff = cashClosing?.cashDifferenceCents;
    return SectionCard(
      title: '${closing.businessDay} · '
          '${Money.formatCents(closing.revenueGrossCents)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (festgeschrieben)
                _StatusChip(
                  icon: Icons.lock_outline,
                  label: 'festgeschrieben',
                  color: theme.appColors.info,
                ),
              if (gebucht)
                _StatusChip(
                  icon: Icons.check_circle,
                  label: 'gebucht',
                  color: theme.appColors.success,
                ),
            ],
          ),
          if (festgeschrieben || diff != null) const SizedBox(height: 6),
          Text('${closing.salesCount} Verkäufe · ${closing.refundCount} '
              'Erstattungen'),
          const SizedBox(height: 6),
          for (final b in closing.taxBuckets)
            Text(
              '${b.ratePercent == null ? 'ohne Satz' : '${b.ratePercent} % USt'}: '
              'netto ${Money.formatCents(b.netCents)} · '
              'USt ${Money.formatCents(b.taxCents)}',
              style: theme.textTheme.bodySmall,
            ),
          if (closing.paymentsByMethod.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Zahlart: ${closing.paymentsByMethod.entries.map((e) => '${e.key} ${Money.formatCents(e.value)}').join(' · ')}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (closing.cashMovementCents != 0)
            Text(
                'Bargeld-Bewegung: ${Money.formatCents(closing.cashMovementCents)}',
                style: theme.textTheme.bodySmall),
          if (diff != null) ...[
            const SizedBox(height: 4),
            Text(
              'Kassendifferenz (gezählt − Soll): ${Money.formatCents(diff)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: diff == 0
                    ? theme.appColors.success
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          // Dritte Hand / Fremdgelder — getrennt von Umsatz/Kassendifferenz
          // (Treuhand, kein Umsatz). Fließt bewusst NICHT in die Differenz oben.
          if (festgeschrieben && cashClosing!.thirdParty.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Dritte Hand / Fremdgelder (Treuhand, kein Umsatz)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            for (final t in cashClosing!.thirdParty)
              Text(
                '${t.typeName}: ${Money.formatCents(t.amountCents)}',
                style: theme.textTheme.bodySmall,
              ),
            Text(
              'Fremdgeld gesamt: '
              '${Money.formatCents(cashClosing!.thirdPartyTotalCents)}',
              style:
                  theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if (isAdmin) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!festgeschrieben)
                  FilledButton.tonalIcon(
                    onPressed: onClose,
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Tag abschließen'),
                  )
                else if (!gebucht)
                  FilledButton.tonal(
                    onPressed: onBook,
                    child: const Text('Ins Journal buchen'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
