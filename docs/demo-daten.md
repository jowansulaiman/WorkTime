# Demo-Daten zum vollstaendigen Softwaretest

Der lokale Demo-Modus wird mit einem zusammenhaengenden, reproduzierbaren
Datensatz gestartet. Die fachlichen Fixtures verwenden stabile, eindeutig
erkennbare Demo-IDs. Etablierte Login-UIDs und fachlich vorgegebene
Schluesselformate bleiben kompatibel. Dadurch kann der Seeder seine eigenen
Datensaetze bei jedem Demo-Login aktualisieren, ohne selbst angelegte lokale
Datensaetze zu entfernen.

## Start

```bash
flutter run --dart-define=APP_DISABLE_AUTH=true
```

Fuer die standardmaessig ausgeblendeten, aber lokal testbaren Rollout-Bereiche:

```bash
flutter run \
  --dart-define=APP_DISABLE_AUTH=true \
  --dart-define=APP_SIGNAGE_ENABLED=true \
  --dart-define=APP_DATEV_LOHN_ENABLED=true \
  --dart-define=APP_OKTOPOS_ENABLED=true
```

Der Laden-Tablet-/Kiosk-Ablauf wird separat gestartet, weil er die normale
Navigation absichtlich ersetzt:

```bash
flutter run \
  --dart-define=APP_DISABLE_AUTH=true \
  --dart-define=APP_KIOSK_ENABLED=true
```

Beim Werbe-Player kann mit der Standard-Organisation beispielsweise der Code
`demo-main-org-tabak-display-token` gekoppelt werden. Weitere Codes stehen in
der Display-Verwaltung.

Das Passwort aller Demo-Konten lautet `demo1234`.

| Rolle | Login | Besonderheit |
|---|---|---|
| Admin | `admin@demo.local` | alle Verwaltungs-, Personal-, Finanz- und Auditbereiche |
| Teamleitung | `lea.teamlead@example.com` | Planung und Freigaben |
| Inhaber/Planer | `jowan@demo.local` | drei Standorte |
| Mitarbeiter | `peter@example.com` | offene Stempelung und eigene Anfragen |
| Mitarbeiter | `maria@example.com` | zweites Profil fuer Mehrpersonenablaeufe |
| Mitarbeiter | `maike@demo.local` | Paketshop Fruehdienst |
| Mitarbeiter | `edith@demo.local` | Paketshop Spaetdienst |
| Mitarbeiter | `raffael@demo.local` | Paketshop und Tabak Boerse |
| Mitarbeiter | `majd@demo.local` | Strichmaennchen und Tabak Boerse |
| Mitarbeiter | `tom@demo.local` | Strichmaennchen Spaetdienst |
| Mitarbeiter | `jarla@demo.local` | zwei Standorte |
| Mitarbeiter | `johanna@demo.local` | Tabak Boerse Fruehdienst |
| Mitarbeiter | `jean@demo.local` | Tabak Boerse Tagdienst |

## Abdeckung

Der Referenzdatensatz enthaelt bewusst sowohl regulaere Beispiele als auch
Warn-, Konflikt- und Abschlusszustaende:

- Organisation: drei Standorte, Oeffnungszeiten, Personalbedarf,
  Fremdgeldarten, Teams, Einladungen, Qualifikationen, Vertraege,
  Mehrfach-Standortzuweisungen, Schichtpraeferenzen, Compliance- und
  Fahrtzeitregeln.
- Dienstplan und Anfragen: alle Schichtstatus, offene und zugewiesene
  Schichten, Wiederholungen, Nachtschicht, Vorlagen, alle Abwesenheitsarten und
  -status, halbe Tage, Tauschanfragen und Tauschgutschriften.
- Zeitwirtschaft: Arbeitszeit- und Stempelstatus, App-/Kiosk-Ursprung,
  Korrektur- und Klaerungsfaelle, Vorlagen sowie positive und negative
  Stundenkonten.
- Personal und Lohn: Stammdatenvarianten, Kinder, Notizen, Qualifikationen,
  Ausbildungen, Sollzeit, Urlaub, Arbeitsauftraege, Lohnarten, Lohnprofile und
  Lohnabrechnungsstatus.
- Warenwirtschaft: Lieferanten und Artikel an allen Standorten, Null-/Niedrig-/
  Normalbestand, Kuehlschrankartikel, Chargen/MHD, alle Bestell- und
  Bewegungsstatus, Preisverlauf, Scanresultate, Bestellkorb, Wochenliste,
  Nachfuellliste und Kundenbestellungen.
- Kasse und Auswertungen: Verkaufs- und Retourenbelege, Steuersaetze,
  Zahlarten, Tagesaggregate, Kassensoll/-ist, positive/negative/keine
  Differenz, Fremdgeld und abgeschlossene bzw. gebuchte Geschaeftstage.
- CRM: Kontaktarten, Firmen/Personen, Aktivitaeten, Detaildaten,
  Kontaktorganisationen, Kundenwuensche und Feedback in allen Kategorien und
  Bearbeitungsstatus.
- Finanzen: aktive/inaktive Kostenstellen, alle Kostenartgruppen, Kosten und
  Gutschriften ueber mehrere Perioden, Gesamt-/Einzelbudgets und eine
  vollstaendige DATEV-Konfiguration sowie Finanz- und Lohn-Exporthistorien mit
  reproduzierbaren und bewusst gekappten Snapshots.
- Betrieb: Laden-To-dos aller Prioritaeten, Broadcast-/Standortaufgaben,
  Signage-Medien und Displays mit allen Uebergaengen, sowie alle Auditaktionen.
- Oeffentliche und spezielle Oberflaechen: Kundenwunsch- und Feedbackformular,
  interne Eingaenge mit Bearbeitung, Werbe-Player-Projektion sowie
  Laden-Tablet/Kiosk mit Standortdaten.

Relative Daten wie Schichten, MHD-Warnungen, Aufgaben und Monatsauswertungen
werden an den aktuellen Tag bzw. Monat angelehnt. So bleiben sie auch nach
einem spaeteren App-Start in den Standardfiltern sichtbar.

## Bewusste technische Grenzen

Der Passwortmanager zeigt im lokalen Modus aus Sicherheitsgruenden keine
Klartext-Secrets: Entschluesselung und Re-Authentifizierung benoetigen Cloud KMS.
Datei-Uploads, Push-Token, Kiosk-PIN-Sessions und echte externe OktoPOS-Syncs
benoetigen ebenfalls die jeweiligen Backends. Die zugehoerigen fachlichen
Ansichten werden mit Metadaten bzw. abgeleiteten Demo-Fakten befuellt; der reale
Netzwerk-/Berechtigungstest muss getrennt gegen Firebase-Emulatoren oder eine
Testumgebung erfolgen.
