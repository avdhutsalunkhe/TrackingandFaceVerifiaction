import 'package:flutter_test/flutter_test.dart';
import 'package:rbpssk_plot_area/main.dart';

void main() {
  testWidgets('Renders GPS Journey Tracker placeholder screen', (WidgetTester tester) async {
    await tester.pumpWidget(const GpsJourneyTrackerApp());
    expect(find.text('GPS Journey Tracker'), findsWidgets);
  });
}
