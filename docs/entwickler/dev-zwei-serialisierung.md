# Die Zwei-Serialisierungs-Regel

Dies ist der **wichtigste Footgun** des Projekts. Jedes Model hat **zwei nicht austauschbare Serialisierungsformate**. Sie zu verwechseln verliert still Daten.

## Die zwei Formate

| Methoden | Keys | Datum/Zahlen | Verwendung |
| --- | --- | --- | --- |
| `toFirestoreMap()` / `fromFirestore(id, map)` | **camelCase** | `Timestamp` / `serverTimestamp()` | direkte Firestore-Writes **und** Seeding von `FakeFirebaseFirestore` in Tests |
| `toMap()` / `fromMap(map)` | **snake_case** | ISO-8601-Strings | SharedPreferences **und** Cloud-Function-Callable-Payloads |

## Regeln

- `fromFirestore` bekommt die Doc-ID als **separates erstes Argument** (`fromFirestore(doc.id, doc.data())`); Firestore-Maps enthalten die `id` nie. `fromMap` liest `map['id']`.
- Parser **nie hart casten**. Zahlen/Bools via `import '../core/firestore_num_parser.dart' as parse;` → `parse.toInt/toDouble/toBool/toMap` (tolerant für num|String|bool|null). Daten via `FirestoreDateParser.readDate` (camelCase/Firestore) bzw. `readLocalDate` (snake_case/lokal).
- `copyWith` kann ein Feld **nicht** durch `null` leeren → explizites `clearX: true`-Flag (Muster `clearX ? null : (x ?? this.x)`).

## Die WorkEntry-Ausnahme

> [!NOTE]
> `WorkEntry` hat eigene `_parseFirestoreDate`/`_parseStoredDate`, die bei fehlendem/kaputtem Datum eine `FormatException` **werfen** (kein Fallback). `date` wird auf lokale Mittagszeit (12:00) normalisiert; lokal als `'YYYY-MM-DD'`-String, in Firestore als `Timestamp`.

## Callables verlangen snake_case

> [!WARNING]
> Eine Callable bekommt `toMap()` (**snake_case**). `toFirestoreMap()` an eine Callable zu schicken **verliert still Felder** – der Server (`parseShift`/`parseWorkEntry`) versteht nur snake_case.

## Ein Feld hinzufügen = 6 Stellen

Ein neues Model-Feld berührt **6 Stellen**:

1. `toFirestoreMap`
2. `fromFirestore`
3. `toMap`
4. `fromMap`
5. `copyWith` (+ `clearX` wenn nullable)
6. falls es durch Callables geht: snake_case parse/serialize in `functions/index.js`

Siehe [Kritische Kopplungen](article:dev-kritische-kopplungen).

## Weiter

- [Speichermodi & lokale Persistenz](article:dev-storage-modi)
- [Cloud Functions](article:dev-cloud-functions)
- [Test-Konventionen](article:dev-testing)
