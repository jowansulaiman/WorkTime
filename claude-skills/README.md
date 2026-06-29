# Claude Skills für professionelle Flutter-Entwicklung

Eine Sammlung von **19 hochwertigen System-Prompts („Skills")** für die professionelle Softwareentwicklung mit **Flutter** — eine Codebasis für **Web, iOS, Android und Desktop** (macOS, Windows, Linux). Jeder Skill macht Claude zum spezialisierten Experten für eine Domäne und ist auf den Flutter-/Dart-Cross-Platform-Stack zugeschnitten: Dart-Idiome, Flutter-Packages, plattformspezifische Unterschiede über alle vier Targets und ein Flutter-Client-orientierter Blick auf Backend-Themen.

Jeder Skill ist **eigenständig** und folgt demselben Aufbau: Rolle & Kontext, acht Kernkompetenzen mit konkreten Techniken/Packages und zahlenbasierten Faustregeln sowie ein definiertes Antwortverhalten inklusive Anti-Pattern-Warnungen.

---

## Übersicht der 19 Skills

| #  | Skill | Ordner | Flutter-Schwerpunkte |
|----|-------|--------|----------------------|
| 01 | API-Sicherheit | `sicherheit/` | `flutter_secure_storage`, OAuth2/PKCE (`flutter_appauth`), Cert-Pinning (`dio`), keine Secrets im Bundle, OWASP API Top 10 |
| 02 | Software-Sicherheit | `sicherheit/` | OWASP MASVS/MASTG, `--obfuscate`, Platform-Channel-Security, Web-Hardening (CSP/XSS), Secure SDLC |
| 03 | UX-/UI-Design (Design Intelligence) | `architektur/` | Design-System-First-Workflow, priorisierte Regelhierarchie (A11y/Touch CRITICAL), Pre-Delivery-Anti-Pattern-Checkliste, Material 3 + Cupertino, `ThemeExtension`-Tokens, Profi-Details (keine Emoji-Icons, Safe-Area, Dark-Mode-Kontrast) |
| 04 | Software-Architektur | `architektur/` | Layered (Presentation/Domain/Data), Feature-First, Repository, DI (`get_it`/Riverpod), `go_router`, SOLID in Dart |
| 05 | Microservices (Backend) | `architektur/` | Backend für Flutter-Clients: Modular-Monolith-first, Dart-Backend vs. BaaS, BFF/API-Gateway, Resilience, Saga/Outbox |
| 06 | API-Architektur | `architektur/` | REST/GraphQL/gRPC, Cursor-Pagination, **Versionierung/Abwärtskompatibilität**, Dart-Codegen, Realtime + Offline |
| 07 | Clean Code | `entwicklung/` | Effective Dart, strikte Lints, Sound Null Safety, Immutability (`freezed`/Records), Widget-Komposition |
| 08 | Testing & QA | `entwicklung/` | Test-Pyramide, Unit/Widget/Integration (`patrol`), **Golden Tests**, Mocking (`mocktail`), CI-Plattform-Matrix |
| 09 | CI/CD & DevOps | `entwicklung/` | Codemagic/GitHub Actions, 5 Build-Targets, Code-Signing (Fastlane `match`), Force-Update, OTA (Shorebird) |
| 10 | Performance | `entwicklung/` | DevTools (Profile-Mode), Frame-Budget 16ms/8ms, Rebuild-Minimierung (`const`/`select`), `compute()`/Isolates, App-Size |
| 11 | Refactoring & Tech-Debt | `entwicklung/` | Characterization Tests, Flutter-Smells (God-Widget), `dart fix`, Strangler Fig für Migrationen, Tech-Debt-Quadrant |
| 12 | Error Handling & Resilience | `entwicklung/` | Typed `Result`/`Either`, globale Handler, Offline-First-Retry, `mounted`-Checks, Crash-Reporting |
| 13 | State-Management & Frontend-Architektur | `entwicklung/` | Riverpod/Bloc-Auswahl, unidirektionaler Datenfluss, Widget-/Element-/RenderObject-Baum, `go_router` |
| 14 | Observability | `entwicklung/` | Crashlytics/`sentry_flutter`, Crash-free Users, strukturiertes Logging, Analytics, RUM, Tracing Client→Backend |
| 15 | Cross-Platform-Entwicklung | `entwicklung/` | Eine Codebasis/4 Targets, `kIsWeb`/Platform-Detection, Platform Channels (Pigeon/FFI), Mobile/Desktop/Web-Spezifika |
| 16 | Datenbank | `daten/` | On-Device: Drift/Isar/Hive/sqflite, Secure Storage, Migrationen, Lokale-DB-als-Cache, Encryption at Rest |
| 17 | Datenbankarchitektur (Backend) | `daten/` | Sync-taugliches Schema (`updated_at`, Tombstones, client-IDs), Delta-Queries, Multi-Tenancy/RLS, BaaS-Modellierung |
| 18 | Backend-Daten | `daten/` | APIs/Sync-Endpunkte für Clients, Dart-Backends (Serverpod/Dart Frog), OLTP/OLAP-Trennung, pragmatische Pipelines |
| 19 | Datensynchronisierung | `daten/` | **Offline-First**, Sync-Engines (PowerSync/Firestore), CRDTs (`crdt`), Konfliktauflösung (LWW/HLC), CAP/PACELC, Outbox |

---

## Installation & Nutzung

### Variante A: claude.ai (Projects)

1. Lege in claude.ai ein **Project** an (z. B. „Flutter-Architektur").
2. Öffne **Project instructions** (benutzerdefinierte Anweisungen).
3. Kopiere den Inhalt der gewünschten `.md`-Skill-Datei dort hinein.
4. Alle Chats in diesem Project nutzen nun diesen Experten-Kontext.

Tipp: Lege pro Schwerpunkt ein eigenes Project an, oder kombiniere passende Skills (siehe unten) in einem Project.

### Variante B: API (System-Prompt)

Der Skill-Inhalt wird als `system`-Parameter übergeben. Modellnamen bitte in der offiziellen Dokumentation verifizieren (Stand kann abweichen): z. B. `claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`.

**Python:**

```python
import anthropic

with open("entwicklung/13_frontend-architektur.md", encoding="utf-8") as f:
    skill = f.read()

client = anthropic.Anthropic()  # API-Key über Umgebungsvariable ANTHROPIC_API_KEY

message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=2000,
    system=skill,  # Skill als System-Prompt
    messages=[
        {
            "role": "user",
            "content": "Wie strukturiere ich State Management für eine Offline-First-Flutter-App?",
        }
    ],
)

print(message.content[0].text)
```

**JavaScript / TypeScript:**

```javascript
import Anthropic from "@anthropic-ai/sdk";
import { readFileSync } from "node:fs";

const skill = readFileSync("entwicklung/13_frontend-architektur.md", "utf-8");

const client = new Anthropic(); // API-Key über ANTHROPIC_API_KEY

const message = await client.messages.create({
  model: "claude-sonnet-4-6",
  max_tokens: 2000,
  system: skill, // Skill als System-Prompt
  messages: [
    {
      role: "user",
      content: "Wie strukturiere ich State Management für eine Offline-First-Flutter-App?",
    },
  ],
});

console.log(message.content[0].text);
```

---

## Empfohlene Skill-Kombinationen

Für typische Szenarien lassen sich mehrere Skills sinnvoll kombinieren:

| Szenario | Empfohlene Skills |
|----------|-------------------|
| **Neue Flutter-App aufsetzen** | 04 Architektur · 13 State-Management · 07 Clean Code · 15 Cross-Platform |
| **Offline-First-App bauen** | 19 Datensynchronisierung · 16 Datenbank · 12 Error Handling · 17 Datenbankarchitektur |
| **Backend für die App entwerfen** | 05 Microservices · 06 API-Architektur · 18 Backend-Daten · 17 Datenbankarchitektur |
| **UI/UX über alle Plattformen** | 03 UX-/UI-Design · 15 Cross-Platform · 13 State-Management · 10 Performance |
| **Sicherheit härten** | 02 Software-Sicherheit · 01 API-Sicherheit · 16 Datenbank (Encryption) |
| **Qualität & Auslieferung** | 08 Testing & QA · 09 CI/CD & DevOps · 14 Observability · 11 Refactoring |
| **Performance-Optimierung** | 10 Performance · 13 State-Management · 15 Cross-Platform · 14 Observability |
| **Legacy-Code modernisieren** | 11 Refactoring · 08 Testing & QA · 04 Architektur · 07 Clean Code |

---

## Hinweise

- Alle Skills sind auf **Deutsch** verfasst; etablierte englische Fachbegriffe (z. B. *Circuit Breaker*, *Sharding*, *CRDT*) bleiben englisch.
- Wo der **Backend-Stack** offen ist (Skills 05, 17, 18), werden Annahmen inline benannt — u. a. Dart-Backends (Serverpod, Dart Frog, `shelf`) sowie BaaS (Firebase, Supabase).
- Faustregeln sind bewusst **zahlenbasiert** (Breakpoints, Frame-Budgets, Coverage-Ziele), um konkret statt vage zu sein.
- Skill 03 (UX/UI) wurde methodisch am Open-Source-Skill **ui-ux-pro-max** (`github.com/nextlevelbuilder/ui-ux-pro-max-skill`) ausgerichtet — Design-System-First-Workflow, priorisierte Regelkategorien (Apple HIG / Material Design) und Pre-Delivery-Anti-Pattern-Checkliste — und vollständig auf Flutter/Dart adaptiert.
- Die Skills referenzieren sich gegenseitig (z. B. verweist Sync auf Datenbank und Resilience), lassen sich aber auch einzeln nutzen.

---

## Variante C: Claude Code (auto-ladende Skills)

Aus jedem der 19 Experten-Prompts wird ein **auto-ladender Claude-Code-Skill** unter `.claude/skills/flutter-<domäne>/SKILL.md` erzeugt. Claude Code entdeckt diese beim Start automatisch; die `description` im Frontmatter trägt die Trigger-Keywords, sodass der passende Skill bei einer relevanten Aufgabe von selbst greift (oder per Slash-Command `/flutter-cross-platform` usw.). Jede `SKILL.md` ist bewusst dünn: Frontmatter + Pointer auf den **verbindlichen** Quell-Prompt hier in `claude-skills/` (Single Source of Truth) + die extrahierten Kernkompetenzen.

```bash
node claude-skills/build-skills.mjs          # erzeugt/aktualisiert alle 19 Skills nach .claude/skills/
node claude-skills/build-skills.mjs --check   # CI: schlägt fehl, wenn Skills veraltet sind (exit 1)
node claude-skills/validate-skills.mjs        # Discovery-Check: parst jedes Frontmatter wie Claude Code
```

**Nach dem Editieren eines Prompts** in `claude-skills/` → `build-skills.mjs` erneut ausführen (Titel, Rollen-Satz und Kernkompetenz-Liste werden aus der Quelle extrahiert, bleiben also in Sync). Slug, `description` (Auto-Lade-Signal) und die `Einsatz`-Zeile stehen pro Skill in der `SKILLS`-Tabelle in `build-skills.mjs`.
