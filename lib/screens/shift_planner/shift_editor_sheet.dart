// Teil von shift_planner_screen.dart (split-shift-planner-god-file, Strangler Schritt 3).
//
// Der komplette Schicht-Editor-Flow: das Ergebnis-Objekt (_ShiftEditorResult),
// die Vorlagen-Sheets (Picker/Speichern), der Zusatz-Zuweisungs-Entwurf, das
// _ShiftEditorSheet (StatefulWidget) samt State sowie die
// _AdditionalShiftAssignmentCard. Als 'part' gehalten, damit der
// Navigator.push/pop-Vertrag (Future<_ShiftEditorResult?>) und die gesamte
// file-private Kopplung zur Hauptdatei unveraendert erhalten bleiben und keine
// Imports dupliziert werden.
part of '../shift_planner_screen.dart';

/// Obergrenze für einen Speichervorgang im Schicht-Editor. Entspricht der
/// serverseitigen Batch-Chunk-Grenze (`_maxCallableBatchSize = 50`): bleibt der
/// Fan-out (Tage × Mitarbeiter) ≤ 50, läuft das Speichern als EIN atomarer
/// Server-Call → kein Teil-Write-Risiko bei einer Compliance-Ablehnung.
const int _kMaxShiftsPerSave = 50;

class _ShiftEditorResult {
  const _ShiftEditorResult({
    required this.shifts,
    required this.recurrencePattern,
    required this.recurrenceEndDate,
    this.groupAsSeries = false,
  });

  final List<Shift> shifts;
  final RecurrencePattern recurrencePattern;
  final DateTime? recurrenceEndDate;

  /// True, wenn die Schichten als zusammengehörige Serie (gemeinsame seriesId)
  /// gespeichert werden sollen – z.B. eine Mehrtage-Anlage. Der Aufrufer
  /// vergibt dann eine [ScheduleProvider.newSeriesId].
  final bool groupAsSeries;
}

class _ShiftTemplatePickerSheet extends StatelessWidget {
  const _ShiftTemplatePickerSheet({
    required this.templates,
    required this.selectedTemplateId,
  });

  final List<ShiftTemplate> templates;
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
              'Schichtvorlage auswaehlen',
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
                      _formatShiftTemplateSummary(context, template),
                      maxLines: template.notes != null ? 4 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
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

class _ShiftTemplateSaveSheet extends StatefulWidget {
  const _ShiftTemplateSaveSheet({
    required this.template,
  });

  final ShiftTemplate template;

  @override
  State<_ShiftTemplateSaveSheet> createState() =>
      _ShiftTemplateSaveSheetState();
}

class _ShiftTemplateSaveSheetState extends State<_ShiftTemplateSaveSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.template.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.template.id != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Schichtvorlage bearbeiten' : 'Schichtvorlage speichern',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatShiftTemplateSummary(context, widget.template),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name der Vorlage',
                prefixIcon: Icon(Icons.bookmark_outline),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Bitte einen Namen eingeben';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: Icon(isEdit ? Icons.edit_outlined : Icons.save),
              label: Text(
                isEdit ? 'Vorlage aktualisieren' : 'Vorlage speichern',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      widget.template.copyWith(
        name: _nameCtrl.text.trim(),
      ),
    );
  }
}

class _AdditionalShiftAssignmentDraft {
  const _AdditionalShiftAssignmentDraft({
    required this.id,
    this.memberId,
    required this.startTime,
    required this.endTime,
    this.breakMinutes = 0,
  });

  final int id;
  final String? memberId;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final double breakMinutes;

  _AdditionalShiftAssignmentDraft copyWith({
    String? memberId,
    bool clearMemberId = false,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    double? breakMinutes,
  }) {
    return _AdditionalShiftAssignmentDraft(
      id: id,
      memberId: clearMemberId ? null : (memberId ?? this.memberId),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      breakMinutes: breakMinutes ?? this.breakMinutes,
    );
  }
}

/// Mehrtage-Auswahl: Wochentags-Maske (Mo–So) über einen Zeitraum PLUS
/// Kalender-Mehrfachauswahl beliebiger Einzeltage. Gibt das gewählte
/// (datums-normalisierte) Tages-Set via [Navigator.pop] zurück.
class _MultiDayPickerSheet extends StatefulWidget {
  const _MultiDayPickerSheet({
    required this.initialDays,
    required this.anchorDay,
  });

  final Set<DateTime> initialDays;
  final DateTime anchorDay;

  @override
  State<_MultiDayPickerSheet> createState() => _MultiDayPickerSheetState();
}

class _MultiDayPickerSheetState extends State<_MultiDayPickerSheet> {
  static const List<String> _weekdayLabels = [
    'Mo',
    'Di',
    'Mi',
    'Do',
    'Fr',
    'Sa',
    'So',
  ];

  late Set<DateTime> _days;
  final Set<int> _weekdays = <int>{}; // 1=Mo .. 7=So (DateTime.weekday)
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _days = {for (final day in widget.initialDays) _dateOnly(day)};
    if (_days.isEmpty) {
      _days = {_dateOnly(widget.anchorDay)};
    }
    _rangeStart = _dateOnly(widget.anchorDay);
    _rangeEnd = _rangeStart.add(const Duration(days: 27)); // 4 Wochen
    _visibleMonth = DateTime(_rangeStart.year, _rangeStart.month);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _applyMask() {
    if (_rangeEnd.isBefore(_rangeStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Das Enddatum liegt vor dem Startdatum.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    final activeWeekdays =
        _weekdays.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : _weekdays;
    setState(() {
      var cursor = _rangeStart;
      while (!cursor.isAfter(_rangeEnd)) {
        if (activeWeekdays.contains(cursor.weekday)) {
          _days.add(_dateOnly(cursor));
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    });
  }

  void _toggleDay(DateTime day) {
    final normalized = _dateOnly(day);
    setState(() {
      if (!_days.remove(normalized)) {
        _days.add(normalized);
      }
    });
  }

  Future<void> _pickRangeBound({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _rangeStart : _rangeEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _rangeStart = _dateOnly(picked);
        if (_rangeEnd.isBefore(_rangeStart)) {
          _rangeEnd = _rangeStart;
        }
      } else {
        _rangeEnd = _dateOnly(picked);
        if (_rangeEnd.isBefore(_rangeStart)) {
          _rangeStart = _rangeEnd;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tage waehlen',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Wochentage im Zeitraum hinzufuegen oder einzelne Tage im '
                'Kalender antippen.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text('Wochentage', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _weekdayLabels.length; i++)
                    FilterChip(
                      label: Text(_weekdayLabels[i]),
                      selected: _weekdays.contains(i + 1),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _weekdays.add(i + 1);
                        } else {
                          _weekdays.remove(i + 1);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateTile(
                      label: 'Von',
                      value:
                          DateFormat('dd.MM.yyyy', 'de_DE').format(_rangeStart),
                      icon: Icons.event,
                      onTap: () => _pickRangeBound(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateTile(
                      label: 'Bis',
                      value:
                          DateFormat('dd.MM.yyyy', 'de_DE').format(_rangeEnd),
                      icon: Icons.event,
                      onTap: () => _pickRangeBound(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _applyMask,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(
                    _weekdays.isEmpty
                        ? 'Alle Tage im Zeitraum hinzufuegen'
                        : 'Wochentage im Zeitraum hinzufuegen',
                  ),
                ),
              ),
              const Divider(height: 28),
              _buildMonthHeader(theme),
              const SizedBox(height: 8),
              _buildWeekdayHeader(theme),
              const SizedBox(height: 4),
              _buildMonthGrid(theme),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _days.length == 1
                          ? '1 Tag ausgewaehlt'
                          : '${_days.length} Tage ausgewaehlt',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _days.isEmpty
                        ? null
                        : () => setState(_days.clear),
                    child: const Text('Zuruecksetzen'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _days.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_days),
                  child: const Text('Uebernehmen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthHeader(ThemeData theme) {
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() {
            _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month - 1);
          }),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Vorheriger Monat',
        ),
        Expanded(
          child: Text(
            DateFormat('MMMM yyyy', 'de_DE').format(_visibleMonth),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          onPressed: () => setState(() {
            _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month + 1);
          }),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Naechster Monat',
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader(ThemeData theme) {
    return Row(
      children: [
        for (final label in _weekdayLabels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMonthGrid(ThemeData theme) {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leadingBlanks = firstOfMonth.weekday - 1; // Mo-first
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final today = _dateOnly(widget.anchorDay);

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var dayNum = 1; dayNum <= daysInMonth; dayNum++) {
      final day = DateTime(_visibleMonth.year, _visibleMonth.month, dayNum);
      final selected = _days.contains(day);
      final isAnchor = day == today;
      cells.add(
        Padding(
          padding: const EdgeInsets.all(2),
          child: InkWell(
            onTap: () => _toggleDay(day),
            customBorder: const CircleBorder(),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? theme.colorScheme.primary : null,
                border: !selected && isAnchor
                    ? Border.all(color: theme.colorScheme.primary)
                    : null,
              ),
              child: Text(
                '$dayNum',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.bold : null,
                ),
              ),
            ),
          ),
        ),
      );
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: [
            for (var j = i; j < i + 7; j++) Expanded(child: cells[j]),
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

/// Auswahl beim Kopieren einer Schicht: Ziel-Mitarbeiter + Zieltage.
class _CopyShiftSelection {
  const _CopyShiftSelection({required this.days, required this.assigneeUids});

  final Set<DateTime> days;
  final List<String> assigneeUids;
}

/// Sheet zum Kopieren einer Schicht auf andere Mitarbeiter UND/ODER andere
/// Tage. Mitarbeiter werden per Chips gewählt (Standard: der bisherige
/// Mitarbeiter), Tage über den Mehrtage-Picker (Standard: der Quelltag).
class _CopyShiftSheet extends StatefulWidget {
  const _CopyShiftSheet({required this.source, required this.members});

  final Shift source;
  final List<AppUserProfile> members;

  @override
  State<_CopyShiftSheet> createState() => _CopyShiftSheetState();
}

class _CopyShiftSheetState extends State<_CopyShiftSheet> {
  late Set<String> _assigneeUids;
  late Set<DateTime> _days;

  DateTime get _sourceDay => DateTime(
        widget.source.startTime.year,
        widget.source.startTime.month,
        widget.source.startTime.day,
      );

  @override
  void initState() {
    super.initState();
    _assigneeUids =
        widget.source.isUnassigned ? <String>{} : {widget.source.userId};
    _days = {_sourceDay};
  }

  Future<void> _pickDays() async {
    final picked = await showModalBottomSheet<Set<DateTime>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _MultiDayPickerSheet(
        initialDays: _days,
        anchorDay: _sourceDay,
      ),
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() => _days = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedDays = _days.toList()..sort();
    final daysLabel = sortedDays.length == 1
        ? DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(sortedDays.first)
        : '${sortedDays.length} Tage · ab '
            '${DateFormat('dd.MM.yyyy', 'de_DE').format(sortedDays.first)}';
    final copyCount = _assigneeUids.length * _days.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Schicht kopieren',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '"${widget.source.title}" auf gewaehlte Mitarbeiter und Tage '
                'kopieren.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text('Mitarbeiter', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (widget.members.isEmpty)
                Text(
                  'Keine aktiven Mitarbeiter vorhanden.',
                  style: theme.textTheme.bodyMedium,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final member in widget.members)
                      FilterChip(
                        label: Text(member.displayName),
                        selected: _assigneeUids.contains(member.uid),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _assigneeUids.add(member.uid);
                          } else {
                            _assigneeUids.remove(member.uid);
                          }
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Text('Tage', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _DateTile(
                label: 'Tage',
                value: daysLabel,
                icon: Icons.event_available,
                onTap: _pickDays,
              ),
              const SizedBox(height: 16),
              Text(
                copyCount == 1
                    ? 'Es wird 1 Kopie erstellt.'
                    : 'Es werden bis zu $copyCount Kopien erstellt.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (copyCount > _kMaxShiftsPerSave) ...[
                const SizedBox(height: 8),
                Text(
                  'Zu viele Kopien: max. $_kMaxShiftsPerSave pro Vorgang. '
                  'Bitte weniger Tage oder Mitarbeiter wählen.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_assigneeUids.isEmpty ||
                          _days.isEmpty ||
                          copyCount > _kMaxShiftsPerSave)
                      ? null
                      : () => Navigator.of(context).pop(
                            _CopyShiftSelection(
                              days: _days,
                              assigneeUids: _assigneeUids.toList(),
                            ),
                          ),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Kopieren'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftEditorSheet extends StatefulWidget {
  const _ShiftEditorSheet({
    required this.members,
    required this.teams,
    required this.currentUser,
    this.shift,
    this.initialDate,
    this.initialUserIds,
    this.initialUnassigned = false,
    this.initialLocation,
    this.initialTeamId,
    this.initialTeamName,
    this.initialTitle,
  });

  final List<AppUserProfile> members;
  final List<TeamDefinition> teams;
  final AppUserProfile currentUser;
  final Shift? shift;
  final DateTime? initialDate;
  final Set<String>? initialUserIds;
  final bool initialUnassigned;
  final String? initialLocation;
  final String? initialTeamId;
  final String? initialTeamName;
  final String? initialTitle;

  @override
  State<_ShiftEditorSheet> createState() => _ShiftEditorSheetState();
}

class _ShiftEditorSheetState extends State<_ShiftEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _teamCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _breakCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late Set<String> _selectedUserIds;
  String? _selectedTeamId;
  late ShiftStatus _status;
  RecurrencePattern _recurrencePattern = RecurrencePattern.none;
  DateTime? _recurrenceEndDate;
  // Tage, an denen Schichten erzeugt werden (Mehrtage-Anlage). Immer
  // datums-normalisiert (Mitternacht) und nicht leer; im Edit-Modus genau ein
  // Tag. [_date] bleibt der Ankertag (= frühester Tag, Bezug für Uhrzeiten und
  // Zusatzbesetzungen).
  late Set<DateTime> _selectedDays;
  String? _shiftColor;
  List<ShiftConflictIssue> _conflictIssues = const [];
  List<ShiftAssigneeAvailability> _assigneeAvailability = const [];
  int _availabilityRequestId = 0;
  bool _loadingAvailability = false;
  late bool _saveAsUnassigned;
  String? _selectedSiteId;
  String? _selectedTemplateId;
  bool _siteInitialized = false;
  Set<String> _requiredQualificationIds = <String>{};
  List<_AdditionalShiftAssignmentDraft> _additionalAssignments = const [];
  int _nextAdditionalAssignmentDraftId = 0;
  bool _validating = false;
  // Aufgeklappte Sperrgruende je Mitarbeiter (kompakte Liste: Details on demand).
  final Set<String> _expandedMemberIds = <String>{};
  // Lange Teams: erst gekappt, dann auf Wunsch komplett zeigen.
  bool _showAllMembers = false;

  @override
  void initState() {
    super.initState();
    final shift = widget.shift;
    _saveAsUnassigned =
        widget.initialUnassigned || (shift?.isUnassigned ?? false);
    final initialDate =
        widget.initialDate ?? shift?.startTime ?? DateTime.now();
    _titleCtrl =
        TextEditingController(text: shift?.title ?? widget.initialTitle ?? '');
    _teamCtrl = TextEditingController(
      text: shift?.team ?? widget.initialTeamName ?? '',
    );
    _locationCtrl = TextEditingController(
      text: shift?.location ?? widget.initialLocation ?? '',
    );
    _breakCtrl = TextEditingController(
      text: (shift?.breakMinutes ?? 30).toStringAsFixed(0),
    );
    _notesCtrl = TextEditingController(text: shift?.notes ?? '');
    _date = initialDate;
    _selectedDays = {DateTime(initialDate.year, initialDate.month, initialDate.day)};
    _startTime = TimeOfDay.fromDateTime(
      shift?.startTime ?? initialDate,
    );
    _endTime = TimeOfDay.fromDateTime(
      shift?.endTime ?? initialDate.add(const Duration(hours: 8)),
    );
    final draftUserIds = widget.initialUserIds ?? const <String>{};
    if (shift != null) {
      _selectedUserIds = {
        if (!shift.isUnassigned) shift.userId,
      };
    } else if (draftUserIds.isNotEmpty) {
      _selectedUserIds = draftUserIds.toSet();
    } else if (_saveAsUnassigned) {
      _selectedUserIds = <String>{};
    } else {
      _selectedUserIds = {
        if (widget.members.isNotEmpty) widget.members.first.uid,
      };
    }
    _selectedTeamId = shift?.teamId ??
        widget.initialTeamId ??
        widget.teams
            .where((team) => team.name == shift?.team)
            .map((team) => team.id)
            .whereType<String>()
            .firstOrNull;
    _selectedSiteId = shift?.siteId;
    _requiredQualificationIds = {
      ...?shift?.requiredQualificationIds,
    };
    _status = shift?.status ?? ShiftStatus.planned;
    _recurrencePattern = shift?.recurrencePattern ?? RecurrencePattern.none;
    _shiftColor = shift?.color;
    _titleCtrl.addListener(_clearConflictPreview);
    _teamCtrl.addListener(_clearConflictPreview);
    _locationCtrl.addListener(_clearConflictPreview);
    _breakCtrl.addListener(_clearConflictPreview);
    _notesCtrl.addListener(_clearConflictPreview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_saveAsUnassigned) {
        _refreshAssigneeAvailability();
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_clearConflictPreview);
    _teamCtrl.removeListener(_clearConflictPreview);
    _locationCtrl.removeListener(_clearConflictPreview);
    _breakCtrl.removeListener(_clearConflictPreview);
    _notesCtrl.removeListener(_clearConflictPreview);
    _titleCtrl.dispose();
    _teamCtrl.dispose();
    _locationCtrl.dispose();
    _breakCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_siteInitialized) {
      return;
    }
    _siteInitialized = true;
    final sites = context.read<TeamProvider>().sites;
    var site = sites.firstWhereOrNull(
      (candidate) =>
          candidate.id == _selectedSiteId ||
          candidate.name.trim().toLowerCase() ==
              _locationCtrl.text.trim().toLowerCase(),
    );
    // Smarte Vorbelegung des Pflicht-Standorts (spart bei jeder Neuanlage
    // Taps): kein Treffer + Neuanlage -> einziger Org-Standort, sonst der
    // zuletzt verwendete. Im Edit-Modus nie überschreiben.
    if (site == null && widget.shift == null) {
      if (sites.length == 1) {
        site = sites.first;
      } else {
        site = sites.firstWhereOrNull(
          (candidate) => candidate.id == ScheduleProvider.lastUsedSiteId,
        );
      }
    }
    if (site != null) {
      _selectedSiteId = site.id;
      _locationCtrl.text = site.name;
    }
  }

  void _clearConflictPreview() {
    if (_conflictIssues.isEmpty) {
      return;
    }
    setState(() => _conflictIssues = const []);
  }

  void _setDirty(
    VoidCallback callback, {
    bool refreshAvailability = false,
  }) {
    setState(() {
      callback();
      _conflictIssues = const [];
    });
    if (refreshAvailability) {
      _refreshAssigneeAvailability();
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = context.watch<TeamProvider>();
    final scheduleProvider = context.watch<ScheduleProvider>();
    final sites = teamProvider.sites;
    final qualifications = teamProvider.qualifications;
    final shiftTemplates = scheduleProvider.shiftTemplates;
    final selectedTemplate = shiftTemplates
        .where((template) => template.id == _selectedTemplateId)
        .firstOrNull;
    final isEdit = widget.shift != null;
    final selectedTeam =
        widget.teams.where((team) => team.id == _selectedTeamId).firstOrNull;
    final availabilityItems = _visibleAssigneeAvailability;
    final availableMembers = availabilityItems
        .where((entry) => entry.isAvailable)
        .toList(growable: false);
    final unavailableMembers = availabilityItems
        .where((entry) => !entry.isAvailable)
        .toList(growable: false);
    final selectedUserId = _selectedUserIds.firstOrNull;
    final selectedAvailability = availabilityItems
        .where((entry) => entry.member.uid == selectedUserId)
        .firstOrNull;
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final pagePad = spacing.md;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixierter Kopf: Titel + Schliessen.
            Padding(
              padding: EdgeInsets.fromLTRB(pagePad, spacing.sm, spacing.sm, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Schicht bearbeiten' : 'Neue Schicht',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schliessen',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Scrollbarer Formular-Inhalt in klaren Abschnitten.
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  pagePad,
                  spacing.sm,
                  pagePad,
                  spacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTemplateBar(context, shiftTemplates, selectedTemplate),
                    SizedBox(height: spacing.md),
                    _buildCoreSection(context, sites, isEdit),
                    SizedBox(height: spacing.md),
                    _buildStaffingSection(
                      context,
                      isEdit: isEdit,
                      availabilityItems: availabilityItems,
                      availableMembers: availableMembers,
                      unavailableMembers: unavailableMembers,
                      selectedUserId: selectedUserId,
                      selectedAvailability: selectedAvailability,
                    ),
                    SizedBox(height: spacing.md),
                    _buildDetailsSection(
                      context,
                      qualifications: qualifications,
                      selectedTeam: selectedTeam,
                      isEdit: isEdit,
                    ),
                    if (_conflictIssues.isNotEmpty) ...[
                      SizedBox(height: spacing.md),
                      _buildConflictCard(context),
                    ],
                  ],
                ),
              ),
            ),
            // Fixierte Aktionsleiste (immer erreichbar).
            _buildFooter(context, isEdit),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTemplate(List<ShiftTemplate> templates) async {
    final template = await showModalBottomSheet<ShiftTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _ShiftTemplatePickerSheet(
        templates: templates,
        selectedTemplateId: _selectedTemplateId,
      ),
    );
    if (template == null || !mounted) {
      return;
    }

    final sites = context.read<TeamProvider>().sites;
    final resolvedTeam = widget.teams.firstWhereOrNull(
      (team) =>
          team.id == template.teamId ||
          (template.teamName?.trim().isNotEmpty == true &&
              team.name.trim().toLowerCase() ==
                  template.teamName!.trim().toLowerCase()),
    );
    final resolvedSite = sites.firstWhereOrNull(
      (site) =>
          site.id == template.siteId ||
          (template.siteName?.trim().isNotEmpty == true &&
              site.name.trim().toLowerCase() ==
                  template.siteName!.trim().toLowerCase()),
    );

    _setDirty(
      () {
        _selectedTemplateId = template.id;
        _titleCtrl.text = template.title;
        _startTime = _timeOfDayFromMinutes(template.startMinutes);
        _endTime = _timeOfDayFromMinutes(template.endMinutes);
        _breakCtrl.text = _formatBreakMinutes(template.breakMinutes);
        _notesCtrl.text = template.notes ?? '';
        _selectedTeamId = resolvedTeam?.id;
        _teamCtrl.text = resolvedTeam?.name ?? (template.teamName ?? '');
        _selectedSiteId = resolvedSite?.id;
        _locationCtrl.text = resolvedSite?.name ?? (template.siteName ?? '');
        _requiredQualificationIds = template.requiredQualificationIds.toSet();
        _shiftColor = template.color;
      },
      refreshAvailability: true,
    );
  }

  Future<void> _saveCurrentAsTemplate() async {
    final draft = _buildTemplateDraft();
    if (draft == null) {
      return;
    }

    final template = await _openTemplateSaveSheet(draft);
    if (template == null || !mounted) {
      return;
    }

    try {
      await context.read<ScheduleProvider>().saveShiftTemplate(template);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schichtvorlage gespeichert.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vorlage konnte nicht gespeichert werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _updateTemplate(ShiftTemplate template) async {
    final draft = _buildTemplateDraft();
    if (draft == null) {
      return;
    }

    final updatedTemplate = await _openTemplateSaveSheet(
      draft.copyWith(
        id: template.id,
        orgId: template.orgId,
        userId: template.userId,
        name: template.name,
      ),
    );
    if (updatedTemplate == null || !mounted) {
      return;
    }

    try {
      await context.read<ScheduleProvider>().saveShiftTemplate(updatedTemplate);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schichtvorlage aktualisiert.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vorlage konnte nicht aktualisiert werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteTemplate(ShiftTemplate template) async {
    final templateId = template.id;
    if (templateId == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Schichtvorlage löschen?'),
        content: Text(
          'Die Vorlage "${template.name}" wird unwiderruflich geloescht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await context.read<ScheduleProvider>().deleteShiftTemplate(templateId);
      if (!mounted) {
        return;
      }
      if (_selectedTemplateId == templateId) {
        _setDirty(() => _selectedTemplateId = null);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schichtvorlage geloescht.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vorlage konnte nicht geloescht werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<ShiftTemplate?> _openTemplateSaveSheet(ShiftTemplate template) {
    return showModalBottomSheet<ShiftTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _ShiftTemplateSaveSheet(template: template),
      ),
    );
  }

  ShiftTemplate? _buildTemplateDraft() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte zuerst einen Schichttitel eingeben.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    final startMinutes = _toMinutes(_startTime);
    final endMinutes = _toMinutes(_endTime);
    // endMinutes < startMinutes ist erlaubt (Übernacht-Vorlage, wird beim
    // Anwenden auf den Folgetag gerollt). Nur identische Zeiten sind ungültig.
    if (endMinutes == startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Start- und Endzeit dürfen nicht identisch sein.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    final sites = context.read<TeamProvider>().sites;
    final selectedTeam =
        widget.teams.where((team) => team.id == _selectedTeamId).firstOrNull;
    final selectedSite =
        sites.where((site) => site.id == _selectedSiteId).firstOrNull;
    final teamName = _teamCtrl.text.trim().isEmpty
        ? selectedTeam?.name
        : _teamCtrl.text.trim();
    final siteName = selectedSite?.name ??
        (_locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim());

    return ShiftTemplate(
      name: title,
      title: title,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      breakMinutes: _parseBreakMinutes(),
      teamId: selectedTeam?.id,
      teamName: teamName,
      siteId: selectedSite?.id,
      siteName: siteName,
      requiredQualificationIds:
          _requiredQualificationIds.toList(growable: false),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      color: _shiftColor,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      _setDirty(
        () => _date = picked,
        refreshAvailability: true,
      );
    }
  }

  String _selectedDaysSummary() {
    final sorted = _selectedDays.toList()..sort();
    if (sorted.isEmpty) {
      return 'Tag waehlen';
    }
    if (sorted.length == 1) {
      return DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(sorted.first);
    }
    return '${sorted.length} Tage · ab '
        '${DateFormat('dd.MM.yyyy', 'de_DE').format(sorted.first)}';
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      _setDirty(
        () => _startTime = picked,
        refreshAvailability: true,
      );
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      _setDirty(
        () => _endTime = picked,
        refreshAvailability: true,
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final shifts = _buildProposedShifts();
    if (shifts == null) {
      return;
    }

    setState(() {
      _validating = true;
      _conflictIssues = const [];
    });

    try {
      final issues = await context.read<ScheduleProvider>().validateShifts(
            shifts,
            recurrencePattern: _recurrencePattern,
            recurrenceEndDate: _recurrenceEndDate,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _validating = false;
        _conflictIssues = issues;
      });
      if (issues.isNotEmpty) {
        return;
      }

      Navigator.of(context).pop(
        _ShiftEditorResult(
          shifts: shifts,
          recurrencePattern: _recurrencePattern,
          recurrenceEndDate: _recurrenceEndDate,
          groupAsSeries: widget.shift == null && _selectedDays.length > 1,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _validating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Konfliktpruefung fehlgeschlagen: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// "Betroffene überspringen" lohnt nur, wenn überhaupt mehr als eine Schicht
  /// vorgeschlagen wird (Mehrtage / mehrere Mitarbeiter / Zusatzbesetzung) und
  /// es eine Neuanlage ist – sonst bliebe nichts zu speichern.
  bool get _canSkipConflicts =>
      widget.shift == null &&
      (_selectedDays.length > 1 ||
          _selectedUserIds.length > 1 ||
          _additionalAssignments.isNotEmpty);

  /// Schlüssel zum Abgleich einer Konflikt-Schicht mit einer vorgeschlagenen
  /// Schicht (Mitarbeiter + Startzeitpunkt identifizieren eine Fan-out-Zelle
  /// eindeutig).
  String _shiftKey(Shift shift) =>
      '${shift.userId}@${shift.startTime.millisecondsSinceEpoch}';

  Future<void> _saveSkippingConflicts() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final proposed = _buildProposedShifts();
    if (proposed == null) {
      return;
    }
    final affectedKeys =
        _conflictIssues.map((issue) => _shiftKey(issue.shift)).toSet();
    final remaining = proposed
        .where((shift) => !affectedKeys.contains(_shiftKey(shift)))
        .toList(growable: false);
    if (remaining.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Alle vorgeschlagenen Schichten sind betroffen – nichts zu '
            'speichern.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() {
      _validating = true;
    });
    try {
      // Erneut prüfen: nach dem Entfernen der Konflikt-Schichten können
      // batch-interne Überschneidungen wegfallen.
      final issues =
          await context.read<ScheduleProvider>().validateShifts(remaining);
      if (!mounted) {
        return;
      }
      setState(() {
        _validating = false;
        _conflictIssues = issues;
      });
      if (issues.isNotEmpty) {
        return;
      }
      Navigator.of(context).pop(
        _ShiftEditorResult(
          shifts: remaining,
          recurrencePattern: RecurrencePattern.none,
          recurrenceEndDate: null,
          groupAsSeries: remaining.length > 1,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _validating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Konfliktpruefung fehlgeschlagen: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  List<Shift>? _buildProposedShifts() {
    final sites = context.read<TeamProvider>().sites;
    final selectedMembers = widget.members
        .where((candidate) => _selectedUserIds.contains(candidate.uid))
        .toList(growable: false);

    if (!_selectedEndDateTime.isAfter(_selectedStartDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Endzeit muss nach Startzeit liegen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    if (!_saveAsUnassigned &&
        selectedMembers.isEmpty &&
        _additionalAssignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte mindestens einen Mitarbeiter einplanen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    // Mehrtage ist anlage-only: im Edit-Modus genau der bearbeitete Tag.
    final days = (widget.shift != null
        ? <DateTime>[_dateOnly(_date)]
        : (_selectedDays.toList()..sort()));
    if (days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte mindestens einen Tag auswaehlen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    final teamName =
        _teamCtrl.text.trim().isEmpty ? null : _teamCtrl.text.trim();
    final selectedSite = sites.firstWhereOrNull(
      (site) => site.id == _selectedSiteId,
    );
    if (selectedSite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte einen Standort auswaehlen.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }
    // Zuletzt benutzten Standort für die nächste Neuanlage merken (UI-Komfort).
    ScheduleProvider.lastUsedSiteId = selectedSite.id;

    // Fan-out begrenzen: bis [_kMaxShiftsPerSave] bleibt das Speichern EIN
    // atomarer Server-Call (kein Teil-Write-Risiko). Zusatzbesetzungen liegen
    // nur am Ankertag und zählen daher einfach.
    final primaryPerDay = _saveAsUnassigned ? 1 : selectedMembers.length;
    final totalShifts =
        primaryPerDay * days.length + _additionalAssignments.length;
    if (totalShifts > _kMaxShiftsPerSave) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Zu viele Schichten auf einmal ($totalShifts). Bitte Tage oder '
            'Mitarbeiter reduzieren (max. $_kMaxShiftsPerSave pro Speichern).',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    final location = selectedSite.name;
    final breakMinutes = _parseBreakMinutes();
    final title = _titleCtrl.text.trim();
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    final quals = _requiredQualificationIds.toList(growable: false);

    if (_saveAsUnassigned) {
      return [
        for (final day in days)
          Shift(
            id: widget.shift?.id,
            orgId: widget.currentUser.orgId,
            userId: '',
            employeeName: 'Freie Schicht',
            title: title,
            startTime: _startDateTimeForDay(day),
            endTime: _endDateTimeForDay(day),
            breakMinutes: breakMinutes,
            teamId: _selectedTeamId,
            team: teamName,
            siteId: selectedSite.id,
            siteName: selectedSite.name,
            location: location,
            requiredQualificationIds: quals,
            notes: notes,
            seriesId: widget.shift?.seriesId,
            recurrencePattern: _recurrencePattern,
            color: _shiftColor,
            status: _status,
            createdByUid: widget.currentUser.uid,
          ),
      ];
    }

    final shifts = <Shift>[
      for (final day in days)
        for (final member in selectedMembers)
          Shift(
            id: widget.shift?.id,
            orgId: widget.currentUser.orgId,
            userId: member.uid,
            employeeName: member.displayName,
            title: title,
            startTime: _startDateTimeForDay(day),
            endTime: _endDateTimeForDay(day),
            breakMinutes: breakMinutes,
            teamId: _selectedTeamId,
            team: teamName,
            siteId: selectedSite.id,
            siteName: selectedSite.name,
            location: location,
            requiredQualificationIds: quals,
            notes: notes,
            seriesId: widget.shift?.seriesId,
            recurrencePattern: _recurrencePattern,
            color: _shiftColor,
            status: _status,
            createdByUid: widget.currentUser.uid,
          ),
    ];

    for (var index = 0; index < _additionalAssignments.length; index++) {
      final draft = _additionalAssignments[index];
      final memberId = draft.memberId?.trim();
      if (memberId == null || memberId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bitte fuer Zusatzbesetzung ${index + 1} einen Mitarbeiter auswaehlen.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return null;
      }
      final member = widget.members
          .where((candidate) => candidate.uid == memberId)
          .firstOrNull;
      if (member == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mitarbeiter fuer Zusatzbesetzung ${index + 1} wurde nicht gefunden.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return null;
      }

      final additionalStart = _dateTimeFor(draft.startTime);
      final additionalEnd = _endDateTimeFor(draft.startTime, draft.endTime);
      if (!additionalEnd.isAfter(additionalStart)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Endzeit muss in Zusatzbesetzung ${index + 1} nach der Startzeit liegen.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return null;
      }

      shifts.add(
        Shift(
          orgId: widget.currentUser.orgId,
          userId: member.uid,
          employeeName: member.displayName,
          title: _titleCtrl.text.trim(),
          startTime: additionalStart,
          endTime: additionalEnd,
          breakMinutes: draft.breakMinutes,
          teamId: _selectedTeamId,
          team: teamName,
          siteId: selectedSite.id,
          siteName: selectedSite.name,
          location: location,
          requiredQualificationIds:
              _requiredQualificationIds.toList(growable: false),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          seriesId: widget.shift?.seriesId,
          recurrencePattern: _recurrencePattern,
          color: _shiftColor,
          status: _status,
          createdByUid: widget.currentUser.uid,
        ),
      );
    }

    return shifts;
  }

  List<ShiftAssigneeAvailability> get _visibleAssigneeAvailability {
    if (_assigneeAvailability.isNotEmpty) {
      return _assigneeAvailability;
    }
    final fallback = widget.members
        .map((member) => ShiftAssigneeAvailability(member: member))
        .toList(growable: false)
      ..sort(
        (a, b) => a.member.displayName.compareTo(b.member.displayName),
      );
    return fallback;
  }

  DateTime get _selectedStartDateTime => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _startTime.hour,
        _startTime.minute,
      );

  DateTime get _selectedEndDateTime =>
      _endDateTimeFor(_startTime, _endTime);

  DateTime _dateTimeFor(TimeOfDay time) => DateTime(
        _date.year,
        _date.month,
        _date.day,
        time.hour,
        time.minute,
      );

  /// Bildet den End-Zeitpunkt zur Start-/Endzeit. Liegt die Endzeit zeitlich
  /// VOR der Startzeit, wird sie als Folgetag interpretiert (Übernacht-Schicht,
  /// z.B. 22:00–06:00). Gleiche Start-/Endzeit bleibt unverändert (= 0 Minuten),
  /// damit die nachgelagerte „Endzeit muss nach Startzeit liegen"-Prüfung greift.
  DateTime _endDateTimeFor(TimeOfDay start, TimeOfDay end) {
    final base = _dateTimeFor(end);
    final startMinutes = _toMinutes(start);
    final endMinutes = _toMinutes(end);
    return endMinutes < startMinutes
        ? base.add(const Duration(days: 1))
        : base;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Start-Zeitpunkt der Schicht für einen konkreten Tag (gewählte Startzeit).
  DateTime _startDateTimeForDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, _startTime.hour, _startTime.minute);

  /// End-Zeitpunkt für einen konkreten Tag; Übernacht-Schichten (Endzeit vor
  /// Startzeit) landen auf dem Folgetag – analog zu [_endDateTimeFor].
  DateTime _endDateTimeForDay(DateTime day) {
    final base =
        DateTime(day.year, day.month, day.day, _endTime.hour, _endTime.minute);
    return _toMinutes(_endTime) < _toMinutes(_startTime)
        ? base.add(const Duration(days: 1))
        : base;
  }

  /// Öffnet den Mehrtage-Picker (Wochentags-Maske + Kalender) und übernimmt die
  /// Auswahl. Hält die Invariante: nicht leer, datums-normalisiert, [_date] =
  /// frühester Tag (Ankertag für Uhrzeiten/Zusatzbesetzungen).
  Future<void> _openMultiDayPicker() async {
    final picked = await showModalBottomSheet<Set<DateTime>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _MultiDayPickerSheet(
        initialDays: _selectedDays,
        anchorDay: _dateOnly(_date),
      ),
    );
    if (picked == null || picked.isEmpty) {
      return;
    }
    final sorted = picked.toList()..sort();
    _setDirty(
      () {
        _selectedDays = picked;
        _date = sorted.first;
      },
      refreshAvailability: true,
    );
  }

  void _addAdditionalAssignment() {
    _setDirty(() {
      _additionalAssignments = [
        ..._additionalAssignments,
        _AdditionalShiftAssignmentDraft(
          id: _nextAdditionalAssignmentDraftId++,
          startTime: _startTime,
          endTime: _endTime,
          breakMinutes: _parseBreakMinutes(),
        ),
      ];
    });
  }

  void _removeAdditionalAssignment(int draftId) {
    _setDirty(() {
      _additionalAssignments = _additionalAssignments
          .where((draft) => draft.id != draftId)
          .toList(growable: false);
    });
  }

  void _updateAdditionalAssignment(
    int draftId,
    _AdditionalShiftAssignmentDraft Function(
      _AdditionalShiftAssignmentDraft draft,
    ) update,
  ) {
    _setDirty(() {
      _additionalAssignments = _additionalAssignments
          .map((draft) => draft.id == draftId ? update(draft) : draft)
          .toList(growable: false);
    });
  }

  Future<void> _pickAdditionalStart(int draftId) async {
    final draft = _additionalAssignments
        .where((candidate) => candidate.id == draftId)
        .firstOrNull;
    if (draft == null) {
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: draft.startTime,
    );
    if (picked == null) {
      return;
    }
    _updateAdditionalAssignment(
      draftId,
      (currentDraft) => currentDraft.copyWith(startTime: picked),
    );
  }

  Future<void> _pickAdditionalEnd(int draftId) async {
    final draft = _additionalAssignments
        .where((candidate) => candidate.id == draftId)
        .firstOrNull;
    if (draft == null) {
      return;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: draft.endTime,
    );
    if (picked == null) {
      return;
    }
    _updateAdditionalAssignment(
      draftId,
      (currentDraft) => currentDraft.copyWith(endTime: picked),
    );
  }

  Future<void> _refreshAssigneeAvailability() async {
    if (_saveAsUnassigned) {
      setState(() {
        _loadingAvailability = false;
        _assigneeAvailability = const [];
      });
      return;
    }
    final requestId = ++_availabilityRequestId;
    final startTime = _selectedStartDateTime;
    final endTime = _selectedEndDateTime;

    if (!endTime.isAfter(startTime) || widget.members.isEmpty) {
      if (!mounted || requestId != _availabilityRequestId) {
        return;
      }
      setState(() {
        _loadingAvailability = false;
        _assigneeAvailability = widget.members
            .map((member) => ShiftAssigneeAvailability(member: member))
            .toList(growable: false);
      });
      return;
    }

    setState(() => _loadingAvailability = true);

    try {
      final availability =
          await context.read<ScheduleProvider>().loadAssigneeAvailability(
                members: widget.members,
                startTime: startTime,
                endTime: endTime,
                breakMinutes: _parseBreakMinutes(),
                siteId: _selectedSiteId,
                siteName: _locationCtrl.text.trim().isEmpty
                    ? null
                    : _locationCtrl.text.trim(),
                requiredQualificationIds:
                    _requiredQualificationIds.toList(growable: false),
                shiftTitle: _titleCtrl.text.trim(),
                excludeShiftId: widget.shift?.id,
              );
      if (!mounted || requestId != _availabilityRequestId) {
        return;
      }
      setState(() {
        _loadingAvailability = false;
        _assigneeAvailability = availability;
        _selectedUserIds.removeWhere(
          (userId) => availability.any(
            (entry) => entry.member.uid == userId && !entry.isAvailable,
          ),
        );
      });
    } catch (error) {
      if (!mounted || requestId != _availabilityRequestId) {
        return;
      }
      setState(() => _loadingAvailability = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Verfuegbarkeiten konnten nicht geladen werden: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  double _parseBreakMinutes() {
    return _parseBreakMinutesValue(_breakCtrl.text);
  }

  double _parseBreakMinutesValue(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Abschnitts-Builder fuer den modernisierten Schicht-Editor (klare Abschnitte:
  // Eckdaten -> Besetzung -> Details, kompakte Vorlagen-Leiste, fixierter
  // Speichern-Button). Reine Layout-Umstrukturierung; die Formular-/Speicher-
  // Logik (Controller, _setDirty, Validierung, _buildProposedShifts) bleibt
  // unveraendert.
  // ---------------------------------------------------------------------------

  Widget _buildTemplateBar(
    BuildContext context,
    List<ShiftTemplate> shiftTemplates,
    ShiftTemplate? selectedTemplate,
  ) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: spacing.sm,
          runSpacing: spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: shiftTemplates.isEmpty
                  ? null
                  : () => _pickTemplate(shiftTemplates),
              icon: const Icon(Icons.bookmarks_outlined),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  selectedTemplate?.name ?? 'Aus Vorlage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saveCurrentAsTemplate,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Als Vorlage'),
            ),
            if (selectedTemplate != null)
              PopupMenuButton<String>(
                tooltip: 'Vorlagen-Aktionen',
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  if (value == 'update') {
                    _updateTemplate(selectedTemplate);
                  } else if (value == 'delete') {
                    _deleteTemplate(selectedTemplate);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'update',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Vorlage aktualisieren'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Vorlage löschen'),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (selectedTemplate != null) ...[
          SizedBox(height: spacing.sm),
          Text(
            _formatShiftTemplateSummary(context, selectedTemplate),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCoreSection(
    BuildContext context,
    List<SiteDefinition> sites,
    bool isEdit,
  ) {
    final spacing = context.spacing;
    return _EditorSection(
      title: 'Eckdaten',
      icon: Icons.event_note_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Schichttitel',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return 'Bitte Titel eingeben';
              }
              return null;
            },
          ),
          SizedBox(height: spacing.md),
          if (isEdit)
            _PickerField(
              icon: Icons.calendar_today,
              label: 'Datum',
              value: DateFormat('dd.MM.yyyy', 'de_DE').format(_date),
              onTap: _pickDate,
            )
          else
            _PickerField(
              icon: Icons.event_available,
              label: 'Tage',
              value: _selectedDaysSummary(),
              onTap: _openMultiDayPicker,
            ),
          SizedBox(height: spacing.md),
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  icon: Icons.login,
                  label: 'Beginn',
                  value: _startTime.format(context),
                  onTap: _pickStart,
                  showChevron: false,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: _PickerField(
                  icon: Icons.logout,
                  label: 'Ende',
                  value: _endTime.format(context),
                  onTap: _pickEnd,
                  showChevron: false,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          if (sites.isEmpty) ...[
            TextFormField(
              controller: _breakCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Pause in Minuten',
                prefixIcon: Icon(Icons.coffee_outlined),
              ),
              onChanged: (_) => _setDirty(() {}, refreshAvailability: true),
            ),
            SizedBox(height: spacing.md),
            const _EditorNoticeCard(
              icon: Icons.location_off_outlined,
              title: 'Noch keine Standorte angelegt',
              message:
                  'Bitte hinterlege zuerst Standorte in der Teamverwaltung, um die Schicht einem Standort zuzuordnen.',
              tone: _EditorNoticeTone.warning,
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _breakCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Pause (Min.)',
                      prefixIcon: Icon(Icons.coffee_outlined),
                    ),
                    onChanged: (_) =>
                        _setDirty(() {}, refreshAvailability: true),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedSiteId,
                    decoration: const InputDecoration(
                      labelText: 'Standort',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    items: [
                      for (final site in sites)
                        DropdownMenuItem(
                          value: site.id,
                          child: Text(
                            site.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      _setDirty(
                        () {
                          _selectedSiteId = value;
                          final selected = sites
                              .where((site) => site.id == value)
                              .firstOrNull;
                          _locationCtrl.text = selected?.name ?? '';
                        },
                        refreshAvailability: true,
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStaffingSection(
    BuildContext context, {
    required bool isEdit,
    required List<ShiftAssigneeAvailability> availabilityItems,
    required List<ShiftAssigneeAvailability> availableMembers,
    required List<ShiftAssigneeAvailability> unavailableMembers,
    required String? selectedUserId,
    required ShiftAssigneeAvailability? selectedAvailability,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final showAdditional = !_saveAsUnassigned && widget.members.isNotEmpty;

    return _EditorSection(
      title: 'Besetzung',
      icon: Icons.groups_outlined,
      trailing: (!_saveAsUnassigned && !isEdit && widget.members.isNotEmpty)
          ? _EditorCountBadge(label: '${_selectedUserIds.length} ausgewaehlt')
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Mitarbeiter'),
                  icon: Icon(Icons.person_outline),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Freie Schicht'),
                  icon: Icon(Icons.event_available_outlined),
                ),
              ],
              selected: {_saveAsUnassigned},
              onSelectionChanged: (selection) {
                final unassigned = selection.first;
                if (unassigned == _saveAsUnassigned) {
                  return;
                }
                if (unassigned) {
                  _setDirty(() {
                    _saveAsUnassigned = true;
                    _selectedUserIds = <String>{};
                    _additionalAssignments = const [];
                  });
                } else {
                  _setDirty(
                    () {
                      _saveAsUnassigned = false;
                      if (_selectedUserIds.isEmpty &&
                          widget.members.isNotEmpty) {
                        _selectedUserIds = {widget.members.first.uid};
                      }
                    },
                    refreshAvailability: true,
                  );
                }
              },
            ),
          ),
          SizedBox(height: spacing.md),
          if (_saveAsUnassigned)
            Text(
              'Diese Schicht wird ohne feste Zuordnung gespeichert und erscheint im Bereich "Freie Schichten".',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else if (isEdit) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: selectedUserId,
              decoration: const InputDecoration(
                labelText: 'Mitarbeiter',
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: [
                for (final availability in availabilityItems)
                  DropdownMenuItem(
                    value: availability.member.uid,
                    enabled: availability.isAvailable ||
                        availability.member.uid == selectedUserId,
                    child: Text(
                      availability.isAvailable ||
                              availability.member.uid == selectedUserId
                          ? availability.member.displayName
                          : '${availability.member.displayName} · nicht verfuegbar',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _setDirty(() => _selectedUserIds = {value});
                }
              },
            ),
            if (_loadingAvailability) ...[
              SizedBox(height: spacing.md),
              const LinearProgressIndicator(),
            ],
            if (selectedAvailability != null &&
                !selectedAvailability.isAvailable) ...[
              SizedBox(height: spacing.md),
              _buildBlockingNotice(context, selectedAvailability),
            ],
          ] else
            _buildMemberPicker(context, availableMembers, unavailableMembers),
          if (showAdditional) ..._buildAdditionalAssignments(context),
        ],
      ),
    );
  }

  Widget _buildMemberPicker(
    BuildContext context,
    List<ShiftAssigneeAvailability> availableMembers,
    List<ShiftAssigneeAvailability> unavailableMembers,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;

    if (widget.members.isEmpty) {
      return const _EditorNoticeCard(
        icon: Icons.people_outline_rounded,
        title: 'Keine aktiven Mitarbeiter vorhanden',
        message: 'Im Team sind aktuell keine aktiven Mitarbeiter hinterlegt.',
        tone: _EditorNoticeTone.warning,
      );
    }

    // Eine kompakte, scannbare Liste: frei (auswaehlbar) zuerst, dann gesperrt
    // (Sperrgruende nur auf Tipp). Lange Teams werden gekappt -> kein endloses
    // Scrollen mehr durch die frueheren Verfuegbarkeits-Grosskarten.
    final ordered = [...availableMembers, ...unavailableMembers];
    const cap = 8;
    final showAll = _showAllMembers || ordered.length <= cap;
    final visible = showAll ? ordered : ordered.take(cap).toList();
    final hidden = ordered.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: spacing.sm,
                runSpacing: spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _EditorCountBadge(
                    label: '${availableMembers.length} frei',
                    tone: _EditorBadgeTone.success,
                  ),
                  if (unavailableMembers.isNotEmpty)
                    _EditorCountBadge(
                      label: '${unavailableMembers.length} gesperrt',
                      tone: _EditorBadgeTone.warning,
                    ),
                ],
              ),
            ),
            if (availableMembers.isNotEmpty)
              TextButton.icon(
                onPressed: () => _setDirty(
                  () => _selectedUserIds = availableMembers
                      .map((entry) => entry.member.uid)
                      .toSet(),
                ),
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Alle freien'),
              ),
          ],
        ),
        if (_loadingAvailability) ...[
          SizedBox(height: spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(context.radii.pill),
            child: const LinearProgressIndicator(minHeight: 4),
          ),
        ],
        SizedBox(height: spacing.sm + spacing.xs),
        if (availableMembers.isEmpty && !_loadingAvailability) ...[
          Text(
            'Aktuell kein freier Mitarbeiter im gewaehlten Zeitfenster. Passe Zeiten, Standort oder Qualifikationen an – oder speichere die Schicht als freie Schicht.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.sm + spacing.xs),
        ],
        for (final availability in visible)
          _buildMemberTile(context, availability),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAllMembers = true),
              icon: const Icon(Icons.expand_more, size: 18),
              label: Text('Weitere $hidden anzeigen'),
            ),
          )
        else if (showAll && ordered.length > cap)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAllMembers = false),
              icon: const Icon(Icons.expand_less, size: 18),
              label: const Text('Weniger anzeigen'),
            ),
          ),
      ],
    );
  }

  /// Eine schlanke Mitarbeiter-Zeile: farbiger Status (frei/Warnung/gesperrt),
  /// Name + einzeiliger Grund. Frei = antippbar (Auswahl), gesperrt = antippbar
  /// (Sperrgruende ein-/ausklappen). Ersetzt die fruehere Verfuegbarkeits-
  /// Grosskarte und haelt den Besetzungs-Abschnitt kurz.
  Widget _buildMemberTile(BuildContext context, ShiftAssigneeAvailability av) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final spacing = context.spacing;
    final radius = BorderRadius.circular(context.radii.md);

    final isAvailable = av.isAvailable;
    final reasons = isAvailable
        ? const <_AvailabilityReason>[]
        : _buildAssigneeAvailabilityReasons(av);
    final hasBlocking =
        reasons.any((reason) => reason.tone == _AvailabilityReasonTone.blocking);
    final statusColor = isAvailable
        ? appColors.success
        : (hasBlocking ? colorScheme.error : appColors.warning);
    final selected = _selectedUserIds.contains(av.member.uid);
    final expanded = _expandedMemberIds.contains(av.member.uid);
    final summary = isAvailable
        ? 'Verfuegbar'
        : (reasons.isEmpty ? 'Nicht verfuegbar' : reasons.first.message);
    final extra = reasons.length > 1 ? reasons.length - 1 : 0;
    final statusIcon = isAvailable
        ? Icons.check_circle
        : (hasBlocking ? Icons.block : Icons.warning_amber_rounded);

    return Container(
      margin: EdgeInsets.only(bottom: spacing.sm),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerLow,
        border: Border.all(
          color: selected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.7),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: radius,
            onTap: isAvailable
                ? () => _setDirty(() {
                      if (selected) {
                        _selectedUserIds.remove(av.member.uid);
                      } else {
                        _selectedUserIds.add(av.member.uid);
                      }
                    })
                : () => setState(() {
                      if (expanded) {
                        _expandedMemberIds.remove(av.member.uid);
                      } else {
                        _expandedMemberIds.add(av.member.uid);
                      }
                    }),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.sm + spacing.xs,
                vertical: spacing.sm,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: statusColor.withValues(alpha: 0.16),
                    child: Text(
                      _initialsForName(av.member.displayName),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.sm + spacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          av.member.displayName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: spacing.xxs),
                        Row(
                          children: [
                            Icon(statusIcon, size: 14, color: statusColor),
                            SizedBox(width: spacing.xs),
                            Flexible(
                              child: Text(
                                summary,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (extra > 0) ...[
                              SizedBox(width: spacing.xs),
                              Text(
                                '+$extra',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  if (isAvailable)
                    Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color:
                          selected ? colorScheme.primary : colorScheme.outline,
                    )
                  else
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          if (!isAvailable && expanded)
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.sm + spacing.xs,
                0,
                spacing.sm + spacing.xs,
                spacing.sm + spacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(
                    height: spacing.md,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  ..._buildReasonLines(context, reasons),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Kompakte Sperrgrund-Zeilen (Icon + Text), genutzt im aufgeklappten Tile und
  /// im Bearbeiten-Modus-Hinweis. [textColor] fuer getoente Hintergruende.
  List<Widget> _buildReasonLines(
    BuildContext context,
    List<_AvailabilityReason> reasons, {
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final spacing = context.spacing;
    return [
      for (var i = 0; i < reasons.length; i++) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              reasons[i].icon,
              size: 16,
              color: reasons[i].tone == _AvailabilityReasonTone.blocking
                  ? colorScheme.error
                  : appColors.warning,
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                reasons[i].message,
                style: theme.textTheme.bodySmall?.copyWith(color: textColor),
              ),
            ),
          ],
        ),
        if (i < reasons.length - 1) SizedBox(height: spacing.xs),
      ],
    ];
  }

  /// Kompakter Sperr-Hinweis fuer den Bearbeiten-Modus (ausgewaehlter
  /// Mitarbeiter nicht verfuegbar) – schlanke getoente Box statt Grosskarte.
  Widget _buildBlockingNotice(
    BuildContext context,
    ShiftAssigneeAvailability availability,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = theme.appColors;
    final spacing = context.spacing;
    final reasons = _buildAssigneeAvailabilityReasons(availability);
    final hasBlocking =
        reasons.any((reason) => reason.tone == _AvailabilityReasonTone.blocking);
    final accent = hasBlocking ? colorScheme.error : appColors.warning;
    final background =
        hasBlocking ? colorScheme.errorContainer : appColors.warningContainer;
    final foreground = hasBlocking
        ? colorScheme.onErrorContainer
        : appColors.onWarningContainer;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm + spacing.xs),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasBlocking ? Icons.block : Icons.warning_amber_rounded,
                size: 18,
                color: accent,
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  'Ausgewaehlter Mitarbeiter ist nicht verfuegbar',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          ..._buildReasonLines(context, reasons, textColor: foreground),
        ],
      ),
    );
  }

  List<Widget> _buildAdditionalAssignments(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return [
      Divider(height: spacing.lg, color: theme.colorScheme.outlineVariant),
      Wrap(
        spacing: spacing.sm + spacing.xxs,
        runSpacing: spacing.sm + spacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Weitere Besetzungen',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          _EditorCountBadge(
            label:
                '${_additionalAssignments.length} Zusatzbesetzung${_additionalAssignments.length == 1 ? '' : 'en'}',
          ),
          FilledButton.tonalIcon(
            onPressed: _addAdditionalAssignment,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Person hinzufuegen'),
          ),
        ],
      ),
      SizedBox(height: spacing.sm + spacing.xxs),
      Text(
        'Titel, Standort, Arbeitsbereich, Qualifikationen, Notiz, Status und Farbe werden vom Hauptblock uebernommen. Fuer jede Zusatzbesetzung kannst du einen eigenen Mitarbeiter und eigene Zeiten definieren. Konflikte werden beim Speichern gemeinsam geprueft.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      SizedBox(height: spacing.md),
      if (_additionalAssignments.isEmpty)
        const _EditorNoticeCard(
          icon: Icons.schedule_send_outlined,
          title: 'Keine Zusatzbesetzung angelegt',
          message:
              'Nutze weitere Besetzungen, wenn dieselbe Schicht von mehreren Personen in unterschiedlichen Zeitfenstern uebernommen wird, zum Beispiel 08:00 - 10:00 und 10:00 - 13:00.',
          tone: _EditorNoticeTone.info,
        )
      else
        for (var index = 0; index < _additionalAssignments.length; index++) ...[
          _AdditionalShiftAssignmentCard(
            key: ValueKey(
              'additional-assignment-${_additionalAssignments[index].id}',
            ),
            index: index,
            draft: _additionalAssignments[index],
            members: widget.members,
            onMemberChanged: (memberId) => _updateAdditionalAssignment(
              _additionalAssignments[index].id,
              (draft) => draft.copyWith(memberId: memberId),
            ),
            onRemove: () => _removeAdditionalAssignment(
              _additionalAssignments[index].id,
            ),
            onPickStart: () => _pickAdditionalStart(
              _additionalAssignments[index].id,
            ),
            onPickEnd: () => _pickAdditionalEnd(
              _additionalAssignments[index].id,
            ),
            onBreakChanged: (value) => _updateAdditionalAssignment(
              _additionalAssignments[index].id,
              (draft) => draft.copyWith(
                breakMinutes: _parseBreakMinutesValue(value),
              ),
            ),
          ),
          if (index < _additionalAssignments.length - 1)
            SizedBox(height: spacing.sm + spacing.xs),
        ],
    ];
  }

  Widget _buildDetailsSection(
    BuildContext context, {
    required List<QualificationDefinition> qualifications,
    required TeamDefinition? selectedTeam,
    required bool isEdit,
  }) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return _EditorSection(
      title: 'Details',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _selectedTeamId,
            decoration: const InputDecoration(
              labelText: 'Gespeichertes Team',
              prefixIcon: Icon(Icons.groups_2_outlined),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Kein Team'),
              ),
              for (final team in widget.teams)
                DropdownMenuItem<String?>(
                  value: team.id,
                  child: Text(team.name),
                ),
            ],
            onChanged: (value) {
              _setDirty(
                () {
                  _selectedTeamId = value;
                  if (value == null) {
                    return;
                  }
                  final team = widget.teams
                      .where((candidate) => candidate.id == value)
                      .firstOrNull;
                  if (team == null) {
                    return;
                  }
                  _teamCtrl.text = team.name;
                  if (!isEdit && team.memberIds.isNotEmpty) {
                    _selectedUserIds = widget.members
                        .where((member) => team.memberIds.contains(member.uid))
                        .map((member) => member.uid)
                        .toSet();
                  }
                },
                refreshAvailability: true,
              );
            },
          ),
          if (selectedTeam != null &&
              selectedTeam.memberIds.isNotEmpty &&
              !isEdit) ...[
            SizedBox(height: spacing.sm),
            Text(
              'Teammitglieder werden automatisch uebernommen. Belegte Mitarbeiter werden darunter separat mit Konfliktgrund angezeigt.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          SizedBox(height: spacing.md),
          TextFormField(
            controller: _teamCtrl,
            decoration: const InputDecoration(
              labelText: 'Team / Bereich',
              prefixIcon: Icon(Icons.group_work_outlined),
            ),
          ),
          if (qualifications.isNotEmpty) ...[
            SizedBox(height: spacing.md),
            Text(
              'Erforderliche Qualifikationen',
              style: theme.textTheme.titleSmall,
            ),
            SizedBox(height: spacing.sm),
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              children: [
                for (final qualification in qualifications)
                  FilterChip(
                    label: Text(qualification.name),
                    selected:
                        _requiredQualificationIds.contains(qualification.id),
                    onSelected: (selected) {
                      _setDirty(
                        () {
                          if (qualification.id == null) {
                            return;
                          }
                          if (selected) {
                            _requiredQualificationIds.add(qualification.id!);
                          } else {
                            _requiredQualificationIds.remove(qualification.id);
                          }
                        },
                        refreshAvailability: true,
                      );
                    },
                  ),
              ],
            ),
          ],
          SizedBox(height: spacing.md),
          DropdownButtonFormField<ShiftStatus>(
            isExpanded: true,
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
            items: [
              for (final status in ShiftStatus.values)
                DropdownMenuItem(
                  value: status,
                  child: Text(status.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                _setDirty(() => _status = value);
              }
            },
          ),
          // Wiederholung/Serien werden über den Mehrtage-Picker (mehrere Tage
          // gleichzeitig anlegen) abgebildet, nicht über ein editierbares
          // Wiederholungs-Muster. Bei bestehenden Serien-Schichten nur als
          // Read-only-Hinweis anzeigen.
          if (isEdit && _recurrencePattern != RecurrencePattern.none) ...[
            SizedBox(height: spacing.md),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Wiederholung',
                prefixIcon: Icon(Icons.repeat),
                border: OutlineInputBorder(),
              ),
              child: Text(_recurrencePattern.label),
            ),
          ],
          SizedBox(height: spacing.md),
          Text('Farbe', style: theme.textTheme.titleSmall),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              for (final hex in const [
                '#4CAF50',
                '#2196F3',
                '#FF9800',
                '#E91E63',
                '#9C27B0',
                '#00BCD4',
                '#795548',
                '#607D8B',
              ])
                InkWell(
                  onTap: () => _setDirty(
                    () => _shiftColor = _shiftColor == hex ? null : hex,
                  ),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              Color(int.parse(hex.replaceFirst('#', '0xFF'))),
                          shape: BoxShape.circle,
                          border: _shiftColor == hex
                              ? Border.all(
                                  color: theme.colorScheme.onSurface,
                                  width: 3,
                                )
                              : Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                        ),
                        child: _shiftColor == hex
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: spacing.md),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notiz',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.errorContainer,
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _conflictIssues.length == 1
                  ? '1 Konflikt gefunden'
                  : '${_conflictIssues.length} Konflikte gefunden',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onErrorContainer,
              ),
            ),
            SizedBox(height: spacing.sm),
            Text(
              'Die betroffenen Schichten werden unten aufgelistet. Passe Zeiten, Mitarbeiter oder Abwesenheiten an und pruefe erneut.',
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
            SizedBox(height: spacing.md - spacing.xs),
            _ShiftConflictList(
              issues: _conflictIssues,
              textColor: colorScheme.onErrorContainer,
            ),
            if (_canSkipConflicts) ...[
              SizedBox(height: spacing.md - spacing.xs),
              OutlinedButton.icon(
                onPressed: _validating ? null : _saveSkippingConflicts,
                icon: const Icon(Icons.playlist_add_check),
                label: const Text(
                  'Betroffene ueberspringen und Rest speichern',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onErrorContainer,
                  side: BorderSide(
                    color:
                        colorScheme.onErrorContainer.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isEdit) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return Container(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm + spacing.xs,
        spacing.md,
        spacing.sm + spacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      // top:false -> nur der untere Sicherheitsabstand (Home-Indicator); der
      // Tastatur-Inset traegt bereits das aeussere Padding(viewInsets) am
      // Aufrufer, daher hier kein Doppelzaehlen.
      child: SafeArea(
        top: false,
        child: FilledButton.icon(
          onPressed: _validating ? null : _save,
          icon: _validating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(
            _validating
                ? 'Pruefe Konflikte...'
                : (isEdit ? 'Aktualisieren' : 'Speichern'),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ),
    );
  }
}

class _AdditionalShiftAssignmentCard extends StatelessWidget {
  const _AdditionalShiftAssignmentCard({
    super.key,
    required this.index,
    required this.draft,
    required this.members,
    required this.onMemberChanged,
    required this.onRemove,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onBreakChanged,
  });

  final int index;
  final _AdditionalShiftAssignmentDraft draft;
  final List<AppUserProfile> members;
  final ValueChanged<String?> onMemberChanged;
  final VoidCallback onRemove;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final ValueChanged<String> onBreakChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedMember = members
        .where((candidate) => candidate.uid == draft.memberId)
        .firstOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Zusatzbesetzung ${index + 1}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (selectedMember != null)
                      _EditorCountBadge(
                        label: selectedMember.role.label,
                        tone: _EditorBadgeTone.neutral,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Zusatzbesetzung entfernen',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: draft.memberId,
            decoration: const InputDecoration(
              labelText: 'Mitarbeiter',
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: [
              for (final member in members)
                DropdownMenuItem(
                  value: member.uid,
                  child: Text(member.displayName),
                ),
            ],
            onChanged: onMemberChanged,
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Beginn'),
                  trailing: Text(draft.startTime.format(context)),
                  onTap: onPickStart,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Ende'),
                  trailing: Text(draft.endTime.format(context)),
                  onTap: onPickEnd,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('additional-break-${draft.id}'),
            initialValue: _formatBreakMinutes(draft.breakMinutes),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Pause in Minuten',
              prefixIcon: Icon(Icons.coffee_outlined),
            ),
            onChanged: onBreakChanged,
          ),
        ],
      ),
    );
  }
}

/// Tokenisierte Abschnittskarte des Schicht-Editors (klare Abschnitte:
/// Eckdaten/Besetzung/Details). Kopf mit Icon + fettem Titel + optionaler
/// Aktion rechts ([trailing]) auf Basis einer [Card]; Abstaende/Groessen aus
/// den Design-Tokens.
class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.spacing;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: context.iconSizes.md,
                  color: theme.colorScheme.primary,
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            SizedBox(height: spacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Antippbares Feld im Eingabefeld-Look (Rahmen + Label + Wert), z. B. fuer
/// Datum/Tage und Beginn/Ende. Modernisiert die fruehere [ListTile]-Variante
/// und erlaubt eine kompakte Nebeneinander-Anordnung (Beginn|Ende). [showChevron]
/// blendet den Pfeil aus, wenn das Feld in einer Zeile mehrfach steht.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spacing = context.spacing;
    final radius = BorderRadius.circular(context.radii.md);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.sm + spacing.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: context.iconSizes.md,
              color: colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: spacing.sm + spacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: spacing.xxs),
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (showChevron)
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Öffnet das Tausch-Anfrage-Sheet für die eigene [shift]: Auswahl einer
/// Kollegenschicht (Tausch) oder eines Kollegen, der übernimmt (Gutschrift),
/// und Versand der Anfrage. Zeigt Erfolg/Fehler selbst per SnackBar.
Future<void> showSwapRequestSheet(BuildContext context, Shift shift) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _SwapRequestSheet(shift: shift),
  );
}

class _SwapRequestSheet extends StatefulWidget {
  const _SwapRequestSheet({required this.shift});

  final Shift shift;

  @override
  State<_SwapRequestSheet> createState() => _SwapRequestSheetState();
}

class _SwapRequestSheetState extends State<_SwapRequestSheet> {
  SwapKind _kind = SwapKind.exchange;
  bool _loading = true;
  bool _submitting = false;
  List<Shift> _candidates = const [];
  Shift? _selectedShift;
  String? _selectedMemberUid;
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    final schedule = context.read<ScheduleProvider>();
    // Aktueller + nächster Monat: deckt Tausch und „nächsten Monat regeln" ab.
    final base = widget.shift.startTime;
    final start = DateTime(base.year, base.month, 1);
    final end = DateTime(base.year, base.month + 2, 1);
    try {
      final candidates = await schedule.getSwappableShiftsInRange(start, end);
      if (!mounted) return;
      setState(() {
        _candidates = candidates
            .where((candidate) => candidate.id != widget.shift.id)
            .toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _candidates = const [];
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final schedule = context.read<ScheduleProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ShiftSwapRequest request;
    if (_kind == SwapKind.exchange) {
      final target = _selectedShift;
      if (target == null) {
        return;
      }
      request = ShiftSwapRequest(
        orgId: widget.shift.orgId,
        requesterUid: widget.shift.userId,
        requesterName: widget.shift.employeeName,
        requesterShiftId: widget.shift.id ?? '',
        targetUid: target.userId,
        targetName: target.employeeName,
        targetShiftId: target.id,
        kind: SwapKind.exchange,
        requesterShiftStart: widget.shift.startTime,
        note: _noteController.text,
      );
    } else {
      final memberUid = _selectedMemberUid;
      if (memberUid == null) {
        return;
      }
      final memberName = schedule.orgMembers
              .where((member) => member.uid == memberUid)
              .map((member) => member.displayName)
              .firstOrNull ??
          '';
      request = ShiftSwapRequest(
        orgId: widget.shift.orgId,
        requesterUid: widget.shift.userId,
        requesterName: widget.shift.employeeName,
        requesterShiftId: widget.shift.id ?? '',
        targetUid: memberUid,
        targetName: memberName,
        kind: SwapKind.giveAway,
        requesterShiftStart: widget.shift.startTime,
        note: _noteController.text,
      );
    }

    setState(() => _submitting = true);
    try {
      await schedule.submitShiftSwapRequest(request);
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Tauschanfrage gesendet')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = context.watch<ScheduleProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final startFmt = DateFormat('EEE, dd.MM. HH:mm', 'de_DE');
    final endFmt = DateFormat('HH:mm', 'de_DE');
    final ownUid = widget.shift.userId;
    final members = schedule.orgMembers
        .where((member) => member.uid != ownUid && member.isActive)
        .toList(growable: false)
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    final canSubmit = !_submitting &&
        (_kind == SwapKind.exchange
            ? _selectedShift != null
            : _selectedMemberUid != null);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tausch anfragen',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Deine Schicht: ${widget.shift.title} · '
              '${startFmt.format(widget.shift.startTime)} – '
              '${endFmt.format(widget.shift.endTime)}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            SegmentedButton<SwapKind>(
              segments: const [
                ButtonSegment(
                  value: SwapKind.exchange,
                  label: Text('Tauschen'),
                  icon: Icon(Icons.swap_horiz),
                ),
                ButtonSegment(
                  value: SwapKind.giveAway,
                  label: Text('Abgeben'),
                  icon: Icon(Icons.redo),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _submitting
                  ? null
                  : (selection) =>
                      setState(() => _kind = selection.first),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _kind == SwapKind.exchange
                  ? _buildExchangeList(startFmt, endFmt, colorScheme)
                  : _buildGiveAwayList(members, colorScheme),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              enabled: !_submitting,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSubmit ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'Sende…' : 'Anfrage senden'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExchangeList(
    DateFormat startFmt,
    DateFormat endFmt,
    ColorScheme colorScheme,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Keine tauschbaren Schichten der Kollegen im aktuellen und nächsten '
          'Monat gefunden. Du kannst die Schicht stattdessen „Abgeben".',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _candidates.length,
      itemBuilder: (context, index) {
        final candidate = _candidates[index];
        final selected = _selectedShift?.id == candidate.id;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: selected ? colorScheme.secondaryContainer : null,
          child: ListTile(
            leading: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? colorScheme.primary : colorScheme.outline,
            ),
            title: Text(candidate.employeeName),
            subtitle: Text(
              '${candidate.title} · ${startFmt.format(candidate.startTime)} – '
              '${endFmt.format(candidate.endTime)}'
              '${candidate.effectiveSiteLabel == null ? '' : '\n${candidate.effectiveSiteLabel}'}',
            ),
            isThreeLine: candidate.effectiveSiteLabel != null,
            onTap: _submitting
                ? null
                : () => setState(() => _selectedShift = candidate),
          ),
        );
      },
    );
  }

  Widget _buildGiveAwayList(
    List<AppUserProfile> members,
    ColorScheme colorScheme,
  ) {
    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Keine Kollegen verfügbar.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Der Kollege übernimmt deine Schicht – ohne Gegenleistung. Es '
            'entsteht eine Gutschrift, die nächsten Monat eingelöst wird.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              final selected = _selectedMemberUid == member.uid;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: selected ? colorScheme.secondaryContainer : null,
                child: ListTile(
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.person_outline,
                    color:
                        selected ? colorScheme.primary : colorScheme.outline,
                  ),
                  title: Text(member.displayName),
                  onTap: _submitting
                      ? null
                      : () =>
                          setState(() => _selectedMemberUid = member.uid),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
