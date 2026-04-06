import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';

import '../models/shift.dart';
import '../models/work_entry.dart';
import '../models/work_template.dart';
import '../providers/team_provider.dart';
import '../providers/work_provider.dart';
import '../widgets/breadcrumb_app_bar.dart';

class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({
    super.key,
    this.entry,
    this.initialDate,
    this.parentLabel = 'Zeit',
  });

  final WorkEntry? entry;
  final DateTime? initialDate;
  final String parentLabel;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late TextEditingController _breakCtrl;
  late TextEditingController _noteCtrl;
  late TextEditingController _correctionReasonCtrl;
  String? _selectedTemplateId;
  String? _selectedSiteId;
  bool _saving = false;
  bool _loadingConfirmedShifts = false;
  List<Shift> _confirmedDayShifts = [];
  String? _confirmedShiftsError;
  String? _selectedShiftId;
  bool _applyFullShift = false;
  int _dayShiftRequestId = 0;
  bool _checkingShiftCoverage = false;
  Shift? _coveringShift;
  String? _shiftCoverageError;
  String? _shiftCoverageInfo;
  bool _allowsOvertimeExtension = false;
  int _shiftCoverageRequestId = 0;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null) {
      _date = WorkEntry.normalizeDate(entry.date);
      _startTime = TimeOfDay.fromDateTime(entry.startTime);
      _endTime = TimeOfDay.fromDateTime(entry.endTime);
      _breakCtrl =
          TextEditingController(text: entry.breakMinutes.toInt().toString());
      _noteCtrl = TextEditingController(text: entry.note ?? '');
      _correctionReasonCtrl =
          TextEditingController(text: entry.correctionReason ?? '');
      _selectedSiteId = entry.siteId;
    } else {
      _date = WorkEntry.normalizeDate(widget.initialDate ?? DateTime.now());
      _startTime = const TimeOfDay(hour: 8, minute: 0);
      _endTime = const TimeOfDay(hour: 17, minute: 0);
      _breakCtrl = TextEditingController(text: '30');
      _noteCtrl = TextEditingController();
      _correctionReasonCtrl = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reloadShiftContext();
      }
    });
  }

  @override
  void dispose() {
    _breakCtrl.dispose();
    _noteCtrl.dispose();
    _correctionReasonCtrl.dispose();
    super.dispose();
  }

  double get _workedHours {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    final breakMinutes = double.tryParse(_breakCtrl.text) ?? 0;
    final diff = endMinutes - startMinutes - breakMinutes;
    return diff > 0 ? diff / 60.0 : 0;
  }

  DateTime get _selectedStartDateTime => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _startTime.hour,
        _startTime.minute,
      );

  DateTime get _selectedEndDateTime => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _endTime.hour,
        _endTime.minute,
      );

  bool get _hasValidTimeRange =>
      _selectedEndDateTime.isAfter(_selectedStartDateTime);

  Shift? get _selectedShift => _confirmedDayShifts.firstWhereOrNull(
        (shift) => shift.id == _selectedShiftId,
      );

  bool get _canSaveWithShiftCoverage =>
      !_saving &&
      !_checkingShiftCoverage &&
      _selectedShift != null &&
      _shiftCoverageError == null;

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.entry != null;
    final dateFmt = DateFormat('EEEE, dd. MMMM yyyy', 'de_DE');
    final provider = context.watch<WorkProvider>();
    final teamProvider = context.watch<TeamProvider>();
    final currentUser = provider.currentUser;
    final templates = provider.templates;
    final sites =
        provider.sites.isNotEmpty ? provider.sites : teamProvider.sites;
    final selectedTemplate = _selectedTemplateId == null
        ? null
        : templates.cast<WorkTemplate?>().firstWhere(
              (template) => template?.id == _selectedTemplateId,
              orElse: () => null,
            );

    if (!(currentUser?.canEditTimeEntries ?? false)) {
      return Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: widget.parentLabel,
              onTap: () => Navigator.of(context).pop(),
            ),
            BreadcrumbItem(
              label: isEdit ? 'Eintrag bearbeiten' : 'Neuer Eintrag',
            ),
          ],
        ),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Zeiteintraege duerfen fuer dieses Profil nicht bearbeitet werden.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: [
          BreadcrumbItem(
            label: widget.parentLabel,
            onTap: () => Navigator.of(context).pop(),
          ),
          BreadcrumbItem(
              label: isEdit ? 'Eintrag bearbeiten' : 'Neuer Eintrag'),
        ],
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'Loeschen',
              onPressed: _deleteEntry,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionLabel('Datum'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(dateFmt.format(_date)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(height: 16),
                if (templates.isNotEmpty) ...[
                  const _SectionLabel('Vorlage'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.bookmarks_outlined),
                      title: Text(
                        selectedTemplate?.name ?? 'Aus Vorlage uebernehmen',
                      ),
                      subtitle: Text(
                        selectedTemplate == null
                            ? '${templates.length} Vorlage${templates.length == 1 ? '' : 'n'} verfuegbar'
                            : _formatTemplateSummary(context, selectedTemplate),
                        maxLines: selectedTemplate?.note != null ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: selectedTemplate?.note != null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickTemplate(templates),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const _SectionLabel('Bestaetigte Schicht'),
                _ConfirmedShiftSelectorCard(
                  shifts: _confirmedDayShifts,
                  loading: _loadingConfirmedShifts,
                  error: _confirmedShiftsError,
                  selectedShiftId: _selectedShiftId,
                  applyFullShift: _applyFullShift,
                  onSelectShift: _handleShiftSelection,
                  onApplyFullShiftChanged: _selectedShift == null
                      ? null
                      : _handleApplyFullShiftChanged,
                ),
                const SizedBox(height: 16),
                const _SectionLabel('Arbeitszeit'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.login),
                        title: const Text('Beginn'),
                        trailing: Text(_formatTime(context, _startTime)),
                        onTap: _applyFullShift ? null : _pickStart,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('Ende'),
                        trailing: Text(_formatTime(context, _endTime)),
                        onTap: _applyFullShift ? null : _pickEnd,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ShiftCoverageCard(
                  loading: _checkingShiftCoverage,
                  shift: _coveringShift,
                  start: _selectedStartDateTime,
                  end: _selectedEndDateTime,
                  error: _shiftCoverageError,
                  info: _shiftCoverageInfo,
                  allowsOvertimeExtension: _allowsOvertimeExtension,
                  hasValidTimeRange: _hasValidTimeRange,
                ),
                const SizedBox(height: 16),
                const _SectionLabel('Standort'),
                if (sites.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Es ist noch kein Standort hinterlegt. Bitte zuerst einen Standort in der Teamverwaltung anlegen.',
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSiteId,
                    decoration: const InputDecoration(
                      labelText: 'Standort',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    items: [
                      for (final site in sites)
                        DropdownMenuItem(
                          value: site.id,
                          child: Text(site.name),
                        ),
                    ],
                    onChanged: _applyFullShift
                        ? null
                        : (value) {
                            setState(() => _selectedSiteId = value);
                          },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Bitte einen Standort auswaehlen';
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 16),
                const _SectionLabel('Pause'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: TextFormField(
                      controller: _breakCtrl,
                      enabled: !_applyFullShift,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.coffee_outlined),
                        hintText: 'Pause in Minuten',
                        suffixText: 'min',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final parsed = double.tryParse(value ?? '');
                        if (parsed == null || parsed < 0) {
                          return 'Ungueltiger Wert';
                        }
                        if (parsed != parsed.roundToDouble()) {
                          return 'Bitte eine ganze Zahl eingeben';
                        }
                        final totalMinutes =
                            _selectedEndDateTime
                                .difference(_selectedStartDateTime)
                                .inMinutes;
                        if (totalMinutes > 0 && parsed >= totalMinutes) {
                          return 'Pause darf nicht laenger als die Arbeitszeit sein';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _HoursSummaryCard(hours: _workedHours),
                const SizedBox(height: 16),
                if (isEdit) ...[
                  const _SectionLabel('Korrekturgrund'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextFormField(
                        controller: _correctionReasonCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText:
                              'Pflicht bei Aenderungen an Zeit, Pause oder Standort',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Bitte einen Korrekturgrund angeben';
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const _SectionLabel('Notiz'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextFormField(
                      controller: _noteCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Projekt, Aufgabe oder Bemerkung',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _canSaveWithShiftCoverage ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(isEdit ? 'Aktualisieren' : 'Speichern'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: WorkEntry.normalizeDate(_date),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _date = WorkEntry.normalizeDate(picked);
      _selectedShiftId = null;
      _applyFullShift = false;
    });
    await _reloadShiftContext();
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _startTime = picked;
      _selectedTemplateId = null;
    });
    await _refreshShiftCoverage();
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _endTime = picked;
      _selectedTemplateId = null;
    });
    await _refreshShiftCoverage();
  }

  Future<void> _pickTemplate(List<WorkTemplate> templates) async {
    final template = await showModalBottomSheet<WorkTemplate>(
      context: context,
      useSafeArea: true,
      builder: (_) => _TemplatePickerSheet(
        templates: templates,
        selectedTemplateId: _selectedTemplateId,
      ),
    );
    if (template == null) {
      return;
    }
    setState(() {
      _selectedTemplateId = template.id;
      _startTime = _timeOfDayFromMinutes(template.startMinutes);
      _endTime = _timeOfDayFromMinutes(template.endMinutes);
      _breakCtrl.text = _formatBreakMinutes(template.breakMinutes);
      _noteCtrl.text = template.note ?? '';
      _applyFullShift = false;
    });
    await _refreshShiftCoverage();
  }

  Future<void> _reloadShiftContext() async {
    final requestId = ++_dayShiftRequestId;
    setState(() {
      _loadingConfirmedShifts = true;
      _confirmedShiftsError = null;
    });

    try {
      final shifts =
          await context.read<WorkProvider>().loadConfirmedShiftsForDay(_date);
      if (!mounted || requestId != _dayShiftRequestId) {
        return;
      }
      final nextSelectedShiftId = _resolveInitialShiftId(shifts);
      setState(() {
        _confirmedDayShifts = shifts;
        _selectedShiftId = nextSelectedShiftId;
        _loadingConfirmedShifts = false;
        _confirmedShiftsError = shifts.isEmpty
            ? 'An diesem Tag gibt es keine bestaetigte Schicht.'
            : null;
        if (nextSelectedShiftId == null) {
          _applyFullShift = false;
        }
      });
      final selectedShift = _selectedShift;
      if (selectedShift != null) {
        _syncShiftDefaults(selectedShift, applyWholeShift: _applyFullShift);
      }
      await _refreshShiftCoverage();
    } catch (error) {
      if (!mounted || requestId != _dayShiftRequestId) {
        return;
      }
      setState(() {
        _confirmedDayShifts = const [];
        _selectedShiftId = null;
        _applyFullShift = false;
        _loadingConfirmedShifts = false;
        _confirmedShiftsError =
            'Bestaetigte Schichten konnten nicht geladen werden.';
      });
      await _refreshShiftCoverage();
    }
  }

  String? _resolveInitialShiftId(List<Shift> shifts) {
    if (_selectedShiftId != null &&
        shifts.any((shift) => shift.id == _selectedShiftId)) {
      return _selectedShiftId;
    }

    final sourceShiftId = widget.entry?.sourceShiftId;
    if (sourceShiftId != null &&
        shifts.any((shift) => shift.id == sourceShiftId)) {
      return sourceShiftId;
    }

    final matchingShift = shifts.firstWhereOrNull(
      (shift) => _doesRangeFitShift(shift),
    );
    if (matchingShift != null) {
      return matchingShift.id;
    }

    if (shifts.length == 1) {
      return shifts.first.id;
    }

    return null;
  }

  bool _doesRangeFitShift(
    Shift shift, {
    DateTime? start,
    DateTime? end,
  }) {
    final effectiveStart = start ?? _selectedStartDateTime;
    final effectiveEnd = end ?? _selectedEndDateTime;
    return !shift.startTime.isAfter(effectiveStart) &&
        !shift.endTime.isBefore(effectiveEnd);
  }

  bool _doesRangeOverlapShift(
    Shift shift, {
    DateTime? start,
    DateTime? end,
  }) {
    final effectiveStart = start ?? _selectedStartDateTime;
    final effectiveEnd = end ?? _selectedEndDateTime;
    return effectiveStart.isBefore(shift.endTime) &&
        effectiveEnd.isAfter(shift.startTime);
  }

  void _syncShiftDefaults(
    Shift shift, {
    required bool applyWholeShift,
  }) {
    setState(() {
      if (shift.siteId?.trim().isNotEmpty == true) {
        _selectedSiteId = shift.siteId;
      }
      if (applyWholeShift) {
        _startTime = TimeOfDay.fromDateTime(shift.startTime);
        _endTime = TimeOfDay.fromDateTime(shift.endTime);
        _breakCtrl.text = _formatBreakMinutes(shift.breakMinutes);
      }
    });
  }

  Future<void> _handleShiftSelection(Shift shift) async {
    setState(() {
      _selectedShiftId = shift.id;
    });
    _syncShiftDefaults(shift, applyWholeShift: _applyFullShift);
    await _refreshShiftCoverage();
  }

  Future<void> _handleApplyFullShiftChanged(bool value) async {
    final selectedShift = _selectedShift;
    setState(() {
      _applyFullShift = value;
    });
    if (selectedShift != null) {
      _syncShiftDefaults(selectedShift, applyWholeShift: value);
    }
    await _refreshShiftCoverage();
  }

  Future<void> _refreshShiftCoverage() async {
    final requestId = ++_shiftCoverageRequestId;
    if (!_hasValidTimeRange) {
      if (!mounted) {
        return;
      }
      setState(() {
        _checkingShiftCoverage = false;
        _coveringShift = null;
        _shiftCoverageError = 'Endzeit muss nach der Startzeit liegen.';
        _shiftCoverageInfo = null;
        _allowsOvertimeExtension = false;
      });
      return;
    }

    setState(() {
      _checkingShiftCoverage = true;
      _shiftCoverageError = null;
      _shiftCoverageInfo = null;
      _allowsOvertimeExtension = false;
    });

    try {
      final shift = _selectedShift;
      if (!mounted || requestId != _shiftCoverageRequestId) {
        return;
      }
      if (shift == null) {
        setState(() {
          _coveringShift = null;
          _shiftCoverageError = _loadingConfirmedShifts
              ? 'Bestaetigte Schichten werden geladen.'
              : _confirmedDayShifts.isEmpty
                  ? 'An diesem Tag gibt es keine bestaetigte Schicht.'
                  : 'Bitte waehle eine bestaetigte Schicht aus.';
          _shiftCoverageInfo = null;
          _allowsOvertimeExtension = false;
          _checkingShiftCoverage = false;
        });
        return;
      }

      final fits = _applyFullShift || _doesRangeFitShift(shift);
      final overlaps = _doesRangeOverlapShift(shift);
      setState(() {
        _coveringShift = fits || overlaps ? shift : null;
        _shiftCoverageError = null;
        _shiftCoverageInfo = null;
        _allowsOvertimeExtension = false;
        if (fits) {
          _shiftCoverageInfo =
              'Der Eintrag liegt vollstaendig innerhalb der ausgewaehlten Schicht.';
        } else if (overlaps) {
          _allowsOvertimeExtension = true;
          _shiftCoverageInfo =
              'Der Eintrag reicht ueber die Schicht hinaus. Beim Speichern kannst du die Zusatzzeit als Ueberstunden bestaetigen.';
        } else {
          _shiftCoverageError =
              'Zeiten muessen die ausgewaehlte Schicht mindestens teilweise abdecken. '
              'Fuer Ueberstunden muss der Eintrag an '
              '${DateFormat('HH:mm').format(shift.startTime)} - '
              '${DateFormat('HH:mm').format(shift.endTime)} liegen.';
        }
        _checkingShiftCoverage = false;
      });
    } catch (error) {
      if (!mounted || requestId != _shiftCoverageRequestId) {
        return;
      }
      setState(() {
        _coveringShift = null;
        _shiftCoverageError =
            'Schichtabdeckung konnte gerade nicht geprueft werden.';
        _shiftCoverageInfo = null;
        _allowsOvertimeExtension = false;
        _checkingShiftCoverage = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _startTime.hour,
      _startTime.minute,
    );
    final end = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Endzeit muss nach der Startzeit liegen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final provider = context.read<WorkProvider>();
    final sites = provider.sites.isNotEmpty
        ? provider.sites
        : context.read<TeamProvider>().sites;
    final selectedSite =
        sites.where((site) => site.id == _selectedSiteId).firstOrNull;
    if (selectedSite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte einen Standort waehlen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    final hasEditChanges = widget.entry != null &&
        (widget.entry!.startTime != start ||
            widget.entry!.endTime != end ||
            widget.entry!.breakMinutes !=
                (double.tryParse(_breakCtrl.text) ?? 0) ||
            widget.entry!.siteId != _selectedSiteId);
    if (hasEditChanges && _correctionReasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte einen Korrekturgrund eingeben.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final entry = WorkEntry(
      id: widget.entry?.id,
      orgId: widget.entry?.orgId ?? '',
      userId: widget.entry?.userId ?? '',
      date: WorkEntry.normalizeDate(_date),
      startTime: start,
      endTime: end,
      breakMinutes: double.tryParse(_breakCtrl.text) ?? 0,
      siteId: selectedSite.id,
      siteName: selectedSite.name,
      sourceShiftId: _selectedShift?.id,
      correctionReason: _correctionReasonCtrl.text.trim().isEmpty
          ? null
          : _correctionReasonCtrl.text.trim(),
      correctedByUid: hasEditChanges ? provider.currentUser?.uid : null,
      correctedAt: hasEditChanges ? DateTime.now() : null,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );

    try {
      await provider.saveEntryWithOvertimeHandling(
        entry,
        allowOvertime: false,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } on OvertimeApprovalRequired catch (approval) {
      if (!mounted) {
        return;
      }
      final approved = await _confirmOvertimeApproval(approval);
      if (approved != true) {
        return;
      }
      try {
        await provider.saveEntryWithOvertimeHandling(
          entry,
          allowOvertime: true,
        );
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop();
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Speichern: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool?> _confirmOvertimeApproval(
    OvertimeApprovalRequired approval,
  ) {
    final timeFmt = DateFormat('HH:mm');
    final lines = <String>[
      'Die geplante Schicht laeuft von '
          '${timeFmt.format(approval.shift.startTime)} bis '
          '${timeFmt.format(approval.shift.endTime)}.',
    ];
    if (approval.hasBeforeShiftOvertime) {
      lines.add(
        'Vor der Schicht: ${timeFmt.format(approval.beforeShiftStart!)} - '
        '${timeFmt.format(approval.beforeShiftEnd!)}',
      );
    }
    if (approval.hasAfterShiftOvertime) {
      lines.add(
        'Nach der Schicht: ${timeFmt.format(approval.afterShiftStart!)} - '
        '${timeFmt.format(approval.afterShiftEnd!)}',
      );
    }
    lines.add(
      'Die Schicht selbst wird nicht veraendert. Die Zusatzzeit wird als Ueberstunden gespeichert.',
    );

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arbeitszeit verlaengern?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines) ...[
                Text(line),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Als Ueberstunden speichern'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry() async {
    final id = widget.entry?.id;
    if (id == null) {
      return;
    }
    final provider = context.read<WorkProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eintrag loeschen?'),
        content: const Text('Dieser Eintrag wird unwiderruflich geloescht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Loeschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await provider.deleteEntry(id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Loeschen: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _ConfirmedShiftSelectorCard extends StatelessWidget {
  const _ConfirmedShiftSelectorCard({
    required this.shifts,
    required this.loading,
    required this.error,
    required this.selectedShiftId,
    required this.applyFullShift,
    required this.onSelectShift,
    required this.onApplyFullShiftChanged,
  });

  final List<Shift> shifts;
  final bool loading;
  final String? error;
  final String? selectedShiftId;
  final bool applyFullShift;
  final Future<void> Function(Shift shift) onSelectShift;
  final Future<void> Function(bool value)? onApplyFullShiftChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bestaetigte Schichten am gewaehlten Tag',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Waehle die Schicht aus, zu der der Zeiteintrag gehoert.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (error != null)
            _ShiftNoticeCard(
              icon: Icons.event_busy_outlined,
              message: error!,
              tone: _ShiftNoticeTone.warning,
            )
          else
            ...shifts.map(
              (shift) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ConfirmedShiftChoiceTile(
                  shift: shift,
                  selected: shift.id == selectedShiftId,
                  onTap: () => onSelectShift(shift),
                ),
              ),
            ),
          if (onApplyFullShiftChanged != null) ...[
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              value: applyFullShift,
              contentPadding: EdgeInsets.zero,
              title: const Text('Komplette Schicht uebernehmen'),
              subtitle: Text(
                applyFullShift
                    ? 'Beginn, Ende, Pause und Standort werden direkt aus der Schicht uebernommen.'
                    : 'Wenn deaktiviert, traegst du deine tatsaechlich geleisteten Zeiten innerhalb dieser Schicht selbst ein.',
              ),
              onChanged: onApplyFullShiftChanged,
            ),
          ],
        ],
      ),
    );
  }
}

enum _ShiftNoticeTone { info, warning }

class _ShiftNoticeCard extends StatelessWidget {
  const _ShiftNoticeCard({
    required this.icon,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String message;
  final _ShiftNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _ShiftNoticeTone.info => (
          colorScheme.primaryContainer.withValues(alpha: 0.42),
          colorScheme.onPrimaryContainer,
        ),
      _ShiftNoticeTone.warning => (
          colorScheme.errorContainer.withValues(alpha: 0.42),
          colorScheme.onErrorContainer,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmedShiftChoiceTile extends StatelessWidget {
  const _ConfirmedShiftChoiceTile({
    required this.shift,
    required this.selected,
    required this.onTap,
  });

  final Shift shift;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.42)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? colorScheme.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: colorScheme.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shift.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        _ShiftStatusPill(status: shift.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DateFormat('HH:mm').format(shift.startTime)} - ${DateFormat('HH:mm').format(shift.endTime)}'
                      ' · ${shift.workedHours.toStringAsFixed(1)} h',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (shift.effectiveSiteLabel?.trim().isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 4),
                      Text(
                        shift.effectiveSiteLabel!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftStatusPill extends StatelessWidget {
  const _ShiftStatusPill({required this.status});

  final ShiftStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      ShiftStatus.confirmed => colorScheme.primary,
      ShiftStatus.completed => colorScheme.secondary,
      ShiftStatus.cancelled => colorScheme.error,
      ShiftStatus.planned => colorScheme.tertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _ShiftCoverageCard extends StatelessWidget {
  const _ShiftCoverageCard({
    required this.loading,
    required this.shift,
    required this.start,
    required this.end,
    required this.error,
    required this.info,
    required this.allowsOvertimeExtension,
    required this.hasValidTimeRange,
  });

  final bool loading;
  final Shift? shift;
  final DateTime start;
  final DateTime end;
  final String? error;
  final String? info;
  final bool allowsOvertimeExtension;
  final bool hasValidTimeRange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isValid = shift != null && error == null;
    final background = error != null
        ? colorScheme.errorContainer.withValues(alpha: 0.34)
        : allowsOvertimeExtension
            ? colorScheme.secondaryContainer.withValues(alpha: 0.34)
            : colorScheme.primaryContainer.withValues(alpha: 0.38);
    final foreground = error != null
        ? colorScheme.onErrorContainer
        : allowsOvertimeExtension
            ? colorScheme.onSecondaryContainer
            : colorScheme.onPrimaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isValid
              ? colorScheme.primary.withValues(alpha: 0.18)
              : colorScheme.error.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                error != null
                    ? Icons.block_outlined
                    : allowsOvertimeExtension
                        ? Icons.schedule_send_outlined
                        : Icons.verified_outlined,
                color: foreground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Schichtpruefung',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasValidTimeRange
                ? '${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)}'
                : 'Zeitfenster ungueltig',
            style: theme.textTheme.titleMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (shift != null && error == null)
            Text(
              info ??
                  'Abgedeckt durch "${shift!.title}" · ${DateFormat('HH:mm').format(shift!.startTime)} - ${DateFormat('HH:mm').format(shift!.endTime)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground.withValues(alpha: 0.92),
              ),
            )
          else
            Text(
              error ?? 'Fuer diesen Zeitraum gibt es keine passende Schicht.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground.withValues(alpha: 0.92),
              ),
            ),
        ],
      ),
    );
  }
}

class _HoursSummaryCard extends StatelessWidget {
  const _HoursSummaryCard({required this.hours});

  final double hours;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Gearbeitete Zeit: ${hours.toStringAsFixed(2)} Stunden',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplatePickerSheet extends StatelessWidget {
  const _TemplatePickerSheet({
    required this.templates,
    required this.selectedTemplateId,
  });

  final List<WorkTemplate> templates;
  final String? selectedTemplateId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vorlage auswaehlen',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: templates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final template = templates[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(template.name),
                    subtitle: Text(
                      _formatTemplateSummary(context, template),
                      maxLines: template.note != null ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: template.note != null,
                    trailing: selectedTemplateId == template.id
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(template),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTemplateSummary(BuildContext context, WorkTemplate template) {
  final timeRange =
      '${_formatTime(context, _timeOfDayFromMinutes(template.startMinutes))} - '
      '${_formatTime(context, _timeOfDayFromMinutes(template.endMinutes))}';
  final breakText = 'Pause: ${_formatBreakMinutes(template.breakMinutes)} min';
  final noteText = template.note == null ? '' : '\n${template.note}';
  return '$timeRange · $breakText$noteText';
}

String _formatTime(BuildContext context, TimeOfDay time) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    time,
    alwaysUse24HourFormat: true,
  );
}

String _formatBreakMinutes(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

TimeOfDay _timeOfDayFromMinutes(int minutes) {
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}
