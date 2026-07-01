import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/services/push_messaging_service.dart';

void main() {
  group('channelIdForType — Ereignistyp → Android-Channel', () {
    test('Genehmigungen: Abwesenheit + alle Tausch-Phasen', () {
      for (final type in [
        'absence_submitted',
        'absence_decision',
        'shift_swap_request',
        'shift_swap_accepted',
        'shift_swap_declined',
        'shift_swap_confirmed',
        'shift_swap_rejected',
      ]) {
        expect(channelIdForType(type), 'genehmigungen', reason: type);
      }
    });

    test('Schichtplan: veröffentlicht + offen', () {
      expect(channelIdForType('shift_published'), 'schichtplan');
      expect(channelIdForType('shift_open'), 'schichtplan');
    });

    test('Kundenwünsche / Bestand / Aufgaben', () {
      expect(channelIdForType('customer_wish'), 'kundenwuensche');
      expect(channelIdForType('low_stock'), 'bestand');
      expect(channelIdForType('expiry'), 'bestand');
      expect(channelIdForType('customer_feedback'), 'aufgaben');
    });

    test('unbekannter Typ → Default-Channel (aufgaben)', () {
      expect(channelIdForType('irgendwas'), 'aufgaben');
      expect(channelIdForType(''), 'aufgaben');
    });
  });
}
