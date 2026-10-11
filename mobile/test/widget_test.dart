import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yabosen_controller/src/api.dart';
import 'package:yabosen_controller/src/settings.dart';
import 'package:yabosen_controller/src/status_controller.dart';
import 'package:yabosen_controller/src/ui/schedule/schedule_tab.dart';
import 'package:yabosen_controller/src/ui/status/status_tab.dart';
import 'package:yabosen_controller/src/ui/theme.dart';

YabosenApi _fakeApi() => YabosenApi(
  apiKey: 'k',
  client: MockClient((request) async {
    final body = switch (request.url.path) {
      '/api/status' => {
        'status': 'idle',
        'customMessage': 'brb food',
        'activityType': null,
        'activityName': null,
        'episodeInfo': null,
        'seasonInfo': null,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        '_debug': {'storedStatus': 'online'},
      },
      '/api/sleep-schedule' => {
        'enabled': true,
        'sleepyTime': '23:30',
        'wakeyTime': '08:00',
      },
      _ => {'error': 'not found'},
    };
    return http.Response(jsonEncode(body), 200);
  }),
);

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: child),
);

/// A small phone: 320 x 667 logical pixels.
void _usePhoneSize(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(960, 2000)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('status tab renders status, message and all buttons', (
    tester,
  ) async {
    _usePhoneSize(tester);
    final api = _fakeApi();
    final status = StatusController(api);
    await status.refresh();

    await tester.pumpWidget(
      _wrap(
        StatusTab(
          statusController: status,
          apiKey: ApiKeyController(api),
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Idle'), findsWidgets);
    expect(find.text('brb food'), findsWidgets);
    expect(find.textContaining('PC heartbeat is stale'), findsOneWidget);
    for (final label in ['Online', 'Offline', 'DND', 'Sleeping', 'Streaming']) {
      expect(find.text(label), findsWidgets);
    }

    // Switching activity reveals the watching fields.
    await tester.tap(find.text('Watching'));
    await tester.pump();
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Season'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule tab loads and shows the times', (tester) async {
    _usePhoneSize(tester);
    final api = _fakeApi();
    await tester.pumpWidget(
      _wrap(ScheduleTab(api: api, apiKey: ApiKeyController(api))),
    );
    await tester.pumpAndSettle();

    expect(find.text('23:30'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.textContaining('Europe/Bucharest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
