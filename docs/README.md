# WorkTime – Wissen & Handbuch (`docs/`)

Dieses Verzeichnis ist die **Single Source of Truth** der WorkTime-Dokumentation. Aus denselben Markdown-Quellen speisen sich **zwei** Ausgabewege:

1. **In-App-Viewer** „Wissen" (`/wissen`) – für alle angemeldeten Nutzer; Admins sehen zusätzlich die Technik-Doku.
2. **Statische Web-Doku-Site** (`docs-site/`) – per Browser oder statischem Hosting.

## Aufbau

```
docs/
  manifest.json          # Baum: Abschnitte → Artikel (Titel, Rolle, Icon, Suchbegriffe)
  mitarbeiter/*.md       # Fach-/Bedien-Doku (audience: mitarbeiter)
  entwickler/*.md        # technische Doku (audience: entwickler, admin-only)
```

`manifest.json` ist der Index. Jeder Artikel hat `slug`, `title`, `file`, `roleGate` (`all`|`manager`|`admin`), `summary`, `keywords`.

## Erlaubte Markdown-Teilmenge

Der In-App-Renderer (`lib/widgets/markdown_view.dart`) und der Web-Generator unterstützen bewusst dieselbe Teilmenge:

- `#`/`##`/`###`-Überschriften (erste Zeile = genau eine `#` mit dem Titel)
- Absätze, `-`/`1.`-Listen, `**fett**`, `*kursiv*`, `` `code` ``
- Zaun-Codeblöcke ```` ``` ````, Pipe-Tabellen, Trennlinie `---`
- Callouts: `> [!TIP|NOTE|WARNING|IMPORTANT|CAUTION]`
- Links: extern `[Text](https://…)`, **intern** `[Text](article:<slug>)`

Code-Dateien werden als Inline-Code referenziert (z. B. `lib/main.dart`), **nicht** als Markdown-Link.

## Web-Site bauen

```bash
node scripts/build-docs-site.mjs   # erzeugt docs-site/ (gitignored)
```

Danach `docs-site/index.html` im Browser öffnen oder als statisches Hosting ausliefern.

## Einen Artikel hinzufügen

1. `.md`-Datei unter `docs/mitarbeiter/` bzw. `docs/entwickler/` anlegen (erste Zeile `# Titel`).
2. Eintrag im passenden Abschnitt in `manifest.json` ergänzen (`slug`, `title`, `file`, `roleGate`, `summary`, `keywords`).
3. `flutter test test/doc_manifest_integrity_test.dart` prüft Existenz, `#`-Titel und gültige `article:`-Links.
4. Der In-App-Viewer nutzt die gebündelten Assets (`pubspec.yaml` registriert `docs/manifest.json` + die beiden Verzeichnisse). Bei neuen Dateien reicht `flutter pub get` nicht immer – ein Rebuild bündelt die neuen Assets.

## Sichtbarkeit

- `audience: entwickler` ⇒ nur Admins (im Viewer als Abschnitt „Technik").
- `roleGate: all` ⇒ jeder aktive Nutzer · `manager` ⇒ Admin/Schichtleitung · `admin` ⇒ nur Admin.

Die Logik lebt in `DocArticle.isVisibleTo(profile)` (`lib/models/doc_article.dart`) und spiegelt die App-Berechtigungen.
