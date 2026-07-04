import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../core/screen_security.dart';
import '../models/app_user.dart';
import '../models/password_entry.dart';
import '../models/site_definition.dart';
import '../providers/auth_provider.dart';
import '../providers/password_provider.dart';
import '../providers/team_provider.dart';
import '../widgets/breadcrumb_app_bar.dart';

/// **Passwortmanager-Screen `/passwoerter` (§5.3).** Liste + Suche + Kategorie-
/// Filter; „Anzeigen" mit Sicherheitsbestätigung + Auto-Hide; Kopieren
/// protokolliert. Nie Klartext in der Liste. Verwaltung zentraler Einträge nur
/// für Admins; jeder aktive Nutzer verwaltet eigene Einträge.
class PasswordsScreen extends StatefulWidget {
  const PasswordsScreen({
    super.key,
    this.parentLabel = 'Profil',
    @visibleForTesting this.biometricAuthOverride,
  });

  final String parentLabel;

  /// **Nur für Tests.** Ersetzt den `local_auth`-Aufruf (dessen Pigeon-Kanäle
  /// im Widget-Test blockieren). `null` = echte Biometrie/Geräte-PIN.
  final Future<bool> Function()? biometricAuthOverride;

  @override
  State<PasswordsScreen> createState() => _PasswordsScreenState();
}

class _PasswordsScreenState extends State<PasswordsScreen> {
  String _search = '';
  PasswordCategory? _categoryFilter;

  List<PasswordEntry> _filtered(List<PasswordEntry> all) {
    final q = _search.trim().toLowerCase();
    return all.where((e) {
      if (_categoryFilter != null && e.category != _categoryFilter) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          (e.siteName ?? '').toLowerCase().contains(q) ||
          e.category.label.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PasswordProvider>();
    final profile = context.watch<AuthProvider>().profile;
    final breadcrumbs = [
      BreadcrumbItem(
        label: widget.parentLabel,
        onTap: () => Navigator.of(context).maybePop(),
      ),
      const BreadcrumbItem(label: 'Passwörter'),
    ];

    if (!provider.isEnabled) {
      return Scaffold(
        appBar: BreadcrumbAppBar(breadcrumbs: breadcrumbs),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Der Passwortmanager ist in dieser Umgebung nicht verfügbar.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final entries = _filtered(provider.entries);

    return Scaffold(
      appBar: BreadcrumbAppBar(
        breadcrumbs: breadcrumbs,
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: provider.loading ? null : provider.refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, profile),
        icon: const Icon(Icons.add),
        label: const Text('Neu'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Suchen (Dienst, Filiale, Kategorie)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: const Text('Alle'),
                      selected: _categoryFilter == null,
                      onSelected: (_) =>
                          setState(() => _categoryFilter = null),
                    ),
                  ),
                  for (final c in PasswordCategory.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(c.label),
                        selected: _categoryFilter == c,
                        onSelected: (_) =>
                            setState(() => _categoryFilter = c),
                      ),
                    ),
                ],
              ),
            ),
            if (provider.errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(provider.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: provider.loading && entries.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                      ? const Center(
                          child: Text('Noch keine Passwörter hinterlegt.'))
                      : RefreshIndicator(
                          onRefresh: provider.refresh,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                            itemCount: entries.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) => _PasswordCard(
                              entry: entries[i],
                              canManage: _canManage(entries[i], profile),
                              onReveal: () => _reveal(context, entries[i]),
                              onEdit: () =>
                                  _openEditor(context, profile, entry: entries[i]),
                              onDelete: () => _delete(context, entries[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canManage(PasswordEntry entry, AppUserProfile? profile) {
    if (profile == null) return false;
    if (entry.scope == PasswordScope.personal) {
      return entry.ownerUid == profile.uid || profile.isAdmin;
    }
    return profile.canManagePasswords;
  }

  Future<void> _delete(BuildContext context, PasswordEntry entry) async {
    final provider = context.read<PasswordProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('„${entry.title}" löschen?'),
        content: const Text('Der Eintrag wird endgültig entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await provider.delete(entry.id!);
      messenger.showSnackBar(const SnackBar(content: Text('Eintrag gelöscht.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(error))));
    }
  }

  /// Sicherheitsbestätigung vor dem Anzeigen: wo verfügbar per Biometrie/
  /// Geräte-PIN (`local_auth`), sonst per Bestätigungsdialog (Web/Desktop/
  /// Testumgebung). Der Server erzwingt zusätzlich einen frischen Reauth-Nonce
  /// + Rate-Limit — dies ist die zusätzliche Gerätehürde, kein Ersatz.
  Future<bool> _confirmReveal(BuildContext context, PasswordEntry entry) async {
    final override = widget.biometricAuthOverride;
    if (override != null) {
      try {
        if (await override()) return true;
      } catch (_) {/* → Dialog */}
    } else if (!kIsWeb) {
      try {
        final auth = LocalAuthentication();
        if (await auth.isDeviceSupported()) {
          return await auth.authenticate(
            localizedReason: '„${entry.title}" anzeigen bestätigen',
            biometricOnly: false,
            persistAcrossBackgrounding: true,
          );
        }
      } catch (_) {
        // Keine Geräteauth verfügbar / kein Enrollment / Testumgebung →
        // Fallback auf den Bestätigungsdialog.
      }
    }
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Passwort anzeigen'),
        content: Text('„${entry.title}" für kurze Zeit im Klartext anzeigen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Anzeigen')),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _reveal(BuildContext context, PasswordEntry entry) async {
    final provider = context.read<PasswordProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirmReveal(context, entry)) return;
    if (!context.mounted) return;
    try {
      final token = await provider.beginReauth();
      final secret = await provider.reveal(entry.id!, reauthToken: token);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _RevealSheet(
          entry: entry,
          secret: secret,
          onCopy: (field) => provider.logCopy(entry.id!, field: field),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(error))));
    }
  }

  Future<void> _openEditor(BuildContext context, AppUserProfile? profile,
      {PasswordEntry? entry}) async {
    if (profile == null) return;
    final provider = context.read<PasswordProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final sites = context.read<TeamProvider>().sites;
    final members = context.read<TeamProvider>().members;
    final result = await showModalBottomSheet<_EditorResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PasswordEditorSheet(
        entry: entry,
        profile: profile,
        sites: sites,
        members: members,
      ),
    );
    if (result == null) return;
    try {
      await provider.save(
        entry: result.entry,
        plainUsername: result.plainUsername,
        plainPassword: result.plainPassword,
        plainNotes: result.plainNotes,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Passwort gespeichert.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(error))));
    }
  }

  String _msg(Object error) =>
      error is StateError ? error.message : 'Aktion fehlgeschlagen.';
}

class _PasswordCard extends StatelessWidget {
  const _PasswordCard({
    required this.entry,
    required this.canManage,
    required this.onReveal,
    required this.onEdit,
    required this.onDelete,
  });

  final PasswordEntry entry;
  final bool canManage;
  final VoidCallback onReveal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  IconData get _icon => switch (entry.category) {
        PasswordCategory.kvg => Icons.directions_bus_outlined,
        PasswordCategory.lotto => Icons.confirmation_number_outlined,
        PasswordCategory.post => Icons.local_post_office_outlined,
        PasswordCategory.supplierPortal => Icons.local_shipping_outlined,
        PasswordCategory.internalSystem => Icons.computer_outlined,
        PasswordCategory.authorityPortal => Icons.account_balance_outlined,
        PasswordCategory.other => Icons.vpn_key_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      entry.category.label,
      if (entry.siteName != null && entry.siteName!.isNotEmpty) entry.siteName!,
      if (entry.scope == PasswordScope.shared) 'freigegeben',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(_icon, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(entry.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitleParts.join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Anzeigen',
              icon: const Icon(Icons.visibility_outlined),
              onPressed: entry.hasSecret ? onReveal : null,
            ),
            if (canManage)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  PopupMenuItem(value: 'delete', child: Text('Löschen')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Zeigt das entschlüsselte Secret zeitlich begrenzt (Auto-Hide-Countdown) mit
/// Kopier-Buttons. Klartext lebt nur im lokalen Sheet-State.
class _RevealSheet extends StatefulWidget {
  const _RevealSheet({
    required this.entry,
    required this.secret,
    required this.onCopy,
  });

  final PasswordEntry entry;
  final PasswordSecret secret;
  final void Function(String field) onCopy;

  @override
  State<_RevealSheet> createState() => _RevealSheetState();
}

class _RevealSheetState extends State<_RevealSheet> {
  static const int _ttlSeconds = 30;
  static const int _clipboardClearSeconds = 20;
  int _remaining = _ttlSeconds;
  Timer? _timer;
  Timer? _clipboardTimer;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    // Screenshot-/Recents-Schutz, solange das Secret sichtbar ist (Android).
    ScreenSecurity.enable();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _remaining--;
        if (_remaining <= 0) {
          _hidden = true;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clipboardTimer?.cancel();
    ScreenSecurity.disable();
    super.dispose();
  }

  Future<void> _copy(String value, String field, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    widget.onCopy(field);
    _scheduleClipboardClear(value);
    if (!mounted) return;
    // Auto-Clear ist auf Web nicht zuverlässig → dort nichts versprechen.
    const hint = kIsWeb ? '' : ' – wird in $_clipboardClearSeconds s geleert';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label kopiert$hint.')));
  }

  /// Leert die Zwischenablage nach kurzer Zeit — aber nur, wenn dort noch das
  /// kopierte Secret liegt (best-effort; auf Web deaktiviert).
  void _scheduleClipboardClear(String value) {
    _clipboardTimer?.cancel();
    if (kIsWeb) return;
    _clipboardTimer =
        Timer(const Duration(seconds: _clipboardClearSeconds), () async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.secret;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.entry.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            _hidden
                ? 'Aus Sicherheitsgründen ausgeblendet.'
                : 'Wird in $_remaining s automatisch ausgeblendet.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (!_hidden) ...[
            if (s.username.isNotEmpty)
              _SecretField(
                label: 'Benutzername',
                value: s.username,
                onCopy: () => _copy(s.username, 'username', 'Benutzername'),
              ),
            _SecretField(
              label: 'Passwort',
              value: s.password,
              mono: true,
              onCopy: () => _copy(s.password, 'password', 'Passwort'),
            ),
            if (s.notes.isNotEmpty)
              _SecretField(
                label: 'Notiz',
                value: s.notes,
                onCopy: () => _copy(s.notes, 'notes', 'Notiz'),
              ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }
}

class _SecretField extends StatelessWidget {
  const _SecretField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.mono = false,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                SelectableText(
                  value,
                  style: mono
                      ? theme.textTheme.titleMedium
                          ?.copyWith(fontFamily: 'monospace')
                      : theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kopieren',
            icon: const Icon(Icons.copy_outlined),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

class _EditorResult {
  const _EditorResult({
    required this.entry,
    this.plainUsername,
    this.plainPassword,
    this.plainNotes,
  });

  final PasswordEntry entry;
  final String? plainUsername;
  final String? plainPassword;
  final String? plainNotes;
}

class _PasswordEditorSheet extends StatefulWidget {
  const _PasswordEditorSheet({
    required this.entry,
    required this.profile,
    required this.sites,
    required this.members,
  });

  final PasswordEntry? entry;
  final AppUserProfile profile;
  final List<SiteDefinition> sites;
  final List<AppUserProfile> members;

  @override
  State<_PasswordEditorSheet> createState() => _PasswordEditorSheetState();
}

class _PasswordEditorSheetState extends State<_PasswordEditorSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _notesCtrl;
  late PasswordCategory _category;
  late PasswordScope _scope;
  String? _siteId;
  bool _showPass = false;
  final Set<String> _audienceUids = {};
  final Set<String> _audienceRoles = {};
  final Set<String> _audienceSiteIds = {};

  bool get _canManageShared => widget.profile.canManagePasswords;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _urlCtrl = TextEditingController(text: e?.url ?? '');
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _category = e?.category ?? PasswordCategory.other;
    _scope = e?.scope ?? PasswordScope.personal;
    _siteId = e?.siteId;
    _audienceUids.addAll(e?.audienceUids ?? const []);
    _audienceRoles.addAll(e?.audienceRoles ?? const []);
    _audienceSiteIds.addAll(e?.audienceSiteIds ?? const []);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final siteName = _siteId == null
        ? null
        : widget.sites
            .where((s) => s.id == _siteId)
            .map((s) => s.name)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);
    final base = widget.entry;
    final entry = PasswordEntry(
      id: base?.id,
      orgId: widget.profile.orgId,
      title: title,
      category: _category,
      siteId: _siteId,
      siteName: siteName,
      ownerUid: base?.ownerUid ?? widget.profile.uid,
      scope: _scope,
      audienceUids: _scope == PasswordScope.shared
          ? _audienceUids.toList()
          : const [],
      audienceRoles: _scope == PasswordScope.shared
          ? _audienceRoles.toList()
          : const [],
      audienceSiteIds: _scope == PasswordScope.shared
          ? _audienceSiteIds.toList()
          : const [],
      url: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
      hasSecret: base?.hasSecret ?? false,
    );
    final pass = _passCtrl.text;
    Navigator.of(context).pop(_EditorResult(
      entry: entry,
      plainUsername: pass.isEmpty ? null : _userCtrl.text,
      plainPassword: pass.isEmpty ? null : pass,
      plainNotes: pass.isEmpty ? null : _notesCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.entry == null ? 'Neues Passwort' : 'Passwort bearbeiten',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Dienst / Titel',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PasswordCategory>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Kategorie',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in PasswordCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (v) =>
                  setState(() => _category = v ?? PasswordCategory.other),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.sites.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _siteId,
                decoration: const InputDecoration(
                  labelText: 'Filiale (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final s in widget.sites)
                    if (s.id != null)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _siteId = v),
              ),
            ],
            if (_canManageShared) ...[
              const SizedBox(height: 12),
              SegmentedButton<PasswordScope>(
                segments: const [
                  ButtonSegment(
                      value: PasswordScope.personal, label: Text('Eigenes')),
                  ButtonSegment(
                      value: PasswordScope.shared, label: Text('Zentral')),
                ],
                selected: {_scope},
                onSelectionChanged: (s) =>
                    setState(() => _scope = s.first),
              ),
            ],
            if (_scope == PasswordScope.shared && _canManageShared)
              _buildAudience(theme),
            const Divider(height: 32),
            Text('Zugangsdaten',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Benutzername',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: !_showPass,
              decoration: InputDecoration(
                labelText: widget.entry == null
                    ? 'Passwort'
                    : 'Passwort (leer = unverändert)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notiz (verschlüsselt)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudience(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Zielgruppe', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final role in const ['admin', 'teamlead', 'employee'])
              FilterChip(
                label: Text(role),
                selected: _audienceRoles.contains(role),
                onSelected: (v) => setState(() {
                  if (v) {
                    _audienceRoles.add(role);
                  } else {
                    _audienceRoles.remove(role);
                  }
                }),
              ),
          ],
        ),
        if (widget.sites.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Filialen', style: theme.textTheme.labelMedium),
          Wrap(
            spacing: 8,
            children: [
              for (final s in widget.sites)
                if (s.id != null)
                  FilterChip(
                    label: Text(s.name),
                    selected: _audienceSiteIds.contains(s.id),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _audienceSiteIds.add(s.id!);
                      } else {
                        _audienceSiteIds.remove(s.id!);
                      }
                    }),
                  ),
            ],
          ),
        ],
        if (widget.members.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Mitarbeiter', style: theme.textTheme.labelMedium),
          Wrap(
            spacing: 8,
            children: [
              for (final m in widget.members)
                FilterChip(
                  label: Text(m.displayName),
                  selected: _audienceUids.contains(m.uid),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _audienceUids.add(m.uid);
                    } else {
                      _audienceUids.remove(m.uid);
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
