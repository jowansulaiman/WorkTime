import '../models/org_settings.dart';
import '../models/shift.dart';
import '../models/site_definition.dart';
import '../models/site_schedule.dart';

/// **Phase A** der automatischen Schichtverteilung: erzeugt deterministisch
/// unbesetzte Schicht-Slots aus Standort-Öffnungszeiten + Personalbedarf für
/// einen Zeitraum `[rangeStart, rangeEnd)`.
///
/// **Pure / testbar:** kein Provider-State, kein `BuildContext`, keine
/// Firestore-/Async-IO, **kein** `DateTime.now()` und **keine** Zufallswerte.
/// `seriesId` und [shiftIdFactory] werden injiziert, weil Phase B/Preview/Apply
/// Vorschläge über `shift.id` zusammenführen.
class ShiftSlotGenerator {
  const ShiftSlotGenerator({
    required this.sites,
    required this.rangeStart,
    required this.rangeEnd,
    required this.settings,
    required this.existingShifts,
    required this.orgId,
    required this.seriesId,
    required this.shiftIdFactory,
  });

  final List<SiteDefinition> sites;

  /// Halb-offener Zeitraum `[rangeStart, rangeEnd)`. Tagesweise iteriert ab dem
  /// Kalendertag von [rangeStart] (Mitternacht) bis ausschließlich [rangeEnd].
  final DateTime rangeStart;
  final DateTime rangeEnd;

  final OrgSettings settings;

  /// Bereits vorhandene Schichten im Bereich (besetzt ODER offen) — für die
  /// count-aware Idempotenz: identische Slots werden nicht doppelt erzeugt.
  final List<Shift> existingShifts;

  final String orgId;

  /// Gemeinsame Serien-ID aller in diesem Lauf erzeugten Schichten (vom Provider
  /// via `newSeriesId()`).
  final String seriesId;

  /// Stabile ID-Vergabe (vom Provider via `_nextLocalId('shift')`, in Tests
  /// deterministisch).
  final String Function() shiftIdFactory;

  /// Gesetzliche Pausenschwellen (ArbZG) — fix, damit generierte Slots nicht
  /// allein an `break_required` scheitern. Spiegelt die Default-Pausenregel
  /// (30 min ab > 6 h, 45 min ab > 9 h Nettoarbeitszeit).
  static const int _breakThreshold30 = 360;
  static const int _breakThreshold45 = 540;
  static const int _break30 = 30;
  static const int _break45 = 45;

  /// Übergabe-Overlap an Tagesrändern in Minuten (Default 0 — Schichten stoßen
  /// lückenlos aneinander). Konfigurierbar als Konstante (Plan §13.3).
  static const int handoverOverlapMinutes = 0;

  /// Sichere Netto-Tagesobergrenze (ArbZG-Default `maxPlannedMinutesPerDay`).
  /// Der Generator kennt das `ComplianceRuleSet` nicht (pure) → er deckelt die
  /// Segmentlänge gegen diesen gesetzlichen Default, damit kein erzeugter Slot
  /// allein wegen Überlänge dauerhaft an `daily_limit` scheitert.
  static const int _maxNetMinutesPerDay = 600;

  /// Erzeugt die **neu zu erstellenden, unbesetzten** Schichten, deterministisch
  /// sortiert nach `startTime, siteId, id`.
  List<Shift> generate() {
    // Count-aware Idempotenz: vorhandene Schichten nach (siteId|start|end) zählen.
    final existingCounts = <String, int>{};
    for (final shift in existingShifts) {
      final key = _slotKey(shift.siteId, shift.startTime, shift.endTime);
      existingCounts[key] = (existingCounts[key] ?? 0) + 1;
    }

    final result = <Shift>[];
    final firstDay =
        DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    for (var day = firstDay;
        day.isBefore(rangeEnd);
        day = DateTime(day.year, day.month, day.day + 1)) {
      for (final site in sites) {
        final openingWindows = _openingWindowsFor(site, day.weekday);
        if (openingWindows.isEmpty) {
          continue;
        }
        final demands = _demandsFor(site, day.weekday);
        for (final opening in openingWindows) {
          final slots = _slotsForOpening(opening, demands);
          for (final slot in slots) {
            _emitSlot(
              day: day,
              site: site,
              slot: slot,
              existingCounts: existingCounts,
              into: result,
            );
          }
        }
      }
    }

    result.sort((a, b) {
      final byStart = a.startTime.compareTo(b.startTime);
      if (byStart != 0) return byStart;
      final bySite = (a.siteId ?? '').compareTo(b.siteId ?? '');
      if (bySite != 0) return bySite;
      return (a.id ?? '').compareTo(b.id ?? '');
    });
    return result;
  }

  /// Öffnungsfenster eines Standorts für einen Wochentag, sortiert nach Start.
  List<TimeWindow> _openingWindowsFor(SiteDefinition site, int weekday) {
    final windows = <TimeWindow>[];
    for (final entry in site.weekdayHours) {
      if (entry.weekday != weekday) continue;
      for (final window in entry.windows) {
        if (window.isValid) {
          windows.add(window);
        }
      }
    }
    windows.sort((a, b) {
      final byStart = a.startMinute.compareTo(b.startMinute);
      return byStart != 0 ? byStart : a.endMinute.compareTo(b.endMinute);
    });
    return windows;
  }

  /// Bedarfe eines Standorts für einen Wochentag, deterministisch sortiert.
  List<StaffingDemand> _demandsFor(SiteDefinition site, int weekday) {
    final demands =
        site.staffingDemands.where((d) => d.weekday == weekday).toList();
    demands.sort((a, b) {
      final byStart = a.window.startMinute.compareTo(b.window.startMinute);
      if (byStart != 0) return byStart;
      final byEnd = a.window.endMinute.compareTo(b.window.endMinute);
      if (byEnd != 0) return byEnd;
      return a.requiredCount.compareTo(b.requiredCount);
    });
    return demands;
  }

  /// Slot-Definitionen (Zeitfenster + Bedarf + Qualis) für ein Öffnungsfenster.
  ///
  /// Liegt mind. ein Bedarf im Fenster, generiert **jeder** überlappende Bedarf
  /// unabhängig (deterministisch zusammengefasst) in seinem mit dem
  /// Öffnungsfenster geschnittenen Teilfenster. Liegt kein Bedarf im Fenster,
  /// gilt der implizite Bedarf `settings.defaultRequiredCount` (Qualis leer).
  List<_SlotSpec> _slotsForOpening(
    TimeWindow opening,
    List<StaffingDemand> demands,
  ) {
    final overlapping =
        demands.where((d) => d.window.overlaps(opening)).toList();
    final specs = <_SlotSpec>[];
    if (overlapping.isEmpty) {
      for (final window in _splitWindow(opening)) {
        specs.add(_SlotSpec(
          window: window,
          requiredCount: settings.defaultRequiredCount < 1
              ? 1
              : settings.defaultRequiredCount,
          qualificationIds: const [],
        ));
      }
      return specs;
    }
    for (final demand in overlapping) {
      final start = demand.window.startMinute > opening.startMinute
          ? demand.window.startMinute
          : opening.startMinute;
      final end = demand.window.endMinute < opening.endMinute
          ? demand.window.endMinute
          : opening.endMinute;
      if (end <= start) continue;
      for (final window in _splitWindow(TimeWindow(startMinute: start, endMinute: end))) {
        specs.add(_SlotSpec(
          window: window,
          requiredCount: demand.requiredCount < 1 ? 1 : demand.requiredCount,
          qualificationIds: demand.requiredQualificationIds,
        ));
      }
    }
    return specs;
  }

  /// Zerlegt ein Fenster in Brutto-Schichtlängen ~`defaultShiftMinutes`. Reste
  /// < 50 % der Soll-Länge werden an die Nachbarschicht angehängt (kein
  /// Mini-Rest-Slot). Optionaler Übergabe-Overlap an inneren Schnittkanten.
  List<TimeWindow> _splitWindow(TimeWindow window) {
    // Effektives Ziel gegen die Tages-Nettogrenze deckeln (max. ~10,75 h brutto
    // = 600 netto + 45 Pause), damit auch eine misskonfigurierte Ziel-Länge
    // keine dauerhaft unbesetzbaren Slots erzeugt.
    const cap = _maxNetMinutesPerDay + _break45;
    var target = settings.defaultShiftMinutes;
    if (target <= 0 || target > cap) {
      target = cap;
    }
    final start = window.startMinute;
    final end = window.endMinute;
    final length = end - start;
    if (length <= target) {
      return [window];
    }
    final boundaries = <int>[start];
    var cursor = start;
    while (end - cursor > target) {
      final remainderAfter = end - cursor - target;
      if (remainderAfter < target ~/ 2) {
        // Kleinen Rest normalerweise an die letzte Schicht anhängen — ABER nur,
        // wenn die zusammengelegte Schicht netto die Tagesgrenze nicht sprengt
        // (sonst eigener Rest-Slot statt eines nie-compliance-fähigen Slots).
        final mergedGross = end - cursor;
        if (mergedGross - _breakForGross(mergedGross) <= _maxNetMinutesPerDay) {
          break;
        }
      }
      cursor += target;
      boundaries.add(cursor);
    }
    boundaries.add(end);
    final windows = <TimeWindow>[];
    for (var i = 0; i < boundaries.length - 1; i++) {
      final segStart = boundaries[i];
      var segEnd = boundaries[i + 1];
      // Übergabe-Overlap nur an inneren Kanten und nie über das Fenster hinaus.
      if (i < boundaries.length - 2 && handoverOverlapMinutes > 0) {
        segEnd = (segEnd + handoverOverlapMinutes) > end
            ? end
            : segEnd + handoverOverlapMinutes;
      }
      windows.add(TimeWindow(startMinute: segStart, endMinute: segEnd));
    }
    return windows;
  }

  void _emitSlot({
    required DateTime day,
    required SiteDefinition site,
    required _SlotSpec slot,
    required Map<String, int> existingCounts,
    required List<Shift> into,
  }) {
    final startTime = day.add(Duration(minutes: slot.window.startMinute));
    final endTime = day.add(Duration(minutes: slot.window.endMinute));
    final grossMinutes = endTime.difference(startTime).inMinutes;
    final breakMinutes = _breakForGross(grossMinutes).toDouble();

    final key = _slotKey(site.id, startTime, endTime);
    final alreadyThere = existingCounts[key] ?? 0;
    final toCreate = slot.requiredCount - alreadyThere;
    if (toCreate <= 0) {
      return;
    }
    for (var i = 0; i < toCreate; i++) {
      into.add(
        Shift(
          id: shiftIdFactory(),
          orgId: orgId,
          userId: '',
          employeeName: '',
          title: site.name,
          startTime: startTime,
          endTime: endTime,
          breakMinutes: breakMinutes,
          siteId: site.id,
          siteName: site.name,
          requiredQualificationIds: slot.qualificationIds,
          seriesId: seriesId,
          status: ShiftStatus.planned,
        ),
      );
    }
    // Lokale Zählung mitführen, damit mehrere Slots am selben Standort/Zeit im
    // selben Lauf nicht zusätzlich erzeugt werden (sollte selten sein).
    existingCounts[key] = alreadyThere + toCreate;
  }

  /// Pausenminuten so wählen, dass die ArbZG-Pausenregel erfüllt ist
  /// (mind. `settings.defaultBreakMinutes`). Iterativ, da die Pause die
  /// Nettoarbeitszeit senkt.
  int _breakForGross(int grossMinutes) {
    var breakMinutes = settings.defaultBreakMinutes;
    for (var i = 0; i < 4; i++) {
      final net = grossMinutes - breakMinutes;
      var required = 0;
      if (net > _breakThreshold30) required = _break30;
      if (net > _breakThreshold45) required = _break45;
      if (breakMinutes >= required) {
        break;
      }
      breakMinutes = required;
    }
    return breakMinutes;
  }

  String _slotKey(String? siteId, DateTime start, DateTime end) =>
      '${siteId ?? ''}|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}';
}

class _SlotSpec {
  const _SlotSpec({
    required this.window,
    required this.requiredCount,
    required this.qualificationIds,
  });

  final TimeWindow window;
  final int requiredCount;
  final List<String> qualificationIds;
}
