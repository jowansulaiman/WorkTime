import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/models/app_user.dart';
import 'package:worktime_app/models/user_settings.dart';
import 'package:worktime_app/theme/app_theme.dart';
import 'package:worktime_app/widgets/app_nav_rail.dart';

/// Isolierter Widget-Test fuer die modernisierte V2-Seitenleiste [AppNavRail]:
/// zeigt alle Nav-Labels, meldet die Auswahl und oeffnet ueber den Account-Knopf
/// das Menue. Rein praesentational — kein Provider-Stack noetig.
const _admin = AppUserProfile(
  uid: 'admin-1',
  orgId: 'org-1',
  email: 'admin@example.com',
  role: UserRole.admin,
  isActive: true,
  settings: UserSettings(name: 'Sandra'),
);

const _items = [
  AppNavRailItem(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Heute',
  ),
  AppNavRailItem(
    icon: Icons.view_timeline_outlined,
    selectedIcon: Icons.view_timeline,
    label: 'Plan',
  ),
  AppNavRailItem(
    icon: Icons.schedule_outlined,
    selectedIcon: Icons.schedule,
    label: 'Zeit',
  ),
  AppNavRailItem(
    icon: Icons.inbox_outlined,
    selectedIcon: Icons.inbox,
    label: 'Anfragen',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  int selectedIndex = 1,
  ValueChanged<int>? onSelected,
  VoidCallback? onOpenMenu,
  bool expandedLabels = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1000);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolveLight(useV2: true),
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavRail(
              items: _items,
              selectedIndex: selectedIndex,
              onSelected: onSelected ?? (_) {},
              onOpenMenu: onOpenMenu ?? () {},
              user: _admin,
              expandedLabels: expandedLabels,
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async => initializeDateFormatting('de_DE'));

  testWidgets('zeigt alle Nav-Labels + Rollen-Label', (tester) async {
    await _pump(tester);
    expect(find.text('Heute'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Zeit'), findsOneWidget);
    expect(find.text('Anfragen'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget); // Account-Knopf zeigt die Rolle
  });

  testWidgets('Tap auf Eintrag meldet den Index', (tester) async {
    int? selected;
    await _pump(tester, onSelected: (index) => selected = index);
    await tester.tap(find.text('Zeit'));
    await tester.pump();
    expect(selected, 2);
  });

  testWidgets('Account-Knopf oeffnet das Menue', (tester) async {
    var opened = false;
    await _pump(tester, onOpenMenu: () => opened = true);
    await tester.tap(find.byTooltip('Menü öffnen'));
    await tester.pump();
    expect(opened, isTrue);
  });
}
