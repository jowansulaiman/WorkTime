import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worktime_app/screens/public/signage_token_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('leer -> load() gibt null', () async {
    expect(await SignageTokenStore.load(), isNull);
  });

  test('save/load merkt den Token (Auto-Start nach Neustart)', () async {
    await SignageTokenStore.save('TOKEN123');
    expect(await SignageTokenStore.load(), 'TOKEN123');
  });

  test('save trimmt und ignoriert Leer-Eingaben', () async {
    await SignageTokenStore.save('  PAD  ');
    expect(await SignageTokenStore.load(), 'PAD');

    await SignageTokenStore.save('   ');
    // unverändert (leerer Wert überschreibt nicht)
    expect(await SignageTokenStore.load(), 'PAD');
  });

  test('clear entfernt den gemerkten Token', () async {
    await SignageTokenStore.save('X');
    await SignageTokenStore.clear();
    expect(await SignageTokenStore.load(), isNull);
  });
}
