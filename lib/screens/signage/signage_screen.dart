import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../models/ad_media.dart';
import '../../models/signage_display.dart';
import '../../models/site_definition.dart';
import '../../providers/auth_provider.dart';
import '../../providers/signage_provider.dart';
import '../../providers/team_provider.dart';
import '../../ui/ui.dart';

/// Baut die öffentliche Player-URL eines Displays (`<base>/anzeige/<token>`).
/// Basis aus [AppConfig.signagePlayerBaseUrl]; im Web sonst der eigene Origin.
String signagePlayerUrl(String token) {
  final configured = AppConfig.signagePlayerBaseUrl.trim();
  final base = configured.isNotEmpty
      ? configured
      : (kIsWeb ? Uri.base.origin : '');
  final normalized =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return normalized.isEmpty ? '/anzeige/$token' : '$normalized/anzeige/$token';
}

/// **Admin-only** Verwaltung der digitalen Werbe-Displays (Store-Fernseher):
/// Werbebild-Bibliothek hochladen, Displays anlegen und je Display eine
/// Bild-Playlist + Anzeigedauer festlegen. Der Fernseher öffnet die öffentliche
/// Player-URL (`/anzeige/<token>`) und zeigt die Werbung in Vollbild-Schleife.
class SignageScreen extends StatefulWidget {
  const SignageScreen({super.key, required this.parentLabel});

  final String parentLabel;

  @override
  State<SignageScreen> createState() => _SignageScreenState();
}

class _SignageScreenState extends State<SignageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: der Screen rendert Admin-Inhalte nie, selbst wenn eine
    // Route/Karte durchrutscht (die eigentliche Sperre ist RoutePermissions).
    final isAdmin = context.watch<AuthProvider>().profile?.isAdmin ?? false;
    if (!isAdmin) {
      return Scaffold(
        appBar: BreadcrumbAppBar(
          breadcrumbs: [
            BreadcrumbItem(
              label: widget.parentLabel,
              onTap: () => Navigator.of(context).pop(),
            ),
            const BreadcrumbItem(label: 'Displays & Werbung'),
          ],
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Dieser Bereich ist nur für Administratoren.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Crumb(
                label: widget.parentLabel,
                onTap: () => Navigator.of(context).pop(),
              ),
              const Icon(Icons.chevron_right, size: 18),
              const _Crumb(label: 'Displays & Werbung', isLast: true),
            ],
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Displays'),
            Tab(text: 'Werbebilder'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _DisplaysTab(),
          _MediaTab(),
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, this.onTap, this.isLast = false});

  final String label;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final child = Text(
      label,
      style: TextStyle(
        fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
        color: isLast ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
      ),
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      );
    }
    return TextButton(onPressed: onTap, child: child);
  }
}

// ---------------------------------------------------------------------------
// Displays-Tab
// ---------------------------------------------------------------------------

class _DisplaysTab extends StatelessWidget {
  const _DisplaysTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SignageProvider>();
    final displays = provider.displays;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Neues Display'),
      ),
      body: provider.loading && displays.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : displays.isEmpty
              ? const AppEmptyState(
                  icon: Icons.tv_outlined,
                  message:
                      'Noch kein Display angelegt.\nLege ein Display an und weise ihm Werbebilder zu — den Link öffnest du dann auf dem Fernseher.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  children: [
                    for (final display in displays)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DisplayCard(display: display),
                      ),
                  ],
                ),
    );
  }
}

class _DisplayCard extends StatelessWidget {
  const _DisplayCard({required this.display});

  final SignageDisplay display;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SignageProvider>();
    final appColors = Theme.of(context).appColors;
    final siteName = _siteName(context, display.siteId);
    final url = signagePlayerUrl(display.pairingToken);

    return AppCard(
      onTap: () => _openEditor(context, display),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tv_outlined,
                color: display.isActive
                    ? appColors.success
                    : Theme.of(context).disabledColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display.name.isEmpty ? 'Display' : display.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      [
                        if (siteName != null) siteName,
                        '${display.slideCount} ${display.slideCount == 1 ? 'Bild' : 'Bilder'}',
                        '${display.slideSeconds}s je Bild',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              AppStatusBadge(
                label: display.isActive ? 'Aktiv' : 'Pausiert',
                tone: display.isActive
                    ? AppStatusTone.success
                    : AppStatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Fernseh-Link kopieren',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () => _copyUrl(context, url),
              ),
              Switch(
                value: display.isActive,
                onChanged: (value) =>
                    provider.setDisplayActive(display, isActive: value),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Werbebilder-Tab
// ---------------------------------------------------------------------------

class _MediaTab extends StatelessWidget {
  const _MediaTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SignageProvider>();
    final media = provider.media;
    final canUpload = provider.mediaUploadAvailable;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canUpload ? () => _pickAndUpload(context) : null,
        backgroundColor: canUpload ? null : Theme.of(context).disabledColor,
        icon: const Icon(Icons.upload_outlined),
        label: const Text('Bild hochladen'),
      ),
      body: Column(
        children: [
          if (!canUpload)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).appColors.warningContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Der Bild-Upload benötigt den Cloud-Modus (Firebase). Im '
                'Offline-/Demo-Modus lassen sich Displays anlegen, aber keine '
                'Werbebilder hochladen.',
                style: TextStyle(
                  color: Theme.of(context).appColors.onWarningContainer,
                ),
              ),
            ),
          Expanded(
            child: provider.loading && media.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : media.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.image_outlined,
                        message:
                            'Noch keine Werbebilder.\nLade Bilder hoch und weise sie einem Display zu.',
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          childAspectRatio: 4 / 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: media.length,
                        itemBuilder: (context, index) =>
                            _MediaTile(media: media[index]),
                      ),
          ),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media});

  final AdMedia media;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: media.downloadUrl.isEmpty
                ? const Icon(Icons.broken_image_outlined)
                : Image.network(
                    media.downloadUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              color: Colors.black.withValues(alpha: 0.45),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  _MediaMenu(media: media),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaMenu extends StatelessWidget {
  const _MediaMenu({required this.media});

  final AdMedia media;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SignageProvider>();
    final messenger = ScaffoldMessenger.of(context);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (value) async {
        try {
          if (value == 'rename') {
            final title = await _promptText(
              context,
              title: 'Bild umbenennen',
              initial: media.title,
            );
            if (title != null && title.trim().isNotEmpty) {
              await provider.renameMedia(media, title.trim());
            }
          } else if (value == 'delete') {
            final ok = await _confirm(
              context,
              title: 'Werbebild löschen?',
              message:
                  'Das Bild wird aus der Bibliothek und aus allen Displays entfernt.',
            );
            if (ok && media.id != null) {
              await provider.deleteMedia(media.id!);
            }
          }
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text('Aktion fehlgeschlagen: $error')),
          );
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
        PopupMenuItem(value: 'delete', child: Text('Löschen')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Display-Editor (Vollbild, imperativ gepusht)
// ---------------------------------------------------------------------------

class _DisplayEditorScreen extends StatefulWidget {
  const _DisplayEditorScreen({this.display});

  /// Null ⇒ Neuanlage.
  final SignageDisplay? display;

  @override
  State<_DisplayEditorScreen> createState() => _DisplayEditorScreenState();
}

class _DisplayEditorScreenState extends State<_DisplayEditorScreen> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.display?.name ?? '');
  late String? _siteId = widget.display?.siteId;
  late int _slideSeconds = widget.display?.slideSeconds ?? 8;
  late SignageFit _fit = widget.display?.fit ?? SignageFit.cover;
  late SignageTransition _transition =
      widget.display?.transition ?? SignageTransition.fade;
  late final List<String> _mediaIds =
      List<String>.from(widget.display?.mediaIds ?? const <String>[]);
  late bool _isActive = widget.display?.isActive ?? true;
  bool _saving = false;

  bool get _isNew => widget.display == null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Namen für das Display eingeben.')),
      );
      return;
    }
    final provider = context.read<SignageProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final base = widget.display ??
        const SignageDisplay(orgId: '', name: '', pairingToken: '');
    final updated = base.copyWith(
      name: name,
      siteId: _siteId,
      clearSiteId: _siteId == null,
      slideSeconds: _slideSeconds,
      fit: _fit,
      transition: _transition,
      mediaIds: _mediaIds,
      isActive: _isActive,
    );
    try {
      await provider.saveDisplay(updated);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Display gespeichert.')),
      );
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    }
  }

  Future<void> _delete() async {
    final display = widget.display;
    if (display?.id == null) return;
    final provider = context.read<SignageProvider>();
    final navigator = Navigator.of(context);
    final ok = await _confirm(
      context,
      title: 'Display löschen?',
      message:
          'Das Display und sein öffentlicher Link werden entfernt. Die Werbebilder bleiben in der Bibliothek.',
    );
    if (!ok) return;
    await provider.deleteDisplay(display!.id!);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SignageProvider>();
    final sites = context.watch<TeamProvider>().sites;
    final media = provider.media;
    final selected = _mediaIds
        .map((id) => provider.mediaById(id))
        .whereType<AdMedia>()
        .toList(growable: false);
    final available =
        media.where((m) => !_mediaIds.contains(m.id)).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Neues Display' : 'Display bearbeiten'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name des Displays',
              hintText: 'z. B. Schaufenster Strichmännchen',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _siteId,
            decoration: const InputDecoration(labelText: 'Standort (optional)'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Kein Standort'),
              ),
              for (final SiteDefinition site in sites)
                if (site.id != null)
                  DropdownMenuItem<String?>(
                    value: site.id,
                    child: Text(site.name),
                  ),
            ],
            onChanged: (value) => setState(() => _siteId = value),
          ),
          const SizedBox(height: 20),
          Text('Anzeigedauer je Bild: $_slideSeconds Sekunden',
              style: Theme.of(context).textTheme.titleSmall),
          Slider(
            value: _slideSeconds.toDouble(),
            min: 3,
            max: 60,
            divisions: 57,
            label: '$_slideSeconds s',
            onChanged: (value) =>
                setState(() => _slideSeconds = value.round()),
          ),
          const SizedBox(height: 8),
          Text('Bild-Einpassung',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<SignageFit>(
            segments: const [
              ButtonSegment(
                value: SignageFit.cover,
                label: Text('Füllen'),
                icon: Icon(Icons.crop_free),
              ),
              ButtonSegment(
                value: SignageFit.contain,
                label: Text('Ganz zeigen'),
                icon: Icon(Icons.fit_screen_outlined),
              ),
            ],
            selected: {_fit},
            onSelectionChanged: (value) =>
                setState(() => _fit = value.first),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SignageTransition>(
            initialValue: _transition,
            decoration: const InputDecoration(
              labelText: 'Animation (Übergang zwischen Bildern)',
            ),
            items: [
              for (final t in SignageTransition.values)
                DropdownMenuItem<SignageTransition>(
                  value: t,
                  child: Text(t.label),
                ),
            ],
            onChanged: (value) => setState(
                () => _transition = value ?? SignageTransition.fade),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Display aktiv'),
            subtitle: const Text(
                'Pausiert ⇒ der Fernseher zeigt keine Werbung.'),
            value: _isActive,
            onChanged: (value) => setState(() => _isActive = value),
          ),
          const Divider(height: 32),
          Text('Playlist (${selected.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Reihenfolge per Ziehen ändern. Die Bilder laufen in Schleife.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          if (selected.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Noch keine Bilder in der Playlist.'),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final id = _mediaIds.removeAt(oldIndex);
                  _mediaIds.insert(newIndex, id);
                });
              },
              children: [
                for (var i = 0; i < selected.length; i++)
                  ListTile(
                    key: ValueKey(selected[i].id),
                    contentPadding: EdgeInsets.zero,
                    leading: _Thumb(url: selected[i].downloadUrl),
                    title: Text(selected[i].title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(
                          () => _mediaIds.remove(selected[i].id)),
                    ),
                  ),
              ],
            ),
          const Divider(height: 32),
          Text('Aus der Bibliothek hinzufügen',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (available.isEmpty)
            Text(
              media.isEmpty
                  ? 'Noch keine Werbebilder hochgeladen (Reiter „Werbebilder").'
                  : 'Alle Bilder sind bereits in der Playlist.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in available)
                  InkWell(
                    onTap: () => setState(() => _mediaIds.add(m.id!)),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            _Thumb(url: m.downloadUrl, size: 84),
                            const Positioned(
                              right: 2,
                              top: 2,
                              child: CircleAvatar(
                                radius: 11,
                                child: Icon(Icons.add, size: 15),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 84,
                          child: Text(
                            m.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, this.size = 48});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: url.isEmpty
              ? const Icon(Icons.image_outlined)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image_outlined),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helfer
// ---------------------------------------------------------------------------

void _openEditor(BuildContext context, SignageDisplay? display) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _DisplayEditorScreen(display: display),
    ),
  );
}

String? _siteName(BuildContext context, String? siteId) {
  if (siteId == null) return null;
  for (final site in context.read<TeamProvider>().sites) {
    if (site.id == siteId) return site.name;
  }
  return null;
}

void _copyUrl(BuildContext context, String url) {
  Clipboard.setData(ClipboardData(text: url));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Fernseh-Link kopiert.')),
  );
}

Future<void> _pickAndUpload(BuildContext context) async {
  final provider = context.read<SignageProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final picked =
      await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.first;
  final bytes = file.bytes;
  if (bytes == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Datei konnte nicht gelesen werden.')),
    );
    return;
  }
  if (bytes.length >= 10 * 1024 * 1024) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Das Bild ist zu groß (max. 10 MB).')),
    );
    return;
  }
  final rawName = file.name;
  final dot = rawName.lastIndexOf('.');
  final title = dot > 0 ? rawName.substring(0, dot) : rawName;
  try {
    await provider.uploadMedia(
      title: title,
      bytes: bytes,
      fileExtension: file.extension ?? 'jpg',
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Werbebild hochgeladen.')),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Upload fehlgeschlagen: $error')),
    );
  }
}

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
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
  return result ?? false;
}
