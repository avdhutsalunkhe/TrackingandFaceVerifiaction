import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fieldstaff_attendance/screens/admin/employee_travel_map_screen.dart';

// 1x1 transparent PNG for tile mocking
final _transparentPng = <int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0,
  0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84, 120,
  156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68,
  174, 66, 96, 130
];

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool bufferOutput = true;

  @override
  int contentLength = 0;

  @override
  bool persistentConnection = false;

  @override
  void add(List<int> data) {}

  @override
  void write(Object? obj) {}

  @override
  Future addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> close() async {
    return _MockHttpClientResponse();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _transparentPng.length;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(_transparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest();

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

void main() {
  setUp(() {
    HttpOverrides.global = _TestHttpOverrides();
    SharedPreferences.setMockInitialValues({
      'role': 'ADMIN',
      'user_id': 1,
      'token': 'test_token',
    });
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('Employee Travel Map renders configuration, summary, and map with NO employee dropdown', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 1200));

    await tester.pumpWidget(
      const MaterialApp(
        home: EmployeeTravelMapScreen(
          initialEmployeeId: 31673,
          initialEmployeeCode: '31673',
          initialEmployeeName: 'Hemant Patil',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Header
    expect(find.text('Employee Travel Map'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsWidgets);

    // 2. Strict UI Requirement: NO Employee dropdown anywhere
    expect(find.text('Select Employee'), findsNothing);
    expect(find.text('Employee *'), findsNothing);
    expect(find.byType(DropdownButtonFormField), findsNothing);

    // 3. Verify Travel Map Configuration
    expect(find.text('Travel Map Configuration'), findsOneWidget);
    expect(find.text('View Travel Route'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);

    // 4. Verify Travel Summary section & Resolved Employee Info
    expect(find.text('Travel Summary'), findsOneWidget);
    expect(find.text('Hemant Patil'), findsOneWidget);
    expect(find.text('ID: 31673'), findsOneWidget);
    expect(find.text('Tracking Status'), findsOneWidget);
    expect(find.text('Start Time'), findsOneWidget);
    expect(find.text('End Time'), findsOneWidget);
    expect(find.text('Travel Distance'), findsOneWidget);
    expect(find.text('Total Points'), findsOneWidget);

    // 5. Verify Recorded Travel Route Map Card & Controls
    expect(find.text('Recorded Travel Route'), findsOneWidget);
    expect(find.text('Fit to Route'), findsOneWidget);
    expect(find.text('Hide Points'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
  });

  testWidgets('Employee Travel Map shows informative error state when employee context is missing for admin', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 800));

    await tester.pumpWidget(
      const MaterialApp(
        home: EmployeeTravelMapScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify missing employee message and button
    expect(find.text('No Employee Selected'), findsOneWidget);
    expect(find.text('Open Employee List'), findsOneWidget);
    // Still NO employee dropdown
    expect(find.byType(DropdownButtonFormField), findsNothing);
  });
}
