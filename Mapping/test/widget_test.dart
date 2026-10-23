import 'package:flutter_test/flutter_test.dart';
import 'package:rbpssk_plot_area/main.dart';

void main() {
  testWidgets('Renders India Gazetteer Map Screen', (WidgetTester tester) async {
    await tester.pumpWidget(const IndiaGazetteerMapApp());
    expect(find.byType(IndiaMapScreen), findsOneWidget);
  });
}
