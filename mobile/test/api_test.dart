import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yabosen_controller/src/api.dart';
import 'package:yabosen_controller/src/models.dart';

void main() {
  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('POST /api/status sends bearer auth and JSON body', () async {
    late http.Request captured;
    final api = YabosenApi(
      apiKey: 'secret',
      client: MockClient((request) async {
        captured = request;
        return json({'success': true});
      }),
    );
    await api.setStatus(const StatusUpdate(status: StatusKind.idle));
    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'https://yabosen.live/api/status');
    expect(captured.headers['Authorization'], 'Bearer secret');
    expect(jsonDecode(captured.body), {'status': 'idle'});
  });

  test('401 becomes an unauthorized ApiException', () async {
    final api = YabosenApi(
      apiKey: 'wrong',
      client: MockClient(
        (_) async => json({'error': 'Unauthorized: Invalid API Key'}, 401),
      ),
    );
    await expectLater(
      api.setStatus(const StatusUpdate(status: StatusKind.online)),
      throwsA(
        isA<ApiException>().having(
          (e) => e.isUnauthorized,
          'unauthorized',
          true,
        ),
      ),
    );
  });

  test('server error message is surfaced', () async {
    final api = YabosenApi(
      apiKey: 'k',
      client: MockClient(
        (_) async => json({'error': 'Invalid status', 'details': 'nope'}, 400),
      ),
    );
    await expectLater(
      api.setStatus(const StatusUpdate(status: StatusKind.online)),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Invalid status: nope (400)',
        ),
      ),
    );
  });

  test('missing key fails before any request', () async {
    var called = false;
    final api = YabosenApi(
      client: MockClient((_) async {
        called = true;
        return json({});
      }),
    );
    await expectLater(api.sendHeartbeat(), throwsA(isA<ApiException>()));
    expect(called, isFalse);
  });

  test('heartbeat 404 is non-fatal', () async {
    final api = YabosenApi(
      apiKey: 'k',
      client: MockClient((request) async {
        expect(jsonDecode(request.body), {'source': 'mobile'});
        return json({'error': 'No status data found'}, 404);
      }),
    );
    final response = await api.sendHeartbeat();
    expect(response.statusMissing, isTrue);
  });

  test('fetchStatus asks for debug info and parses it', () async {
    final api = YabosenApi(
      client: MockClient((request) async {
        expect(request.url.queryParameters['debug'], '1');
        return json({
          'status': 'idle',
          'updatedAt': 1,
          '_debug': {'storedStatus': 'dnd'},
        });
      }),
    );
    final status = await api.fetchStatus();
    expect(status.isIdleOverride, isTrue);
  });

  test('avatar upload builds a data URL and enforces the size limit', () async {
    late Map<String, dynamic> body;
    final api = YabosenApi(
      apiKey: 'k',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return json({'success': true, 'size': '1KB'});
      }),
    );
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    expect(YabosenApi.sniffImageMimeType(png), 'image/png');
    expect(await api.uploadAvatar(png, mimeType: 'image/png'), '1KB');
    expect(body['avatar'], 'data:image/png;base64,${base64Encode(png)}');

    final tooBig = Uint8List(YabosenApi.maxAvatarBytes + 1);
    await expectLater(
      api.uploadAvatar(tooBig, mimeType: 'image/jpeg'),
      throwsA(isA<ApiException>()),
    );
  });

  test('sleep schedule validation happens client side', () async {
    final api = YabosenApi(
      apiKey: 'k',
      client: MockClient((_) async => json({'success': true})),
    );
    await expectLater(
      api.saveSleepSchedule(
        const SleepSchedule(
          enabled: true,
          sleepyTime: '25:00',
          wakeyTime: '07:00',
        ),
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
