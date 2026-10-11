import 'package:flutter_test/flutter_test.dart';
import 'package:yabosen_controller/src/format.dart';
import 'package:yabosen_controller/src/models.dart';
import 'package:yabosen_controller/src/settings.dart';

void main() {
  group('LiveStatus', () {
    test('parses the server payload', () {
      final status = LiveStatus.fromJson({
        'status': 'dnd',
        'customMessage': 'busy',
        'activityType': 'playing',
        'activityName': 'CS2',
        'episodeInfo': null,
        'seasonInfo': null,
        'updatedAt': 1760000000000,
        'startedAt': 1759990000000,
      });
      expect(status.status, StatusKind.dnd);
      expect(status.customMessage, 'busy');
      expect(status.headline, 'Playing CS2');
      expect(status.updatedAt.millisecondsSinceEpoch, 1760000000000);
      expect(status.startedAt, isNotNull);
      expect(status.isIdleOverride, isFalse);
    });

    test('builds activity aware labels', () {
      LiveStatus make(String status, String? type, {String? s, String? e}) =>
          LiveStatus.fromJson({
            'status': status,
            'activityType': type,
            'activityName': 'X',
            'seasonInfo': s,
            'episodeInfo': e,
            'updatedAt': 0,
          });
      expect(make('streaming', 'playing').headline, 'Streaming X');
      expect(
        make('online', 'watching', s: 'S1', e: '3').headline,
        'Watching X (S1 Ep 3)',
      );
      expect(make('online', 'watching').headline, 'Watching X');
      expect(make('online', 'listening').headline, 'Listening to X');
      expect(make('idle', null).headline, 'Idle');
      expect(make('streaming', null).headline, 'Streaming');
    });

    test('detects the idle override from debug info', () {
      final status = LiveStatus.fromJson({
        'status': 'idle',
        'updatedAt': 0,
        '_debug': {'storedStatus': 'online', 'pcAlive': false},
      });
      expect(status.isIdleOverride, isTrue);
      expect(status.storedStatus, StatusKind.online);
    });

    test('falls back safely on unknown values', () {
      final status = LiveStatus.fromJson({'status': 'weird', 'updatedAt': 'x'});
      expect(status.status, StatusKind.offline);
      expect(status.activity, ActivityKind.none);
    });
  });

  group('StatusUpdate', () {
    test('omits empty fields and activity when none', () {
      const update = StatusUpdate(
        status: StatusKind.online,
        customMessage: '  ',
        activityName: 'ignored',
      );
      expect(update.toJson(), {'status': 'online'});
    });

    test('serialises watching with normalised season/episode', () {
      const update = StatusUpdate(
        status: StatusKind.streaming,
        customMessage: 'hi',
        activity: ActivityKind.watching,
        activityName: ' Frieren ',
        seasonInfo: '2',
        episodeInfo: 'Ep 7',
      );
      expect(update.toJson(), {
        'status': 'streaming',
        'customMessage': 'hi',
        'activityType': 'watching',
        'activityName': 'Frieren',
        'seasonInfo': 'S2',
        'episodeInfo': '7',
      });
    });

    test('drops season/episode for playing', () {
      const update = StatusUpdate(
        status: StatusKind.online,
        activity: ActivityKind.playing,
        activityName: 'CS2',
        seasonInfo: '1',
      );
      expect(update.toJson(), {
        'status': 'online',
        'activityType': 'playing',
        'activityName': 'CS2',
      });
    });

    test('season helpers round-trip', () {
      expect(StatusUpdate.normalizeSeason('Part 2'), 'Part 2');
      expect(StatusUpdate.seasonForEditing('S12'), '12');
      expect(StatusUpdate.seasonForEditing('Part 2'), 'Part 2');
    });
  });

  group('SleepSchedule', () {
    test('validates HH:mm', () {
      expect(SleepSchedule.isValidTime('23:59'), isTrue);
      expect(SleepSchedule.isValidTime('24:00'), isFalse);
      expect(SleepSchedule.isValidTime('7:00'), isFalse);
      expect(SleepSchedule.formatTime(7, 5), '07:05');
    });

    test('parses with defaults and compares by value', () {
      final schedule = SleepSchedule.fromJson({
        'enabled': true,
        'sleepyTime': 'bad',
      });
      expect(schedule.enabled, isTrue);
      expect(schedule.sleepyTime, '23:00');
      expect(schedule.wakeyTime, '07:00');
      expect(schedule, SleepSchedule.defaults.copyWith(enabled: true));
    });
  });

  group('HeartbeatResult', () {
    test('round-trips through an untyped map', () {
      final result = HeartbeatResult.failure('boom');
      final copy = HeartbeatResult.tryFromMap(
        Map<dynamic, dynamic>.from(result.toMap()),
      );
      expect(copy?.ok, isFalse);
      expect(copy?.message, 'boom');
      expect(copy?.at.millisecondsSinceEpoch, result.at.millisecondsSinceEpoch);
      expect(HeartbeatResult.tryFromMap('nope'), isNull);
    });
  });

  group('format', () {
    test('Bucharest wall clock follows EU DST', () {
      // 11 Oct 2026 12:00 UTC -> EEST (UTC+3)
      expect(
        formatHm(bucharestWallClock(DateTime.utc(2026, 10, 11, 12))),
        '15:00',
      );
      // 25 Oct 2026 is the last Sunday of October; after 01:00 UTC -> UTC+2
      expect(
        formatHm(bucharestWallClock(DateTime.utc(2026, 10, 25, 2))),
        '04:00',
      );
      expect(
        formatHm(bucharestWallClock(DateTime.utc(2026, 10, 25, 0, 30))),
        '03:30',
      );
      // January -> EET (UTC+2)
      expect(
        formatHm(bucharestWallClock(DateTime.utc(2026, 1, 10, 22, 15))),
        '00:15',
      );
    });

    test('timestamps and ages', () {
      final now = DateTime(2026, 10, 11, 14, 3, 22);
      expect(formatTimestamp(now, now: now), '14:03:22');
      expect(
        formatTimestamp(DateTime(2026, 10, 9, 8, 5), now: now),
        '9 Oct 08:05',
      );
      expect(
        formatAgo(now.subtract(const Duration(seconds: 10)), now: now),
        'just now',
      );
      expect(
        formatAgo(now.subtract(const Duration(minutes: 5)), now: now),
        '5 min ago',
      );
    });
  });

  test('maskApiKey hides the middle', () {
    expect(maskApiKey('abcdefghijklmnop'), 'ab••••••op');
    expect(maskApiKey('abcdef'), '••••••ef');
    expect(maskApiKey('abc'), '•••');
  });
}
