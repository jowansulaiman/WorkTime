import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_config.dart';
import '../../core/expiry_warning.dart';
import '../../core/fridge_refill_shortfall.dart';
import '../../models/app_user.dart';
import '../../models/cash_count.dart';
import '../../models/customer_wish.dart';
import '../../models/site_definition.dart';
import '../../models/store_task.dart';
import '../../providers/auth_provider.dart';
import '../../models/product_batch.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/store_task_provider.dart';
import '../../providers/team_provider.dart';
import '../../services/firestore_service.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/cash_count_sheet.dart';
import 'kiosk_clock_service.dart';
import 'kiosk_controller.dart';
import 'kiosk_pin_service.dart';
import 'store_task_editor_sheet.dart';

/// **Arbeitsmodus / Laden-Tablet (Kiosk).** Vollbild-Board für das geteilte
/// Tablet im Laden: zeigt dauerhaft die operativ wichtigen Dinge (Kundenwünsche,
/// Laden-To-Dos, Kühlschrank-Nachfüllung, Hinweise) und lässt Mitarbeiter sich
/// per Name + PIN anmelden, um zu stempeln, nachzufüllen und Aufgaben abzuhaken.
///
/// Increment 0: läuft komplett offline (`APP_DISABLE_AUTH`), PIN über den lokalen
/// Dev-Pfad ([KioskPinStore]). Server-geprüfte PIN + echte Per-Mitarbeiter-
/// Stempelung folgen in Increment 2.
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final KioskController _controller = KioskController();
  final FirestoreService _firestore = FirestoreService();
  Timer? _clock;
  DateTime _now = DateTime.now();

  /// Am Gerät lokal gewählter Laden (siehe [KioskDeviceStore]).
  String? _deviceSiteId;
  bool _siteLoaded = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _enableAlwaysOn();
    _loadDeviceSite();
  }

  Future<void> _loadDeviceSite() async {
    final siteId = await KioskDeviceStore.getSiteId();
    if (mounted) {
      setState(() {
        _deviceSiteId = siteId;
        _siteLoaded = true;
      });
    }
  }

  Future<void> _chooseSite(String siteId) async {
    await KioskDeviceStore.setSiteId(siteId);
    if (mounted) setState(() => _deviceSiteId = siteId);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _controller.dispose();
    _disableAlwaysOn();
    super.dispose();
  }

  /// Always-On für das Laden-Tablet: Bildschirm wach halten (Wakelock) +
  /// Vollbild ohne System-Leisten (Immersive). Best-effort — auf nicht
  /// unterstützten Plattformen (Web/Desktop) No-op statt Absturz.
  Future<void> _enableAlwaysOn() async {
    try {
      await WakelockPlus.enable();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      // Kiosk-Komfort, nicht kritisch — Fehler bewusst schlucken.
    }
  }

  Future<void> _disableAlwaysOn() async {
    try {
      await WakelockPlus.disable();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // ignore
    }
  }

  /// Der Laden dieses Tablets (E2), in Prioritätsreihenfolge:
  /// 1. `APP_KIOSK_SITE_ID`-dart-define (vorkonfiguriertes Gerät, Override),
  /// 2. am Gerät lokal gewählter Laden ([KioskDeviceStore]),
  /// 3. bei genau EINEM Standort automatisch dieser,
  /// sonst `null` → der Nutzer muss zuerst einen Laden wählen.
  SiteDefinition? _resolveSite(List<SiteDefinition> sites) {
    if (sites.isEmpty) return null;
    SiteDefinition? byId(String id) {
      for (final s in sites) {
        if (s.id == id) return s;
      }
      return null;
    }

    final configured = AppConfig.kioskSiteId.trim();
    if (configured.isNotEmpty) {
      final match = byId(configured);
      if (match != null) return match;
    }
    final device = _deviceSiteId?.trim();
    if (device != null && device.isNotEmpty) {
      final match = byId(device);
      if (match != null) return match;
    }
    if (sites.length == 1) return sites.first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sites = context.watch<TeamProvider>().sites;

    if (!_siteLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final site = _resolveSite(sites);

    // Kein Laden zugeordnet (mehrere Standorte, noch keine Wahl) → Auswahl.
    if (site == null) {
      return Scaffold(
        body: SafeArea(
          child: _KioskSitePicker(sites: sites, onSelected: _chooseSite),
        ),
      );
    }

    return ChangeNotifierProvider<KioskController>.value(
      value: _controller,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KioskTopBar(
                now: _now,
                storeName: site.name,
                // „Laden wechseln" nur, wenn kein fester dart-define-Override und
                // es mehr als einen Standort gibt.
                onChangeSite: (AppConfig.kioskSiteId.trim().isEmpty &&
                        sites.length > 1)
                    ? () => _openSitePicker(context, sites)
                    : null,
                onLogin: () => _openLoginSheet(context, site),
              ),
              Expanded(
                child: _KioskBoard(
                  siteId: site.id,
                  siteName: site.name,
                  firestore: _firestore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSitePicker(
      BuildContext context, List<SiteDefinition> sites) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _KioskSitePicker(
        sites: sites,
        onSelected: (siteId) {
          Navigator.of(context).pop();
          _chooseSite(siteId);
        },
      ),
    );
  }

  Future<void> _openLoginSheet(BuildContext context, SiteDefinition? site) async {
    final members = context.read<TeamProvider>().members;
    final roster = members.where((m) => m.isActive).toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _KioskLoginSheet(
        roster: roster,
        pinService: KioskPinService.resolve(firestore: _firestore),
        onAuthenticated: (employee, sid) {
          _controller.login(employee, sid: sid);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kopfzeile: Laden + Uhr + Anmeldung / aktiver Mitarbeiter + Auto-Logout
// ---------------------------------------------------------------------------

class _KioskTopBar extends StatelessWidget {
  const _KioskTopBar({
    required this.now,
    required this.storeName,
    required this.onLogin,
    this.onChangeSite,
  });

  final DateTime now;
  final String storeName;
  final VoidCallback onLogin;

  /// Optional: Laden am Gerät wechseln (nur ohne dart-define-Override + >1 Laden).
  final VoidCallback? onChangeSite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<KioskController>();
    final employee = controller.employee;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(storeName, style: theme.textTheme.headlineSmall),
                    ),
                    if (onChangeSite != null)
                      IconButton(
                        tooltip: 'Laden wechseln',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_location_alt_outlined),
                        onPressed: onChangeSite,
                      ),
                  ],
                ),
                Text(
                  DateFormat('EEEE, d. MMMM', 'de_DE').format(now),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateFormat('HH:mm', 'de_DE').format(now),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFeatures: const [],
            ),
          ),
          const SizedBox(width: 24),
          if (employee == null)
            FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login),
              label: const Text('Anmelden'),
            )
          else
            _ActiveEmployeeChip(
              employee: employee,
              expiresAt: controller.expiresAt,
              now: now,
              onLogout: controller.logout,
            ),
        ],
      ),
    );
  }
}

class _ActiveEmployeeChip extends StatelessWidget {
  const _ActiveEmployeeChip({
    required this.employee,
    required this.expiresAt,
    required this.now,
    required this.onLogout,
  });

  final AppUserProfile employee;
  final DateTime? expiresAt;
  final DateTime now;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = expiresAt?.difference(now);
    final secs = remaining == null ? 0 : remaining.inSeconds.clamp(0, 9999);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Angemeldet', style: theme.textTheme.labelSmall),
            Text(
              employee.displayName,
              style: theme.textTheme.titleMedium,
            ),
            if (secs > 0)
              Text(
                'Abmeldung in ${secs}s',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Fertig'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Laden wählen (Geräte-Zuordnung) — Vollbild-Erstwahl + Wechsel-Sheet
// ---------------------------------------------------------------------------

class _KioskSitePicker extends StatelessWidget {
  const _KioskSitePicker({required this.sites, required this.onSelected});

  final List<SiteDefinition> sites;
  final void Function(String siteId) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Laden wählen', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Dieses Tablet einem Laden zuordnen. Es zeigt danach Kundenwünsche, '
            'Kühlschrank-Alarme und To-Dos nur für diesen Laden.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (sites.isEmpty)
            const _KioskEmpty('Keine Standorte hinterlegt.')
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final s = sites[i];
                  final address = s.displayAddress;
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.store_outlined),
                      title: Text(s.name),
                      subtitle: address.isEmpty ? null : Text(address),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: s.id == null ? null : () => onSelected(s.id!),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Board: modulare Kachel-Registry (erweiterbar, E4)
// ---------------------------------------------------------------------------

class _KioskBoard extends StatelessWidget {
  const _KioskBoard({
    required this.siteId,
    required this.siteName,
    required this.firestore,
  });

  final String? siteId;
  final String siteName;
  final FirestoreService firestore;

  @override
  Widget build(BuildContext context) {
    // Kachel-Registry: neue „wichtige Sachen" hier ergänzen.
    final tiles = <Widget>[
      _ClockTile(siteId: siteId, siteName: siteName),
      _StoreTasksTile(siteId: siteId, siteName: siteName),
      _CashCountTile(siteId: siteId, firestore: firestore),
      _FridgeTile(siteId: siteId),
      _ExpiryTile(siteId: siteId),
      _WishesTile(siteId: siteId, siteName: siteName, firestore: firestore),
      _HintsTile(siteId: siteId),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 720
                ? 2
                : 1;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final tile in tiles)
                SizedBox(
                  width: (constraints.maxWidth - 40 - (columns - 1) * 16) /
                      columns,
                  child: tile,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Gemeinsame Kachel-Hülle (Header + optionaler Zähler/Aktion + Inhalt).
class _KioskTile extends StatelessWidget {
  const _KioskTile({
    required this.icon,
    required this.title,
    required this.child,
    this.badge,
    this.badgeColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final String? badge;
  final Color? badgeColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? theme.colorScheme.primary)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: badgeColor ?? theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _KioskEmpty extends StatelessWidget {
  const _KioskEmpty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// ---- Stempeln --------------------------------------------------------------

class _ClockTile extends StatefulWidget {
  const _ClockTile({required this.siteId, required this.siteName});
  final String? siteId;
  final String siteName;

  @override
  State<_ClockTile> createState() => _ClockTileState();
}

class _ClockTileState extends State<_ClockTile> {
  final KioskClockService _service = KioskClockService.resolve();
  String? _sessionUid;
  bool? _clockedIn;
  bool _busy = false;

  Future<void> _refresh(AppUserProfile employee, String? sid) async {
    final value = await _service.isClockedIn(employee, sid: sid);
    if (mounted && employee.uid == _sessionUid) {
      setState(() => _clockedIn = value);
    }
  }

  Future<void> _toggle(
      KioskController controller, AppUserProfile employee) async {
    if (_busy) return;
    setState(() => _busy = true);
    controller.touch();
    final sid = controller.sessionId;
    final bool now;
    if (_clockedIn == true) {
      now = await _service.clockOut(employee, sid: sid);
    } else {
      now = await _service.clockIn(
        employee,
        sid: sid,
        siteId: widget.siteId,
        siteName: widget.siteName,
      );
    }
    if (mounted) {
      setState(() {
        _clockedIn = now;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KioskController>();
    final employee = controller.employee;

    // Session-Wechsel → Stempel-Status (neu) laden.
    if (employee?.uid != _sessionUid) {
      _sessionUid = employee?.uid;
      _clockedIn = null;
      if (employee != null) {
        final sid = controller.sessionId;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _refresh(employee, sid));
      }
    }

    Widget body;
    if (employee == null) {
      body = const _KioskEmpty('Zum Stempeln oben „Anmelden" antippen.');
    } else if (_clockedIn == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final clockedIn = _clockedIn!;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            clockedIn
                ? '${employee.displayName}: eingestempelt'
                : '${employee.displayName}: nicht eingestempelt',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          if (!clockedIn)
            FilledButton.icon(
              onPressed: _busy ? null : () => _toggle(controller, employee),
              icon: const Icon(Icons.login),
              label: const Text('Kommen'),
            )
          else
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _toggle(controller, employee),
              icon: const Icon(Icons.logout),
              label: const Text('Gehen'),
            ),
        ],
      );
    }

    return _KioskTile(
      icon: Icons.schedule,
      title: 'Zeiterfassung',
      child: body,
    );
  }
}

// ---- Kasse zählen (blind) --------------------------------------------------

/// **Kassen-Modul §7.3 — blinde Kassenzählung am Tablet.** Alle Mitarbeitenden
/// dürfen zählen (E2). Bewusst OHNE Soll/Differenz: das Tablet-Gerätekonto hat
/// kein Beleg-Leserecht und „Hinzählen" auf einen bekannten Wert soll gar nicht
/// erst möglich sein. Soll/Differenz sieht die Leitung im Tagesabschluss.
class _CashCountTile extends StatefulWidget {
  const _CashCountTile({required this.siteId, required this.firestore});
  final String? siteId;
  final FirestoreService firestore;

  @override
  State<_CashCountTile> createState() => _CashCountTileState();
}

class _CashCountTileState extends State<_CashCountTile> {
  bool _busy = false;

  Future<void> _count(
      KioskController controller, AppUserProfile employee) async {
    if (_busy) return;
    final siteId = widget.siteId;
    if (siteId == null) return;
    controller.touch();
    final messenger = ScaffoldMessenger.of(context);
    final inventory = context.read<InventoryProvider>();
    // Blind: kein Soll übergeben.
    final input = await showCashCountSheet(
      context,
      subtitle: 'Bitte das gesamte Bargeld in der Kasse zählen und eintragen.',
    );
    if (input == null) return;
    controller.touch();
    setState(() => _busy = true);
    final now = DateTime.now();
    final businessDay =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final sid = controller.sessionId;
    try {
      if (AppConfig.disableAuthentication || sid == null) {
        // Dev-Modus zeigt bewusst „braucht Internet" (Kasse ist cloud-only,
        // saveCashCount wirft im Local-Modus). Der Direkt-Write ist zudem der
        // defensive Fallback für den theoretischen real-cloud/sid==null-Fall,
        // den die Rules ohnehin abfangen.
        await inventory.saveCashCount(CashCount(
          orgId: '',
          siteId: siteId,
          businessDay: businessDay,
          countedAt: now,
          countedCents: input.countedCents,
          note: input.note,
          source: CashCount.sourceKiosk,
          countedByLabel: employee.displayName,
          countedByUserId: employee.uid,
          kioskSessionId: sid,
          createdByUid: '',
        ));
      } else {
        // Echtbetrieb (M6-E): gehärtetes Callable — die zählende Person kommt
        // server-authoritativ aus der Session, nicht vom Client.
        await widget.firestore.kioskSaveCashCount(
          sid: sid,
          countedCents: input.countedCents,
          businessDay: businessDay,
          note: input.note,
          siteId: siteId,
        );
      }
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Zählung gespeichert — danke!')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Zählung braucht Internet — bitte später erneut.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KioskController>();
    final employee = controller.employee;
    Widget body;
    if (employee == null) {
      body = const _KioskEmpty('Zum Zählen oben „Anmelden" antippen.');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Kasse zählen und den Bargeldbestand eintragen. '
            'Die Leitung prüft die Differenz.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _count(controller, employee),
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Kasse zählen'),
          ),
        ],
      );
    }
    return _KioskTile(
      icon: Icons.point_of_sale_outlined,
      title: 'Kasse zählen',
      child: body,
    );
  }
}

// ---- Laden-To-Dos ----------------------------------------------------------

class _StoreTasksTile extends StatelessWidget {
  const _StoreTasksTile({required this.siteId, required this.siteName});
  final String? siteId;
  final String siteName;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreTaskProvider>();
    final controller = context.watch<KioskController>();
    final open = provider.openStoreTasksForSite(siteId);
    final employee = controller.employee;

    return _KioskTile(
      icon: Icons.checklist_rtl,
      title: 'Laden-To-Dos',
      badge: open.isEmpty ? null : open.length.toString(),
      badgeColor: Theme.of(context).appColors.warning,
      trailing: provider.canManage
          ? IconButton(
              tooltip: 'Aufgabe anlegen',
              icon: const Icon(Icons.add),
              onPressed: () => showStoreTaskEditorSheet(
                context,
                siteId: siteId,
                siteName: siteName,
              ),
            )
          : null,
      child: open.isEmpty
          ? const _KioskEmpty('Keine offenen Aufgaben. 👍')
          : Column(
              children: [
                for (final task in open.take(6))
                  _StoreTaskRow(
                    task: task,
                    canCheck: employee != null,
                    onCheck: () {
                      controller.touch();
                      provider.markDoneForSite(
                        task,
                        siteId,
                        employeeId: employee?.uid,
                        employeeName: employee?.displayName,
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class _StoreTaskRow extends StatelessWidget {
  const _StoreTaskRow({
    required this.task,
    required this.canCheck,
    required this.onCheck,
  });
  final StoreTask task;
  final bool canCheck;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        task.isOverdue ? Icons.error_outline : Icons.radio_button_unchecked,
        color: task.isOverdue ? theme.appColors.warning : null,
      ),
      title: Text(task.title),
      subtitle: task.description == null ? null : Text(task.description!),
      trailing: canCheck
          ? FilledButton(
              onPressed: onCheck,
              child: const Text('Erledigt'),
            )
          : null,
    );
  }
}

// ---- Kühlschrank -----------------------------------------------------------

class _FridgeTile extends StatelessWidget {
  const _FridgeTile({required this.siteId});
  final String? siteId;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final controller = context.watch<KioskController>();
    final shortfalls = inventory.fridgeShortfalls(siteId: siteId);
    final canRefill = controller.employee != null;

    return _KioskTile(
      icon: Icons.kitchen_outlined,
      title: 'Kühlschrank nachfüllen',
      badge: shortfalls.isEmpty ? null : shortfalls.length.toString(),
      badgeColor: Theme.of(context).appColors.info,
      child: shortfalls.isEmpty
          ? const _KioskEmpty('Kühlschrank ist gut gefüllt.')
          : Column(
              children: [
                for (final s in shortfalls.take(6))
                  _FridgeRow(
                    shortfall: s,
                    canRefill: canRefill,
                    onRefill: () {
                      controller.touch();
                      inventory.refillFridge(s.product);
                    },
                  ),
              ],
            ),
    );
  }
}

class _FridgeRow extends StatelessWidget {
  const _FridgeRow({
    required this.shortfall,
    required this.canRefill,
    required this.onRefill,
  });
  final FridgeShortfall shortfall;
  final bool canRefill;
  final VoidCallback onRefill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = shortfall.product;
    final color = switch (shortfall.severity) {
      FridgeShortfallSeverity.empty => theme.colorScheme.error,
      FridgeShortfallSeverity.warehouseLow => theme.appColors.warning,
      FridgeShortfallSeverity.refill => theme.appColors.info,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.inventory_2_outlined, color: color),
      title: Text(p.name),
      subtitle: Text(
        'Kühlschrank ${p.fridgeStockClamped}/${p.fridgeTargetStock} · '
        'Lager ${shortfall.warehouseAvailable}',
      ),
      trailing: canRefill
          ? FilledButton.tonal(
              onPressed: onRefill,
              child: const Text('Nachgefüllt'),
            )
          : null,
    );
  }
}

// ---- MHD / Ablauf ----------------------------------------------------------

class _ExpiryTile extends StatelessWidget {
  const _ExpiryTile({required this.siteId});
  final String? siteId;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final controller = context.watch<KioskController>();
    final warnings = inventory.expiryWarnings(siteId: siteId);
    final canResolve = controller.employee != null;
    final hasExpired =
        warnings.any((w) => w.severity == ExpirySeverity.expired);

    return _KioskTile(
      icon: Icons.timelapse_outlined,
      title: 'Läuft bald ab',
      badge: warnings.isEmpty ? null : warnings.length.toString(),
      badgeColor: hasExpired
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).appColors.warning,
      child: warnings.isEmpty
          ? const _KioskEmpty('Nichts läuft in den nächsten Tagen ab.')
          : Column(
              children: [
                for (final w in warnings.take(6))
                  _ExpiryRow(
                    warning: w,
                    canResolve: canResolve,
                    onResolve: (status) {
                      controller.touch();
                      final id = w.batch.id;
                      if (id != null) {
                        inventory.resolveBatch(id, status: status);
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({
    required this.warning,
    required this.canResolve,
    required this.onResolve,
  });
  final ExpiryWarning warning;
  final bool canResolve;
  final void Function(BatchStatus status) onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batch = warning.batch;
    final color = switch (warning.severity) {
      ExpirySeverity.expired => theme.colorScheme.error,
      ExpirySeverity.critical => theme.appColors.warning,
      ExpirySeverity.soon => theme.appColors.info,
    };
    final days = warning.daysUntilExpiry;
    final when = days < 0
        ? 'seit ${-days} ${-days == 1 ? 'Tag' : 'Tagen'} abgelaufen'
        : days == 0
            ? 'läuft heute ab'
            : days == 1
                ? 'läuft morgen ab'
                : 'in $days Tagen';
    final d = '${batch.expiryDate.day.toString().padLeft(2, '0')}.'
        '${batch.expiryDate.month.toString().padLeft(2, '0')}.'
        '${batch.expiryDate.year}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.schedule_outlined, color: color),
      title: Text(batch.productName ?? 'Artikel'),
      subtitle: Text('MHD $d · $when'),
      trailing: canResolve
          ? PopupMenuButton<BatchStatus>(
              tooltip: 'Erledigt',
              icon: const Icon(Icons.check_circle_outline),
              onSelected: onResolve,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: BatchStatus.soldOut,
                  child: Text('Abverkauft'),
                ),
                PopupMenuItem(
                  value: BatchStatus.discarded,
                  child: Text('Entsorgt'),
                ),
              ],
            )
          : null,
    );
  }
}

// ---- Kundenwünsche ---------------------------------------------------------

class _WishesTile extends StatelessWidget {
  const _WishesTile({
    required this.siteId,
    required this.siteName,
    required this.firestore,
  });
  final String? siteId;
  final String siteName;
  final FirestoreService firestore;

  @override
  Widget build(BuildContext context) {
    // Offline-/Demo-Modus hat kein Firebase → Demo-Wünsche zeigen, damit das
    // Board lebendig ist. Im echten Betrieb der Live-Stream (wie im
    // Kundenwünsche-Screen).
    if (AppConfig.disableAuthentication) {
      final demo = _demoWishes(siteName);
      return _wishTile(context, demo);
    }
    final orgId = context.watch<AuthProvider>().profile?.orgId;
    if (orgId == null) {
      return _wishTile(context, const []);
    }
    return StreamBuilder<List<CustomerWish>>(
      stream: firestore.watchCustomerWishes(orgId),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <CustomerWish>[];
        final open = all
            .where((w) => w.status.isOpen)
            .where((w) => w.storeName.trim().isEmpty || w.storeName == siteName)
            .toList(growable: false);
        return _wishTile(context, open);
      },
    );
  }

  Widget _wishTile(BuildContext context, List<CustomerWish> wishes) {
    return _KioskTile(
      icon: Icons.card_giftcard_outlined,
      title: 'Kundenwünsche',
      badge: wishes.isEmpty ? null : wishes.length.toString(),
      badgeColor: Theme.of(context).colorScheme.primary,
      child: wishes.isEmpty
          ? const _KioskEmpty('Keine offenen Wünsche.')
          : Column(
              children: [
                for (final w in wishes.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: Text(w.wishText),
                    subtitle: Text(
                      '${w.category.label} · ${w.quantity}× · ${w.referenceCode}',
                    ),
                  ),
              ],
            ),
    );
  }

  static List<CustomerWish> _demoWishes(String storeName) => [
        CustomerWish(
          orgId: 'demo',
          referenceCode: 'K7Q-9X2',
          storeName: storeName,
          category: CustomerWishCategory.magazine,
          wishText: 'Spiegel Ausgabe 26',
          quantity: 1,
        ),
        CustomerWish(
          orgId: 'demo',
          referenceCode: 'M4T-2P8',
          storeName: storeName,
          category: CustomerWishCategory.tobacco,
          wishText: 'Eine Stange Marlboro Gold',
          quantity: 1,
        ),
      ];
}

// ---- Hinweise (Niedrigbestand) --------------------------------------------

class _HintsTile extends StatelessWidget {
  const _HintsTile({required this.siteId});
  final String? siteId;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final lowStock = inventory.products
        .where((p) => p.isActive && p.needsReorder)
        .toList(growable: false);

    return _KioskTile(
      icon: Icons.notifications_active_outlined,
      title: 'Hinweise',
      badge: lowStock.isEmpty ? null : lowStock.length.toString(),
      badgeColor: Theme.of(context).appColors.warning,
      child: lowStock.isEmpty
          ? const _KioskEmpty('Keine Hinweise.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Artikel mit niedrigem Bestand (nachbestellen):',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                for (final p in lowStock.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.trending_down),
                    title: Text(p.name),
                    subtitle: Text('Bestand ${p.currentStock}'),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anmeldung: Namensliste + 4-stelliges PIN-Pad (Increment 0: Dev-Pfad)
// ---------------------------------------------------------------------------

class _KioskLoginSheet extends StatefulWidget {
  const _KioskLoginSheet({
    required this.roster,
    required this.pinService,
    required this.onAuthenticated,
  });
  final List<AppUserProfile> roster;
  final KioskPinService pinService;
  final void Function(AppUserProfile employee, String sid) onAuthenticated;

  @override
  State<_KioskLoginSheet> createState() => _KioskLoginSheetState();
}

class _KioskLoginSheetState extends State<_KioskLoginSheet> {
  AppUserProfile? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: _selected == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Wer bist du?', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                if (widget.roster.isEmpty)
                  const _KioskEmpty('Keine Mitarbeiter hinterlegt.')
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in widget.roster)
                          ListTile(
                            leading: CircleAvatar(
                              child: Text(_initials(m.displayName)),
                            ),
                            title: Text(m.displayName),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() => _selected = m),
                          ),
                      ],
                    ),
                  ),
              ],
            )
          : _PinPad(
              employee: _selected!,
              pinService: widget.pinService,
              onBack: () => setState(() => _selected = null),
              onSuccess: (sid) {
                final employee = _selected!;
                Navigator.of(context).pop();
                widget.onAuthenticated(employee, sid);
              },
            ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _PinPad extends StatefulWidget {
  const _PinPad({
    required this.employee,
    required this.pinService,
    required this.onBack,
    required this.onSuccess,
  });
  final AppUserProfile employee;
  final KioskPinService pinService;
  final VoidCallback onBack;
  final void Function(String sid) onSuccess;

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> {
  String _pin = '';
  bool _error = false;
  String _errorMsg = 'PIN eingeben';
  bool _checking = false;

  Future<void> _onDigit(String d) async {
    if (_pin.length >= 4 || _checking) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == 4) {
      await _verify();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    final result = await widget.pinService.beginSession(
      employee: widget.employee,
      pin: _pin,
    );
    if (!mounted) return;
    if (result.ok) {
      widget.onSuccess(result.sid!);
    } else {
      setState(() {
        _error = true;
        _errorMsg = result.error ?? 'Falsche PIN, bitte erneut.';
        _pin = '';
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
            ),
            Expanded(
              child: Text(
                widget.employee.displayName,
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _error ? _errorMsg : 'PIN eingeben',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _error ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _NumPad(onDigit: _onDigit, onBackspace: _onBackspace),
        if (AppConfig.disableAuthentication)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Demo: Standard-PIN ${KioskPinStore.demoPin}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _NumPad extends StatelessWidget {
  const _NumPad({required this.onDigit, required this.onBackspace});
  final void Function(String) onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 84,
            height: 64,
            child: OutlinedButton(
              onPressed: onTap,
              child: child,
            ),
          ),
        );
    Widget digit(String d) =>
        key(Text(d, style: Theme.of(context).textTheme.headlineSmall),
            () => onDigit(d));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          digit('1'),
          digit('2'),
          digit('3'),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          digit('4'),
          digit('5'),
          digit('6'),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          digit('7'),
          digit('8'),
          digit('9'),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          key(const SizedBox.shrink(), null),
          digit('0'),
          key(const Icon(Icons.backspace_outlined), onBackspace),
        ]),
      ],
    );
  }
}
