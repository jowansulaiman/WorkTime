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


class _ShiftEditorResult {
  const _ShiftEditorResult({
    required this.shifts,
    required this.recurrencePattern,
    required this.recurrenceEndDate,
  });

  final List<Shift> shifts;
  final RecurrencePattern recurrencePattern;
  final DateTime? recurrenceEndDate;
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
    final site = sites.firstWhereOrNull(
      (candidate) =>
          candidate.id == _selectedSiteId ||
          candidate.name.trim().toLowerCase() ==
              _locationCtrl.text.trim().toLowerCase(),
    );
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? 'Schicht bearbeiten' : 'Neue Schicht',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Schichtvorlagen',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        _EditorCountBadge(
                          label:
                              '${shiftTemplates.length} Vorlage${shiftTemplates.length == 1 ? '' : 'n'}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      selectedTemplate == null
                          ? 'Speichere haeufige Schichten als Vorlage oder uebernimm bestehende Einstellungen mit einem Tippen.'
                          : 'Aktive Vorlage: ${selectedTemplate.name}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: shiftTemplates.isEmpty
                              ? null
                              : () => _pickTemplate(shiftTemplates),
                          icon: const Icon(Icons.bookmarks_outlined),
                          label: Text(
                            selectedTemplate?.name ?? 'Aus Vorlage uebernehmen',
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _saveCurrentAsTemplate,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Als Vorlage speichern'),
                        ),
                        if (selectedTemplate != null) ...[
                          FilledButton.tonalIcon(
                            onPressed: () => _updateTemplate(selectedTemplate),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Vorlage aktualisieren'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _deleteTemplate(selectedTemplate),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Vorlage loeschen'),
                          ),
                        ],
                      ],
                    ),
                    if (selectedTemplate != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _formatShiftTemplateSummary(context, selectedTemplate),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ] else if (shiftTemplates.isEmpty) ...[
                      const SizedBox(height: 12),
                      const _EditorNoticeCard(
                        icon: Icons.bookmark_border_outlined,
                        title: 'Noch keine Schichtvorlagen vorhanden',
                        message:
                            'Lege aus dem aktuellen Formular eine Vorlage an, um wiederkehrende Schichten schneller zu planen.',
                        tone: _EditorNoticeTone.info,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Planung',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    ChoiceChip(
                      label: const Text('Mitarbeiter'),
                      selected: !_saveAsUnassigned,
                      onSelected: (selected) {
                        if (!selected) {
                          return;
                        }
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
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Freie Schicht'),
                      selected: _saveAsUnassigned,
                      onSelected: (selected) {
                        if (!selected) {
                          return;
                        }
                        _setDirty(() {
                          _saveAsUnassigned = true;
                          _selectedUserIds = <String>{};
                          _additionalAssignments = const [];
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_saveAsUnassigned)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Diese Schicht wird ohne feste Zuordnung gespeichert und erscheint im Bereich "Freie Schichten".',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else if (isEdit)
              DropdownButtonFormField<String>(
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
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Mitarbeiter',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          _EditorCountBadge(
                            label: '${_selectedUserIds.length} ausgewaehlt',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (widget.members.isEmpty)
                        const _EditorNoticeCard(
                          icon: Icons.people_outline_rounded,
                          title: 'Keine aktiven Mitarbeiter vorhanden',
                          message:
                              'Im Team sind aktuell keine aktiven Mitarbeiter hinterlegt.',
                          tone: _EditorNoticeTone.warning,
                        )
                      else ...[
                        const _EditorNoticeCard(
                          icon: Icons.auto_awesome_outlined,
                          title: 'Automatische Vorschlaege aktiv',
                          message:
                              'Freie Mitarbeiter werden vorgeschlagen. Bereits belegte oder abwesende Mitarbeiter bleiben gesperrt, bis der Konflikt behoben ist.',
                          tone: _EditorNoticeTone.info,
                        ),
                        if (_loadingAvailability) ...[
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: const LinearProgressIndicator(minHeight: 6),
                          ),
                        ],
                        if (availableMembers.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Verfuegbar im gewaehlten Zeitraum',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              _EditorCountBadge(
                                label: '${availableMembers.length} frei',
                                tone: _EditorBadgeTone.success,
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () => _setDirty(
                                  () => _selectedUserIds = availableMembers
                                      .map((entry) => entry.member.uid)
                                      .toSet(),
                                ),
                                icon: const Icon(Icons.playlist_add_check),
                                label: const Text('Alle freien auswaehlen'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final availability in availableMembers)
                                FilterChip(
                                  label: Text(availability.member.displayName),
                                  selected: _selectedUserIds
                                      .contains(availability.member.uid),
                                  onSelected: (selected) {
                                    _setDirty(() {
                                      if (selected) {
                                        _selectedUserIds
                                            .add(availability.member.uid);
                                      } else {
                                        _selectedUserIds
                                            .remove(availability.member.uid);
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                        if (availableMembers.isEmpty && !_loadingAvailability)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: _EditorNoticeCard(
                              icon: Icons.person_search_outlined,
                              title: 'Aktuell kein freier Mitarbeiter',
                              message:
                                  'Passe Zeitfenster, Standort oder Arbeitsbereich an oder speichere die Schicht als freie Schicht.',
                              tone: _EditorNoticeTone.warning,
                            ),
                          ),
                        if (unavailableMembers.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Nicht verfuegbar',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              _EditorCountBadge(
                                label: '${unavailableMembers.length} gesperrt',
                                tone: _EditorBadgeTone.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Diese Mitarbeiter koennen aktuell nicht eingeplant werden. Die Gruende werden pro Person aufgegliedert.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          const SizedBox(height: 12),
                          Column(
                            children: [
                              for (final availability in unavailableMembers)
                                _AssigneeAvailabilityTile(
                                  availability: availability,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            _DateTile(
              label: 'Datum',
              value: DateFormat('dd.MM.yyyy', 'de_DE').format(_date),
              icon: Icons.calendar_today,
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Beginn'),
                    trailing: Text(_startTime.format(context)),
                    onTap: _pickStart,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Ende'),
                    trailing: Text(_endTime.format(context)),
                    onTap: _pickEnd,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _breakCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Pause in Minuten',
                prefixIcon: Icon(Icons.coffee_outlined),
              ),
              onChanged: (_) => _setDirty(
                () {},
                refreshAvailability: true,
              ),
            ),
            if (!_saveAsUnassigned && widget.members.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Weitere Besetzungen',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
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
                      const SizedBox(height: 10),
                      Text(
                        'Titel, Standort, Arbeitsbereich, Qualifikationen, Notiz, Status und Farbe werden vom Hauptblock uebernommen. Fuer jede Zusatzbesetzung kannst du einen eigenen Mitarbeiter und eigene Zeiten definieren. Konflikte werden beim Speichern gemeinsam geprueft.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 14),
                      if (_additionalAssignments.isEmpty)
                        const _EditorNoticeCard(
                          icon: Icons.schedule_send_outlined,
                          title: 'Keine Zusatzbesetzung angelegt',
                          message:
                              'Nutze weitere Besetzungen, wenn dieselbe Schicht von mehreren Personen in unterschiedlichen Zeitfenstern uebernommen wird, zum Beispiel 08:00 - 10:00 und 10:00 - 13:00.',
                          tone: _EditorNoticeTone.info,
                        )
                      else
                        Column(
                          children: [
                            for (var index = 0;
                                index < _additionalAssignments.length;
                                index++) ...[
                              _AdditionalShiftAssignmentCard(
                                key: ValueKey(
                                  'additional-assignment-${_additionalAssignments[index].id}',
                                ),
                                index: index,
                                draft: _additionalAssignments[index],
                                members: widget.members,
                                onMemberChanged: (memberId) =>
                                    _updateAdditionalAssignment(
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
                                onBreakChanged: (value) =>
                                    _updateAdditionalAssignment(
                                  _additionalAssignments[index].id,
                                  (draft) => draft.copyWith(
                                    breakMinutes:
                                        _parseBreakMinutesValue(value),
                                  ),
                                ),
                              ),
                              if (index < _additionalAssignments.length - 1)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
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
                          .where(
                              (member) => team.memberIds.contains(member.uid))
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
              const SizedBox(height: 8),
              Text(
                'Teammitglieder werden automatisch uebernommen. Belegte Mitarbeiter werden darunter separat mit Konfliktgrund angezeigt.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _teamCtrl,
              decoration: const InputDecoration(
                labelText: 'Team / Bereich',
                prefixIcon: Icon(Icons.group_work_outlined),
              ),
            ),
            const SizedBox(height: 12),
            if (sites.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Es sind noch keine Standorte angelegt. Bitte hinterlege zuerst Standorte in der Teamverwaltung.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
                onChanged: (value) {
                  _setDirty(
                    () {
                      _selectedSiteId = value;
                      final selected =
                          sites.where((site) => site.id == value).firstOrNull;
                      _locationCtrl.text = selected?.name ?? '';
                    },
                    refreshAvailability: true,
                  );
                },
              ),
            if (qualifications.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Erforderliche Qualifikationen',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                              _requiredQualificationIds
                                  .remove(qualification.id);
                            }
                          },
                          refreshAvailability: true,
                        );
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notiz',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ShiftStatus>(
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
            const SizedBox(height: 12),
            DropdownButtonFormField<RecurrencePattern>(
              initialValue: _recurrencePattern,
              decoration: const InputDecoration(
                labelText: 'Wiederholung',
                prefixIcon: Icon(Icons.repeat),
              ),
              items: [
                for (final pattern in RecurrencePattern.values)
                  DropdownMenuItem(
                    value: pattern,
                    child: Text(pattern.label),
                  ),
              ],
              onChanged: isEdit
                  ? null
                  : (value) {
                      if (value != null) {
                        _setDirty(() => _recurrencePattern = value);
                      }
                    },
            ),
            if (!isEdit && _recurrencePattern != RecurrencePattern.none) ...[
              const SizedBox(height: 12),
              _DateTile(
                label: 'Wiederholen bis',
                value: _recurrenceEndDate == null
                    ? 'Enddatum waehlen'
                    : DateFormat('dd.MM.yyyy', 'de_DE').format(_recurrenceEndDate!),
                icon: Icons.event_repeat,
                onTap: _pickRecurrenceEndDate,
              ),
            ],
            const SizedBox(height: 12),
            Text('Farbe', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
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
                  GestureDetector(
                    onTap: () => _setDirty(
                      () => _shiftColor = _shiftColor == hex ? null : hex,
                    ),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(int.parse(hex.replaceFirst('#', '0xFF'))),
                        shape: BoxShape.circle,
                        border: _shiftColor == hex
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 3)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (isEdit && _loadingAvailability) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (isEdit &&
                selectedAvailability != null &&
                !selectedAvailability.isAvailable) ...[
              const SizedBox(height: 12),
              _AssigneeAvailabilityTile(
                availability: selectedAvailability,
                title: 'Ausgewaehlter Mitarbeiter ist nicht verfuegbar',
              ),
            ],
            const SizedBox(height: 20),
            if (_conflictIssues.isNotEmpty) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _conflictIssues.length == 1
                            ? '1 Konflikt gefunden'
                            : '${_conflictIssues.length} Konflikte gefunden',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Die betroffenen Schichten werden unten aufgelistet. Passe Zeiten, Mitarbeiter oder Abwesenheiten an und pruefe erneut.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ShiftConflictList(
                        issues: _conflictIssues,
                        textColor:
                            Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
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
        title: const Text('Schichtvorlage loeschen?'),
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
            child: const Text('Loeschen'),
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

  Future<void> _pickRecurrenceEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recurrenceEndDate ?? _date.add(const Duration(days: 28)),
      firstDate: _date,
      lastDate: DateTime(2035),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      _setDirty(() => _recurrenceEndDate = picked);
    }
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
    final startTime = _selectedStartDateTime;
    final endTime = _selectedEndDateTime;

    if (!endTime.isAfter(startTime)) {
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

    if (widget.shift == null &&
        _recurrencePattern != RecurrencePattern.none &&
        _recurrenceEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte Enddatum fuer die Wiederholung waehlen.'),
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
    final location = selectedSite.name;
    final breakMinutes = _parseBreakMinutes();
    if (_saveAsUnassigned) {
      return [
        Shift(
          id: widget.shift?.id,
          orgId: widget.currentUser.orgId,
          userId: '',
          employeeName: 'Freie Schicht',
          title: _titleCtrl.text.trim(),
          startTime: startTime,
          endTime: endTime,
          breakMinutes: breakMinutes,
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
      ];
    }

    final shifts = <Shift>[
      ...selectedMembers.map(
        (member) => Shift(
          id: widget.shift?.id,
          orgId: widget.currentUser.orgId,
          userId: member.uid,
          employeeName: member.displayName,
          title: _titleCtrl.text.trim(),
          startTime: startTime,
          endTime: endTime,
          breakMinutes: breakMinutes,
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
