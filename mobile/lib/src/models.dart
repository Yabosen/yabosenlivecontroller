/// Plain data models shared by the UI and the background heartbeat isolate.
///
/// This file is pure Dart on purpose (no Flutter imports) so it can be used
/// from any isolate and unit-tested without a widget binding.
library;

/// The status values accepted by `POST /api/status`.
enum StatusKind {
  online('online', 'Online', 'Online'),
  offline('offline', 'Offline', 'Offline'),
  dnd('dnd', 'DND', 'Do Not Disturb'),
  idle('idle', 'Idle', 'Idle'),
  sleeping('sleeping', 'Sleeping', 'Sleeping'),
  streaming('streaming', 'Streaming', 'Streaming');

  const StatusKind(this.apiValue, this.shortLabel, this.label);

  /// Value used on the wire.
  final String apiValue;

  /// Compact label for buttons.
  final String shortLabel;

  /// Full human readable label.
  final String label;

  static StatusKind? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final kind in values) {
      if (kind.apiValue == normalized) return kind;
    }
    return null;
  }
}

/// The activity types the website understands. [none] is sent as "omitted".
enum ActivityKind {
  none(null, 'None'),
  playing('playing', 'Playing'),
  watching('watching', 'Watching'),
  listening('listening', 'Listening');

  const ActivityKind(this.apiValue, this.label);

  final String? apiValue;
  final String label;

  static ActivityKind parse(Object? value) {
    if (value is! String) return none;
    final normalized = value.trim().toLowerCase();
    for (final kind in values) {
      if (kind.apiValue == normalized) return kind;
    }
    return none;
  }
}

/// Response of `GET /api/status`.
class LiveStatus {
  const LiveStatus({
    required this.status,
    required this.updatedAt,
    this.customMessage,
    this.activity = ActivityKind.none,
    this.activityName,
    this.episodeInfo,
    this.seasonInfo,
    this.startedAt,
    this.storedStatus,
  });

  factory LiveStatus.fromJson(Map<String, dynamic> json) {
    // Optional block returned for `?debug=1`; used only to explain an idle
    // override, so everything in it is treated as best-effort.
    final debug = json['_debug'];
    return LiveStatus(
      status: StatusKind.tryParse(json['status']) ?? StatusKind.offline,
      customMessage: _nonEmpty(json['customMessage']),
      activity: ActivityKind.parse(json['activityType']),
      activityName: _nonEmpty(json['activityName']),
      episodeInfo: _nonEmpty(json['episodeInfo']),
      seasonInfo: _nonEmpty(json['seasonInfo']),
      updatedAt: _dateFromMillis(json['updatedAt']) ?? DateTime.now(),
      startedAt: _dateFromMillis(json['startedAt']),
      storedStatus: debug is Map
          ? StatusKind.tryParse(debug['storedStatus'])
          : null,
    );
  }

  final StatusKind status;
  final String? customMessage;
  final ActivityKind activity;
  final String? activityName;
  final String? episodeInfo;
  final String? seasonInfo;

  /// Local time of the last server-side update.
  final DateTime updatedAt;

  /// Local time the current status/activity started, when known.
  final DateTime? startedAt;

  /// The status actually stored on the server, when the server reported it.
  final StatusKind? storedStatus;

  /// True when the site shows "idle" only because the PC heartbeat is stale,
  /// while the stored status is something else.
  bool get isIdleOverride =>
      status == StatusKind.idle &&
      storedStatus != null &&
      storedStatus != StatusKind.idle;

  /// Activity aware description, mirroring the website wording, e.g.
  /// "Playing CS2", "Watching Frieren (S1 Ep 3)", "Listening to X".
  /// Returns `null` when there is no activity to describe.
  String? get activityText {
    final name = activityName;
    if (name == null) return null;
    switch (activity) {
      case ActivityKind.playing:
        return status == StatusKind.streaming
            ? 'Streaming $name'
            : 'Playing $name';
      case ActivityKind.watching:
        final extras = [
          ?seasonInfo,
          if (episodeInfo != null) 'Ep $episodeInfo',
        ];
        return extras.isEmpty
            ? 'Watching $name'
            : 'Watching $name (${extras.join(' ')})';
      case ActivityKind.listening:
        return 'Listening to $name';
      case ActivityKind.none:
        return null;
    }
  }

  /// Primary label for the status card: the activity if any, else the status.
  String get headline => activityText ?? status.label;
}

/// Body of `POST /api/status`.
class StatusUpdate {
  const StatusUpdate({
    required this.status,
    this.customMessage,
    this.activity = ActivityKind.none,
    this.activityName,
    this.seasonInfo,
    this.episodeInfo,
  });

  final StatusKind status;
  final String? customMessage;
  final ActivityKind activity;
  final String? activityName;
  final String? seasonInfo;
  final String? episodeInfo;

  Map<String, Object?> toJson() {
    final message = _nonEmpty(customMessage);
    final name = _nonEmpty(activityName);
    final hasActivity = activity != ActivityKind.none && name != null;
    final watching = hasActivity && activity == ActivityKind.watching;
    final season = watching ? normalizeSeason(seasonInfo) : null;
    final episode = watching ? normalizeEpisode(episodeInfo) : null;
    return {
      'status': status.apiValue,
      'customMessage': ?message,
      if (hasActivity) ...{
        'activityType': activity.apiValue,
        'activityName': name,
        'seasonInfo': ?season,
        'episodeInfo': ?episode,
      },
    };
  }

  /// "1" -> "S1"; anything else (e.g. "S2", "Part 2") is kept as typed.
  static String? normalizeSeason(String? raw) {
    final value = _nonEmpty(raw);
    if (value == null) return null;
    return RegExp(r'^\d+$').hasMatch(value) ? 'S$value' : value;
  }

  /// The website renders `Ep {value}`, so strip a typed "Ep"/"E" prefix.
  static String? normalizeEpisode(String? raw) {
    final value = _nonEmpty(raw);
    if (value == null) return null;
    final stripped = value
        .replaceFirst(
          RegExp(r'^(episode|ep\.?|e)\s*', caseSensitive: false),
          '',
        )
        .trim();
    return stripped.isEmpty ? null : stripped;
  }

  /// Reverse of [normalizeSeason], for pre-filling the edit field: "S1" -> "1".
  static String? seasonForEditing(String? stored) {
    final value = _nonEmpty(stored);
    if (value == null) return null;
    final match = RegExp(r'^[sS](\d+)$').firstMatch(value);
    return match?.group(1) ?? value;
  }
}

/// Body/response of `/api/sleep-schedule`. Times are "HH:mm" in
/// Europe/Bucharest local time.
class SleepSchedule {
  const SleepSchedule({
    required this.enabled,
    required this.sleepyTime,
    required this.wakeyTime,
  });

  factory SleepSchedule.fromJson(Map<String, dynamic> json) {
    String time(Object? value, String fallback) =>
        value is String && isValidTime(value) ? value : fallback;
    return SleepSchedule(
      enabled: json['enabled'] == true,
      sleepyTime: time(json['sleepyTime'], defaults.sleepyTime),
      wakeyTime: time(json['wakeyTime'], defaults.wakeyTime),
    );
  }

  /// Same defaults the server returns when nothing is stored.
  static const defaults = SleepSchedule(
    enabled: false,
    sleepyTime: '23:00',
    wakeyTime: '07:00',
  );

  static final RegExp timePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  static bool isValidTime(String value) => timePattern.hasMatch(value);

  /// Formats hour/minute as zero-padded "HH:mm".
  static String formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  final bool enabled;
  final String sleepyTime;
  final String wakeyTime;

  bool get isValid => isValidTime(sleepyTime) && isValidTime(wakeyTime);

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'sleepyTime': sleepyTime,
    'wakeyTime': wakeyTime,
  };

  SleepSchedule copyWith({
    bool? enabled,
    String? sleepyTime,
    String? wakeyTime,
  }) {
    return SleepSchedule(
      enabled: enabled ?? this.enabled,
      sleepyTime: sleepyTime ?? this.sleepyTime,
      wakeyTime: wakeyTime ?? this.wakeyTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SleepSchedule &&
      other.enabled == enabled &&
      other.sleepyTime == sleepyTime &&
      other.wakeyTime == wakeyTime;

  @override
  int get hashCode => Object.hash(enabled, sleepyTime, wakeyTime);
}

/// Response of `POST /api/heartbeat`.
class HeartbeatResponse {
  const HeartbeatResponse({this.updatedAt, this.statusMissing = false});

  /// Server timestamp of the beat, when the server returned one.
  final DateTime? updatedAt;

  /// The server answered 404 "No status data found". The beat itself is still
  /// recorded server-side, so this is not treated as a failure.
  final bool statusMissing;
}

/// Outcome of one heartbeat attempt. Persisted and sent between isolates, so
/// it serialises to a plain map of primitives.
class HeartbeatResult {
  const HeartbeatResult({
    required this.at,
    required this.ok,
    required this.message,
  });

  factory HeartbeatResult.success(String message) =>
      HeartbeatResult(at: DateTime.now(), ok: true, message: message);

  factory HeartbeatResult.failure(String message) =>
      HeartbeatResult(at: DateTime.now(), ok: false, message: message);

  /// Parses a map produced by [toMap]. Accepts untyped maps because messages
  /// crossing isolate groups lose their generic type arguments.
  static HeartbeatResult? tryFromMap(Object? data) {
    if (data is! Map) return null;
    final at = data['at'];
    final ok = data['ok'];
    final message = data['message'];
    if (at is! int || ok is! bool || message is! String) return null;
    return HeartbeatResult(
      at: DateTime.fromMillisecondsSinceEpoch(at),
      ok: ok,
      message: message,
    );
  }

  /// Tag used to recognise heartbeat messages coming from the task isolate.
  static const String messageType = 'heartbeat';

  final DateTime at;
  final bool ok;
  final String message;

  Map<String, Object> toMap() => {
    'type': messageType,
    'at': at.millisecondsSinceEpoch,
    'ok': ok,
    'message': message,
  };
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _dateFromMillis(Object? value) =>
    value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;
