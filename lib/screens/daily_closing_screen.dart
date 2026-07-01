import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/daily_closing.dart';
import '../core/money.dart';
import '../models/finance_models.dart';
import '../providers/auth_provider.dart';
import '../providers/finance_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/team_provider.dart';
import '../theme/theme_extensions.dart';
import '../widgets/breadcrumb_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

/// **Tagesabschluss → Buchung (P2.0).** Admin-Screen: zeigt je Geschäftstag den
/// Tagesumsatz mit **USt-Split**, **Zahlart-Split** und Bargeld-Bewegung und
/// bucht ihn auf Knopfdruck als **n JournalEntries je USt-Satz** auf das je Satz
/// gewählte Erlöskonto (`FinanceProvider.postDailyClosing`, idempotent).
///
/// Das Satz→Erlöskonto-Mapping wählt der Admin explizit (vorbelegt per
/// Namens-Match, aber die Buchung nutzt die getroffene Auswahl). **Richtwert**
/// — Kassendaten sind Swagger-unverifiziert; der Steuerberater prüft.
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
  final Map<int, String?> _accountByRate = {};
  bool _started = false;

  Future<void> _load(String siteId) async {
    setState(() {
      _siteId = siteId;
      _loading = true;
      _error = null;
    });
    try {
      final closings = await context
          .read<InventoryProvider>()
          .loadDailyClosings(siteId: siteId, windowDays: 31);
      if (!mounted || siteId != _siteId) return;
      setState(() {
        _closings = closings;
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

  Future<void> _book(DailyClosing closing, FinanceProvider finance) async {
    final messenger = ScaffoldMessenger.of(context);
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
      final n = await finance.postDailyClosing(closing,
          revenueCostTypeIdByRate: mapping);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('$n Zeile(n) für ${closing.businessDay} gebucht.')));
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
    if (profile == null || !profile.isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(child: Text('Nur für Administratoren.')),
      );
    }

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
            Expanded(child: _buildBody(context, finance, sites.isEmpty)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, FinanceProvider finance, bool noSites) {
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
    if (_loading && _closings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_closings.isEmpty) {
      return const EmptyState(
          icon: Icons.point_of_sale_outlined,
          title: 'Kein Kassenabgleich',
          message: 'Für die letzten 31 Tage liegen keine Belege vor.');
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
        // Persistiertes Mapping hat Vorrang, sonst Namens-Match-Vorschlag.
        () => finance.datevConfig.revenueAccountByRate[r] ??
            _suggestAccount(r, finance.costTypes),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
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
              for (final rate in sortedRates)
                Row(
                  children: [
                    SizedBox(width: 56, child: Text('$rate %')),
                    Expanded(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _accountByRate[rate],
                        hint: const Text('— Konto wählen —'),
                        onChanged: (v) =>
                            setState(() => _accountByRate[rate] = v),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('— kein Konto —')),
                          for (final t in finance.costTypes)
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
                  onPressed: () => _saveAccounts(finance),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Konten merken'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final c in _closings) ...[
          _ClosingCard(
            closing: c,
            bookedRates: _bookedRatesFor(c, finance.journalEntries),
            onBook: _booking ? null : () => _book(c, finance),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// Persistiert das Satz→Erlöskonto-Mapping in der DATEV-Config (einmal setzen,
  /// dann beim nächsten Aufruf vorbelegt).
  Future<void> _saveAccounts(FinanceProvider finance) async {
    final messenger = ScaffoldMessenger.of(context);
    final mapping = <int, String>{
      for (final e in _accountByRate.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    try {
      await finance
          .saveDatevConfig(finance.datevConfig.copyWith(revenueAccountByRate: mapping));
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Erlöskonten gemerkt.')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Speichern fehlgeschlagen.')));
    }
  }

  Set<int> _bookedRatesFor(DailyClosing c, List<JournalEntry> entries) {
    final prefix = 'pos-${c.businessDay}-${c.siteId}-';
    final booked = <int>{};
    for (final e in entries) {
      final id = e.id;
      if (id == null || !id.startsWith(prefix)) continue;
      final rate = int.tryParse(id.substring(prefix.length));
      if (rate != null) booked.add(rate);
    }
    return booked;
  }
}

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({
    required this.closing,
    required this.bookedRates,
    required this.onBook,
  });

  final DailyClosing closing;
  final Set<int> bookedRates;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBooked = bookedRates.isNotEmpty;
    return SectionCard(
      title: '${closing.businessDay} · '
          '${Money.formatCents(closing.revenueGrossCents)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${closing.salesCount} Verkäufe · ${closing.refundCount} '
              'Erstattungen'),
          const SizedBox(height: 6),
          for (final b in closing.taxBuckets)
            Text(
              '${b.ratePercent == null ? 'ohne Satz' : '${b.ratePercent} % USt'}: '
              'netto ${Money.formatCents(b.netCents)} · '
              'USt ${Money.formatCents(b.taxCents)}'
              '${b.ratePercent != null && bookedRates.contains(b.ratePercent) ? '  ✓ gebucht' : ''}',
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
            Text('Bargeld-Bewegung: ${Money.formatCents(closing.cashMovementCents)}',
                style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isBooked)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(children: [
                    Icon(Icons.check_circle,
                        size: 16, color: theme.appColors.success),
                    const SizedBox(width: 4),
                    Text('gebucht', style: theme.textTheme.labelMedium),
                  ]),
                ),
              FilledButton.tonal(
                onPressed: onBook,
                child: Text(isBooked ? 'Erneut buchen' : 'Buchen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
