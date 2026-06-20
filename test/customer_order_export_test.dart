import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:worktime_app/models/customer_order.dart';
import 'package:worktime_app/services/export_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  List<String> rows(String csv) => csv.split('\n');

  CustomerOrder order() => CustomerOrder(
        orgId: 'org-1',
        siteId: 'site-1',
        siteName: 'Tabak Boerse',
        customerName: 'Herr Schmidt',
        customerContact: '0151 2345678',
        orderNumber: 'KB-2026-0007',
        status: CustomerOrderStatus.open,
        recurrence: CustomerOrderRecurrence.weekly,
        pickupDate: DateTime(2026, 6, 20, 12),
        items: const [
          CustomerOrderItem(
            name: 'Pueblo Tabak 30g',
            category: 'Drehtabak',
            quantity: 5,
            unitPriceCents: 650,
          ),
        ],
      );

  test('buildCustomerOrderCsv beginnt mit BOM und Titelzeile', () {
    final csv = ExportService.buildCustomerOrderCsv(orders: [order()]);
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('Kundenbestellungen Export'));
  });

  test('enthaelt Kopfzeile mit ;-Trenner und alle Spalten', () {
    final csv = ExportService.buildCustomerOrderCsv(orders: [order()]);
    expect(
      csv,
      contains(
        'Bestellnr.;Kunde;Kontakt;Laden;Abholtermin;Rhythmus;Status;Vorbereitet;Positionen;Summe;Notiz',
      ),
    );
  });

  test('Datenzeile enthaelt Kundenwerte', () {
    final csv = ExportService.buildCustomerOrderCsv(orders: [order()]);
    final dataLine = rows(csv).firstWhere(
      (line) => line.contains('Herr Schmidt'),
    );
    final cols = dataLine.split(';');
    expect(cols[0], 'KB-2026-0007');
    expect(cols[1], 'Herr Schmidt');
    expect(cols[4], '20.06.2026');
    expect(cols[5], 'Wöchentlich');
    expect(cols[6], 'Offen');
    expect(cols[7], 'Nein');
    expect(cols[8], contains('5x Pueblo Tabak 30g'));
  });

  test('siteLabel erscheint als Metazeile', () {
    final csv = ExportService.buildCustomerOrderCsv(
      orders: [order()],
      siteLabel: 'Tabak Boerse',
    );
    expect(csv, contains('Laden;Tabak Boerse'));
  });

  test('Felder mit ; werden in Anfuehrungszeichen gesetzt (Escaping)', () {
    const tricky = CustomerOrder(
      orgId: 'org-1',
      siteId: 'site-1',
      customerName: 'Meier; Sohn',
      items: [CustomerOrderItem(name: 'A', quantity: 1)],
    );
    final csv = ExportService.buildCustomerOrderCsv(orders: [tricky]);
    expect(csv, contains('"Meier; Sohn"'));
  });
}
