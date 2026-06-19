// Architektur-Fitness-Check (no-architecture-fitness-lint).
//
// Erzwingt die Importgrenze: die Presentation-Schicht (lib/screens/**) darf
// nicht direkt aus der Service-Schicht (lib/services/**) importieren — Daten-
// zugriff laeuft ueber Provider/Repositories. Bekannte, bewusste Ausnahmen sind
// unten gewhitelistet (reine Datei-Erzeugungs-/Export-Helfer ohne Datenzugriff).
//
// Aufruf:  dart run tool/check_layering.dart
// Exit 0 = sauber, Exit 1 = Verletzung (CI bricht ab).
import 'dart:io';

/// screen-Pfad -> erlaubte Service-Dateinamen.
const Map<String, Set<String>> allowedServiceImports = <String, Set<String>>{
  'lib/screens/statistics_screen.dart': {'download_service.dart'},
  'lib/screens/month_report_screen.dart': {'export_service.dart'},
  'lib/screens/shift_planner_screen.dart': {'export_service.dart'},
};

final RegExp _serviceImport = RegExp(
  r'''^\s*import\s+['"](?:package:worktime_app/services/|\.\./services/)([^'"]+)['"]''',
);

void main() {
  final screensDir = Directory('lib/screens');
  if (!screensDir.existsSync()) {
    stderr.writeln('lib/screens nicht gefunden – im Projektwurzelverzeichnis ausfuehren.');
    exit(2);
  }

  final violations = <String>[];
  for (final entity in screensDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final relativePath = entity.path.replaceAll('\\', '/');
    final allowed = allowedServiceImports[relativePath] ?? const <String>{};
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = _serviceImport.firstMatch(lines[i]);
      if (match == null) {
        continue;
      }
      final service = match.group(1)!;
      if (!allowed.contains(service)) {
        violations.add('$relativePath:${i + 1} -> services/$service');
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln(
      'Architektur-Verletzung: lib/screens darf lib/services nicht direkt importieren.',
    );
    for (final violation in violations) {
      stderr.writeln('  - $violation');
    }
    stderr.writeln(
      'Datenzugriff ueber Provider/Repository fuehren oder die Ausnahme in '
      'tool/check_layering.dart pflegen.',
    );
    exit(1);
  }

  stdout.writeln('Layering OK: keine unerlaubten screens->services Importe.');
}
