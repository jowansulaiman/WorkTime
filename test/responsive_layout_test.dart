import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/widgets/responsive_layout.dart';

void main() {
  group('MobileBreakpoints Window-Size-Classes', () {
    test('NavigationRail erst ab 600dp (medium)', () {
      expect(MobileBreakpoints.useNavigationRail(599), isFalse);
      expect(MobileBreakpoints.useNavigationRail(600), isTrue);
      expect(MobileBreakpoints.useNavigationRail(1024), isTrue);
    });

    test('Alle Rail-Labels erst ab 840dp (expanded)', () {
      expect(MobileBreakpoints.useExpandedRailLabels(839), isFalse);
      expect(MobileBreakpoints.useExpandedRailLabels(840), isTrue);
    });
  });
}
