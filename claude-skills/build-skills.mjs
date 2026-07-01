#!/usr/bin/env node
// Generiert auto-ladende Claude-Code-Skills aus den Experten-System-Prompts in
// claude-skills/. Quelle der Wahrheit bleibt der jeweilige .md-Prompt; jeder
// erzeugte Skill ist eine dünne SKILL.md (Frontmatter zum Auto-Laden + Pointer
// auf den Prompt + extrahierte Kernkompetenzen).
//
//   node claude-skills/build-skills.mjs           # generiert + validiert
//   node claude-skills/build-skills.mjs --check    # nur validieren (CI-tauglich, exit 1 bei Fehler)
//
// Nach dem Editieren eines Prompts in claude-skills/ erneut ausführen.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));      // <repo>/claude-skills
const REPO = dirname(HERE);                                 // <repo>
const SKILLS_DIR = join(REPO, '.claude', 'skills');
const CHECK_ONLY = process.argv.includes('--check');

// Pro Skill nur das, was nicht aus der Quelle ableitbar ist:
//   slug    -> Verzeichnis + Frontmatter-name + Slash-Command
//   src     -> Quell-Prompt (relativ zum Repo-Root)
//   desc    -> Frontmatter-description: DAS Auto-Lade-Signal. Trigger-Verben/Keywords rein.
//   einsatz -> kurze "wann anwenden"-Zeile für den Skill-Body
const SKILLS = [
  {
    slug: 'flutter-api-sicherheit',
    src: 'claude-skills/sicherheit/01_api-sicherheit.md',
    desc: 'API-Sicherheit der Flutter-App: sichere Token-Speicherung pro Plattform (flutter_secure_storage, Keychain/Keystore), OAuth2/OIDC mit PKCE (flutter_appauth), TLS & Certificate Pinning (dio), keine Secrets im Client-Bundle, serverseitige Autorisierung nach OWASP API Security Top 10, Eingabevalidierung/Injection-Schutz, Rate Limiting, CORS/Header-Hygiene (Web). Einsetzen bei Auth-Flows, Token-Handling, API-Calls, Secrets, Cert-Pinning.',
    einsatz: 'Auth-Flows, Token-Speicherung, API-Calls absichern, Secrets, Certificate Pinning, OWASP-API-Review.',
  },
  {
    slug: 'flutter-software-sicherheit',
    src: 'claude-skills/sicherheit/02_software-sicherheit.md',
    desc: 'App-Sicherheit & Härtung der Flutter-App: Threat Modeling (STRIDE), OWASP MASVS/Mobile Top 10, Code-Obfuscation & Tamper-Schutz (--obfuscate), sichere lokale Datenspeicherung, sichere Dart-Coding-Praktiken, Platform-Channel-/Plugin-Sicherheit, Web-Hardening (CSP/XSS), Secure SDLC. Einsetzen bei Sicherheits-Reviews, Obfuscation, Reverse-Engineering-Schutz, Härtung.',
    einsatz: 'Sicherheits-Reviews, Threat Modeling, Obfuscation, Reverse-Engineering-Schutz, Web-Hardening.',
  },
  {
    slug: 'flutter-ux-ui-design',
    src: 'claude-skills/architektur/03_ux-ui-design.md',
    desc: 'UI/UX-Design der Flutter-App nach Design-System-First-Workflow und priorisierter Regelhierarchie: Barrierefreiheit & Touch (kritisch), Performance, visuelle Konsistenz, responsive Layout, Typografie/Farbe, Motion, Formulare/Navigation. Material 3 + Cupertino, ThemeExtension-Tokens, Anti-Pattern-Checkliste vor Auslieferung. Einsetzen beim Bauen/Überarbeiten von Screens, Widgets, Layouts, Themes, Accessibility.',
    einsatz: 'Screens/Widgets bauen oder überarbeiten, Layout, Theme, Accessibility, visuelle Politur.',
  },
  {
    slug: 'flutter-software-architektur',
    src: 'claude-skills/architektur/04_software-architektur.md',
    desc: 'Software-Architektur der Flutter-App: Schichtenarchitektur (Presentation/Domain/Data), Feature-First-Struktur, Repository Pattern, Dependency Injection (get_it/Riverpod), SOLID in Dart, State-/Navigations-Architektur (go_router), Plattformneutralität, ADRs. Einsetzen bei Architekturentscheidungen, Modul-Schnitt, Entkopplung, Testbarkeit, neuen Features.',
    einsatz: 'Architekturentscheidungen, Modul-Schnitt, Entkopplung, Testbarkeit, neue Features strukturieren.',
  },
  {
    slug: 'flutter-microservices-backend',
    src: 'claude-skills/architektur/05_microservices.md',
    desc: 'Backend-/Microservices-Architektur hinter der Flutter-App: Topologie-Wahl (Modular-Monolith-first, Microservices, BaaS, Dart-Backend), Backend for Frontend & API-Gateway, Domänen-Schnitt (DDD), synchrone/asynchrone Kommunikation, Resilienz-Patterns, verteilte Datenkonsistenz (Saga/Outbox), Containerisierung. Einsetzen beim Entwurf der serverseitigen Plattform, Service-Schnitt, Backend-Topologie.',
    einsatz: 'Serverseitige Plattform entwerfen, Service-Schnitt, Backend-Topologie, Resilienz, verteilte Konsistenz.',
  },
  {
    slug: 'flutter-api-architektur',
    src: 'claude-skills/architektur/06_api-architektur.md',
    desc: 'API-Architektur zwischen Flutter-Client und Backend: Paradigmenwahl REST/GraphQL/gRPC, RESTful-Ressourcenmodellierung, client-effiziente Payloads & Cursor-Pagination, Versionierung & Rückwärtskompatibilität, API-Verträge & Dart-Codegen, Auth/Rate-Limiting, Echtzeit & Offline. Einsetzen beim Entwurf/Ändern von API-Endpunkten, Verträgen, Pagination, Versionierung.',
    einsatz: 'API-Endpunkte/Verträge entwerfen oder ändern, Pagination, Versionierung, Rückwärtskompatibilität.',
  },
  {
    slug: 'flutter-clean-code',
    src: 'claude-skills/entwicklung/07_clean-code.md',
    desc: 'Clean Code in Dart/Flutter: Effective Dart & Style, strenges Linting, Sound Null Safety, Immutabilität & Datenmodelle (freezed/Records), saubere Widget-Komposition, SOLID im Kleinen, Code Smells erkennen, Doku/Async-Hygiene. Einsetzen beim Schreiben/Aufräumen von Dart-Code, Naming, Widget-Grenzen, Lint-Fixes, Lesbarkeit.',
    einsatz: 'Dart-Code schreiben/aufräumen, Naming, Widget-Grenzen ziehen, Lint-Fixes, Lesbarkeit.',
  },
  {
    slug: 'flutter-testing-qa',
    src: 'claude-skills/entwicklung/08_testing-qa.md',
    desc: 'Tests & QA für Flutter: Testpyramide, Unit-Tests (package:test), Widget-Tests (flutter_test), Integration-Tests (integration_test/patrol), Golden-Tests (visuelle Regression), Test-Doubles & Mocking (mocktail), TDD/BDD, CI-Plattform-Matrix. Einsetzen beim Schreiben/Erweitern von Tests, Test-Strategie, Flaky-Tests, Coverage.',
    einsatz: 'Tests schreiben oder erweitern, Test-Strategie, Golden-Tests, Mocking, Flaky-Tests, Coverage.',
  },
  {
    slug: 'flutter-cicd-devops',
    src: 'claude-skills/entwicklung/09_cicd-devops.md',
    desc: 'CI/CD & DevOps für die Flutter-App: Pipelines (GitHub Actions/Codemagic), plattformspezifische Builds (5 Targets), Code-Signing & Credentials (Fastlane match), Store-Deployment, Flavors/Umgebungen, Versionierung/Release-Strategie, Feature Flags, OTA (Shorebird). Einsetzen bei Build-Pipelines, Signing, Release, Deployment, Force-Update.',
    einsatz: 'Build-Pipelines, Code-Signing, Store-Deployment, Flavors, Release-Strategie, Force-Update/OTA.',
  },
  {
    slug: 'flutter-performance',
    src: 'claude-skills/entwicklung/10_performance.md',
    desc: 'Performance-Engineering für Flutter: Messen mit DevTools (Profile-Mode), Frame-Budget 16ms/8ms, Rebuilds minimieren (const/select), Listen & Lazy Rendering, Render-Kosten (Paint/Clipping/Opacity), compute()/Isolates, Startzeit & App-Größe, Web/CanvasKit-Spezifika. Einsetzen bei Jank, langsamem Start, großem Bundle, Rebuild-Problemen, Profiling.',
    einsatz: 'Jank/Frame-Drops, langsamer Start, großes Bundle, zu viele Rebuilds, Profiling mit DevTools.',
  },
  {
    slug: 'flutter-refactoring-techdebt',
    src: 'claude-skills/entwicklung/11_refactoring-techdebt.md',
    desc: 'Refactoring & Tech-Debt in Flutter/Dart: verhaltenserhaltende Verbesserung mit Sicherheitsnetz (Characterization Tests), IDE-/dart-fix-gestütztes Refactoring, Flutter-Smells (God-Widget), Refactoring-Katalog (Fowler in Dart), Tech-Debt klassifizieren/sichtbar machen, Legacy-/Migrationsstrategien (Strangler Fig), Abhängigkeitsschulden. Einsetzen bei Umbauten, Migrationen, Tech-Debt-Abbau, Code-Smells.',
    einsatz: 'Umbauten, Migrationen (Null Safety/M3/go_router), Tech-Debt-Abbau, God-Widget & Code-Smells.',
  },
  {
    slug: 'flutter-error-handling',
    src: 'claude-skills/entwicklung/12_error-handling-resilience.md',
    desc: 'Fehlerbehandlung & Resilienz in Flutter: Dart-Fehlermodell (Exception vs. Error), typisierte Ergebnisse (Result/Either) statt Exceptions für erwartbare Fälle, globale Handler, Fehler-UI & Graceful Degradation, Netzwerk-Resilienz (Retry/Timeout/Circuit Breaker), Offline-First-Resilienz, Async-/Lifecycle-Fallen (mounted-Checks), Fehler-Beobachtbarkeit. Einsetzen bei Fehlerpfaden, Retry-Logik, Offline-Handling, Crash-Schutz.',
    einsatz: 'Fehlerpfade, Retry/Timeout, Offline-Handling, mounted-Fallen, Graceful Degradation, Crash-Schutz.',
  },
  {
    slug: 'flutter-state-management',
    src: 'claude-skills/entwicklung/13_frontend-architektur.md',
    desc: 'State-Management & Frontend-Architektur in Flutter: State-Strategie & -Auswahl (Riverpod/Bloc/Provider), unidirektionaler Datenfluss & Immutabilität, Widget-/Element-/RenderObject-Baum, Navigation & Routing (go_router), responsive UI-Architektur, Struktur/Performance/DevX der UI-Schicht. Einsetzen bei State-Design, Provider-Struktur, Rebuild-Scoping, Routing, UI-Architektur.',
    einsatz: 'State-Design, Provider-/Notifier-Struktur, Rebuild-Scoping, Routing, responsive UI-Architektur.',
  },
  {
    slug: 'flutter-observability',
    src: 'claude-skills/entwicklung/14_observability.md',
    desc: 'Observability der Flutter-App: Crash-/Fehler-Reporting (Crashlytics/sentry_flutter), strukturiertes Logging, Analytics & Produkt-Telemetrie, Performance-Monitoring (RUM), Distributed Tracing Client→Backend, Custom Metrics/Health-Signale, DevTools, datenschutzkonforme Signale. Einsetzen bei Logging, Crash-Reporting, Monitoring, Tracing, Analytics, SLOs.',
    einsatz: 'Logging, Crash-Reporting, RUM/Monitoring, Tracing Client→Backend, Analytics, Health-Signale/SLOs.',
  },
  {
    slug: 'flutter-logging',
    src: 'claude-skills/entwicklung/20_logging.md',
    desc: 'Logging-Mechanik der Flutter-App + Cloud Functions: zentrale Logger-Fassade (AppLogger/ErrorReporter) statt verstreuter debugPrint/print, Log-Level & Release-Verhalten (kein print im Release, produktiv warning+), strukturiertes Log-Schema mit Korrelations-/Request-IDs Client→Function, PII-/Secret-Redaction (E-Mail-Maskierung, niemals API-Keys/Tokens/PII/Header/Bodies), Sinks/Transport & externalSink-Adapter, plattformspezifische Ausgabe (Web-Konsole/os_log/Logcat/Desktop, kIsWeb), Performance-Kosten/Compile-Out, Abgrenzung technisches Logging vs. fachliches Audit-Trail (AuditProvider). Serverseitig firebase-functions/logger (strukturierte Cloud-Logs, Severity, niemals Secrets). Einsetzen beim Hinzufügen/Vereinheitlichen von Logs, debugPrint-Migration, Log-Redaction, Request-Korrelation, API-/Cloud-Functions-Logging.',
    einsatz: 'Logs hinzufügen/vereinheitlichen, debugPrint→AppLogger migrieren, Log-Schema/Redaction, Request-Korrelation Client→Function, Cloud-Functions-/API-Logging.',
  },
  {
    slug: 'flutter-cross-platform',
    src: 'claude-skills/entwicklung/15_mobile-entwicklung.md',
    desc: 'Cross-Platform-Entwicklung der Flutter-App aus einer Codebasis (Web/iOS/Android/Desktop): kIsWeb-zuerst & Platform-Detection (dart:io wirft im Web), Platform Channels & natives Interop (Pigeon/FFI), federated Plugins, adaptive UI, Mobile-Spezifika (Push/Permissions/Deep-Links/Lifecycle), Desktop (Fenster/Menüs/Dateizugriff), Web (CanvasKit/PWA/js_interop). Einsetzen bei plattformspezifischem Code, Platform Channels, Web/Desktop-Eigenheiten.',
    einsatz: 'Plattformspezifischer Code, kIsWeb/Platform-Checks, Platform Channels (Pigeon/FFI), Web/Desktop-Eigenheiten.',
  },
  {
    slug: 'flutter-datenbank',
    src: 'claude-skills/daten/16_datenbank.md',
    desc: 'Lokale Datenpersistenz in Flutter: On-Device-DBs (Drift/Isar/Hive/sqflite), Auswahl nach Zugriffsmuster, Secure Storage für Secrets, Schema/Indizes/Queries auf dem Gerät, Migrationen, lokale DB als Cache & Offline-Source-of-Truth, Encryption at Rest. Einsetzen bei lokaler Speicherung, Caching, On-Device-Schema, Migrationen, Verschlüsselung.',
    einsatz: 'Lokale Speicherung, On-Device-Schema/Indizes, Migrationen, Cache-Strategie, Encryption at Rest.',
  },
  {
    slug: 'flutter-datenbankarchitektur',
    src: 'claude-skills/daten/17_datenbankarchitektur.md',
    desc: 'Backend-Datenbankarchitektur für sync-/offline-fähige Flutter-Clients: Datenmodellierung & Normalisierung, sync-taugliches Schema (updated_at, Tombstones, client-IDs), Change-Feeds & Delta-Queries, Indizierung/Query-Performance, Multi-Tenancy & Row-Level-Security, Replikation/Partitionierung/Sharding, Konsistenz/Transaktionen, BaaS-Modellierung. Einsetzen beim Entwurf von Backend-Schemata, Sync-Schema, Multi-Tenancy, Skalierung.',
    einsatz: 'Backend-Schema entwerfen, sync-taugliches Modell, Change-Feeds, Multi-Tenancy/RLS, Skalierung.',
  },
  {
    slug: 'flutter-backend-daten',
    src: 'claude-skills/daten/18_backend-daten.md',
    desc: 'Backend-Datenschicht für die Flutter-App: APIs & Sync-Endpunkte/Change-Feeds, Dart-Backend-Optionen (Serverpod/Dart Frog/shelf), BaaS-Alternativen, OLTP/OLAP-Trennung, pragmatische Datenpipelines (ETL/ELT), Streaming/Echtzeit, Caching/Validierung/Datenqualität. Einsetzen beim Bauen von Backend-Datenflüssen, Sync-Endpunkten, Pipelines, Echtzeit-Daten.',
    einsatz: 'Backend-Datenflüsse, Sync-Endpunkte/Change-Feeds, Pipelines, OLTP/OLAP-Trennung, Echtzeit-Daten.',
  },
  {
    slug: 'flutter-datensynchronisierung',
    src: 'claude-skills/daten/19_datensynchronisierung.md',
    desc: 'Offline-First-Datensynchronisierung in Flutter: Offline-First-Architektur, fertige Sync-Engines (PowerSync/Firestore), Delta-Sync/Cursor/Tombstones, Outbox-Queue & zuverlässige Übertragung, Konfliktauflösung (LWW/HLC), CRDTs, CAP/PACELC-Trade-offs, Hintergrund-Sync & Konflikt-UX. Einsetzen bei Offline-Sync, Konfliktauflösung, Delta-Abgleich, eventual consistency.',
    einsatz: 'Offline-Sync, Konfliktauflösung (LWW/HLC/CRDT), Delta-Abgleich, Outbox, Hintergrund-Sync, Konflikt-UX.',
  },
  {
    slug: 'flutter-offline-modus',
    src: 'claude-skills/daten/21_offline-modus.md',
    desc: 'Offline-Modus einer Flutter-App auf Web/iOS/Android: Scoping (read-only vs. read-write offline, degraded mode, was offline gesperrt wird), Konnektivität erkennen (connectivity_plus + echter Reachability-Check, navigator.onLine, entprelltes Online-Enum im App-State), Plattform-Persistenz-Matrix (Web IndexedDB-Quota/Eviction/Inkognito/Safari-ITP vs. mobile App-Sandbox), Web-Offline (PWA, Service Worker, App-Shell-/Asset-Caching, flutter_service_worker.js, manifest.json, Installierbarkeit), Firestore-/BaaS-Offline-Persistenz plattformgerecht (mobile default vs. Web kIsWeb-Zweig/cacheSettings, vor erstem Read), Offline-Schreiben/Optimistic UI/Pending-Zustand, Hintergrund-/Resume-Sync-Grenzen (workmanager/Doze, iOS BGTaskScheduler, kein Web-Background), Offline-UX (Banner/zuletzt-aktualisiert/Graceful Degradation) und Offline testen. Einsetzen, wenn die App offline nutzbar/installierbar sein soll, bei Offline-Banner/-Indikatoren, Caching, PWA, Offline-Verfügbarkeit pro Plattform.',
    einsatz: 'App offline nutzbar machen (Web/iOS/Android), Offline-Verfügbarkeit scopen, Konnektivitäts-State, PWA/Service-Worker-Caching, Firestore-Offline-Persistenz, Offline-UX, Offline testen.',
  },
  {
    slug: 'flutter-code-review',
    src: 'claude-skills/review/22_code-entwicklungs-review.md',
    desc: "Code- & Entwicklungs-Review der Flutter/WorkTime-App: Diff/Branch/PR prüfen gegen die Definition of Done (flutter analyze + flutter test, Offline-Lauf APP_DISABLE_AUTH), Korrektheit & Bug-Klassen (Null-Safety, await/mounted, _safeNotify, copyWith-clearX, Storage-Modus-Fallback), die Zwei-Serialisierungs-Regel (camelCase toFirestoreMap vs. snake_case toMap, 6 Stellen pro Model-Feld, Callable braucht snake_case), die kritischen Kopplungen (Compliance-Spiegel compliance_service.dart ↔ functions/index.js, Enum .value/fromValue, Provider-Kette, Firestore-Write-Pfade, Functions-Region, Gate-Route/Tab), Provider-/Architektur-Konformität (lazy Cloud-Repo, AuditSink nur auf Erfolgs-Pfad), Sicherheit & Multi-Tenancy (sameOrg ↔ assertSameOrg, Callable=validierter Pfad, Secrets nie im Client, Composite-Index), Test-Konventionen (Fakes statt echtem Firebase, de_DE) und UI-/Konventions-Konformität (Deutsch-only, appColors, Permission-Getter). Einsetzen beim Reviewen von Code, Diffs, Pull-Requests und vor dem Commit.",
    einsatz: 'Code/Diff/Branch/PR reviewen vor Commit, Korrektheit & Bug-Suche, Kopplungs- & Zwei-Serialisierungs-Check, Compliance-Spiegel, Provider-/Architektur-/Konventions-Konformität, Quality Gates.',
  },
  {
    slug: 'flutter-plan-output-review',
    src: 'claude-skills/review/23_plan-output-review.md',
    desc: "Plan- & Output-Review für WorkTime: Plan-Dokumente (versioniert im plan/-Ordner, MEMORY.md-Index) und von Claude erzeugte Outputs/Diffs vor Auslieferung prüfen. Plan-Review: Struktur & Vollständigkeit (Ziel/Scope, Meilensteine mit Status, Datenmodell, Deploy-Schritte, offene Punkte, absolute Daten), Machbarkeit & Architektur-Fit (Provider-Kette, drei Storage-Modi, Zwei-Serialisierung, Compliance-Spiegel, bewusste Grenzen wie öffentliche Web-Routen und Callable-Pfad), Kopplungs- & Risiko-Check (Composite-Index? Rules+Functions synchron? Blaze/Secret?), Scope & Inkrement-Schnitt (kleinster lauffähiger offline-testbarer Schritt, Batch-Limit 50). Output-Review: Korrektheit & Treue zur Anfrage (keine erfundenen Datei-/Symbolnamen, ehrlich berichtete Tests, offengelegte Annahmen), Konventionen (Deutsch, Datei-Links, Memory-/Plan-Ablage), Abnahme/Übergabe (Definition of Done, Restrisiken, nächste Schritte). Einsetzen beim Prüfen/Abnehmen von Plänen und beim Selbst-Review von Outputs vor der Übergabe.",
    einsatz: 'Plan-Dokumente (plan/) prüfen/abnehmen (Vollständigkeit, Machbarkeit, Kopplungen, Meilenstein-Schnitt) und Outputs/Antworten/Diffs vor Übergabe selbst-reviewen (Korrektheit, Treue zur Anfrage, Konventionen, Definition of Done).',
  },
];

function extract(srcAbs) {
  const text = readFileSync(srcAbs, 'utf-8');
  const lines = text.split('\n');

  const h1 = lines.find((l) => /^#\s+/.test(l)) ?? '# (ohne Titel)';
  const title = h1.replace(/^#\s+/, '').replace(/^System-Prompt:\s*/i, '').trim();

  // Erste Sätze der "## Rolle & Kontext"-Sektion (bis zur nächsten ## oder Leerzeile-Block).
  let role = '';
  const roleIdx = lines.findIndex((l) => /^##\s+Rolle/i.test(l));
  if (roleIdx >= 0) {
    const buf = [];
    for (let i = roleIdx + 1; i < lines.length; i++) {
      if (/^##\s+/.test(lines[i])) break;
      if (lines[i].trim()) buf.push(lines[i].trim());
      else if (buf.length) break;
    }
    const para = buf.join(' ');
    // erste zwei Sätze als knappe Rolle
    const m = para.match(/^(.*?\.\s+.*?\.)\s/);
    role = (m ? m[1] : para).trim();
  }

  // Kernkompetenz-Header "### N. Titel"
  const comps = lines
    .filter((l) => /^###\s+\d+\.\s+/.test(l))
    .map((l) => l.replace(/^###\s+\d+\.\s+/, '').trim());

  return { title, role, comps };
}

function relFromSkillToSrc(slug, src) {
  // von .claude/skills/<slug>/SKILL.md nach <src> (relativ zum Repo)
  const from = join(SKILLS_DIR, slug);
  return relative(from, join(REPO, src));
}

function buildSkillMd(s, info) {
  const link = relFromSkillToSrc(s.slug, s.src);
  const comps = info.comps.map((c, i) => `${i + 1}. ${c}`).join('\n');
  return `---
name: ${s.slug}
description: "${s.desc.replace(/"/g, "'")}"
---

# ${info.title}

> **Verbindliche Fachautorität — vor der Arbeit in dieser Domäne lesen und anwenden.**
> Vollständiger Experten-Prompt (Techniken, Packages, zahlenbasierte Faustregeln, Anti-Patterns):
> [\`${s.src}\`](${link}) · relativ zum Projekt-Root: \`${s.src}\`

${info.role}

**Einsatz:** ${s.einsatz}

## Kernkompetenzen (Details + Faustregeln im Quelldokument)
${comps}

## Antwortverhalten
Lies das Quelldokument und wende seine \`## Antwortverhalten\`-Direktiven samt Anti-Pattern-Warnungen an, bevor du Lösungen vorschlägst. Verankere Entscheidungen darin — es ist die verbindliche Fachautorität für diesen Bereich. Antworte auf Deutsch; etablierte englische Fachbegriffe bleiben englisch.
`;
}

// ---- Lauf ----
const problems = [];
const written = [];

for (const s of SKILLS) {
  const srcAbs = join(REPO, s.src);
  if (!existsSync(srcAbs)) {
    problems.push(`FEHLT Quelle: ${s.src} (für ${s.slug})`);
    continue;
  }
  if (!/^[a-z0-9-]+$/.test(s.slug)) problems.push(`Ungültiger slug: ${s.slug}`);
  if (s.desc.length > 1024) problems.push(`description zu lang (${s.desc.length}>1024): ${s.slug}`);

  const info = extract(srcAbs);
  if (info.comps.length !== 8) {
    problems.push(`WARN ${s.slug}: ${info.comps.length} Kernkompetenzen extrahiert (erwartet 8)`);
  }

  const out = join(SKILLS_DIR, s.slug, 'SKILL.md');
  const md = buildSkillMd(s, info);

  if (CHECK_ONLY) {
    if (!existsSync(out)) problems.push(`fehlt (nur --check): ${out}`);
    else if (readFileSync(out, 'utf-8') !== md) problems.push(`veraltet (nur --check): ${s.slug}`);
  } else {
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, md);
    written.push(s.slug);
  }
}

const slugs = SKILLS.map((s) => s.slug);
const dupes = slugs.filter((v, i) => slugs.indexOf(v) !== i);
if (dupes.length) problems.push(`Doppelte slugs: ${[...new Set(dupes)].join(', ')}`);

if (!CHECK_ONLY) console.log(`Geschrieben: ${written.length} Skills nach ${relative(REPO, SKILLS_DIR)}/`);
if (problems.length) {
  console.error('\nProbleme:\n' + problems.map((p) => '  - ' + p).join('\n'));
  process.exit(1);
}
console.log(CHECK_ONLY ? 'Check OK: alle Skills aktuell und valide.' : 'OK: alle Skills valide.');
