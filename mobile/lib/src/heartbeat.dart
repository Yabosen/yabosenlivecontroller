import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';
import 'settings.dart';

/// How often the background service pings `/api/heartbeat`. The server treats
/// a source as stale after 3 minutes, so 60 s tolerates a missed beat or two.
const Duration heartbeatInterval = Duration(seconds: 60);

const int _serviceId = 4207;
const String _beatNowCommand = 'beat-now';

// ------------------------------------------------------------ task isolate

/// Entry point of the heartbeat isolate. Must stay top-level and annotated so
/// it survives tree shaking and can be started by the service after a reboot.
@pragma('vm:entry-point')
void heartbeatTaskCallback() {
  FlutterForegroundTask.setTaskHandler(HeartbeatTaskHandler());
}

/// Runs inside the foreground service's isolate: sends one heartbeat on start
/// and then every [heartbeatInterval], reports each result to the UI and keeps
/// the notification text current.
class HeartbeatTaskHandler extends TaskHandler {
  final YabosenApi _api = YabosenApi();
  bool _inFlight = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    unawaited(_beat());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_beat());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _api.close();
  }

  @override
  void onReceiveData(Object data) {
    if (data == _beatNowCommand) unawaited(_beat());
  }

  Future<void> _beat() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      // Re-read every time so a key changed in the UI is picked up.
      _api.apiKey = await AppSettings.getApiKey();
      final result = await performHeartbeat(_api);
      await AppSettings.setLastHeartbeat(result);
      FlutterForegroundTask.sendDataToMain(result.toMap());
      await FlutterForegroundTask.updateService(
        notificationText: heartbeatNotificationText(result),
      );
    } catch (e, st) {
      debugPrint('Heartbeat task error: $e\n$st');
    } finally {
      _inFlight = false;
    }
  }
}

/// Sends a single heartbeat and turns the outcome into a [HeartbeatResult].
Future<HeartbeatResult> performHeartbeat(YabosenApi api) async {
  if (!api.hasApiKey) return HeartbeatResult.failure('No API key set');
  try {
    final response = await api.sendHeartbeat();
    return HeartbeatResult.success(
      response.statusMissing ? 'OK (no status set on the site yet)' : 'OK',
    );
  } on ApiException catch (e) {
    return HeartbeatResult.failure(e.message);
  }
}

/// "Heartbeat active · last ok 14:03"
String heartbeatNotificationText(HeartbeatResult result) =>
    'Heartbeat active · last ${result.ok ? 'ok' : 'failed'} '
    '${formatHm(result.at)}';

// ------------------------------------------------------------- UI isolate

/// Configures and starts/stops the foreground service (UI isolate only).
abstract final class HeartbeatService {
  /// Must be called once in `main()` before [start].
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'heartbeat',
        channelName: 'Status heartbeat',
        channelDescription: 'Shown while the background heartbeat keeps your live status fresh.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          heartbeatInterval.inMilliseconds,
        ),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowAutoRestart: true,
      ),
    );
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static Future<ServiceRequestResult> start() async {
    if (await isRunning) return const ServiceRequestSuccess();
    // serviceTypes is left null so the type declared in the manifest
    // (specialUse) is used.
    return FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'Yabosen Controller',
      notificationText: 'Heartbeat starting…',
      notificationInitialRoute: '/',
      callback: heartbeatTaskCallback,
    );
  }

  static Future<ServiceRequestResult> stop() async {
    if (!await isRunning) return const ServiceRequestSuccess();
    return FlutterForegroundTask.stopService();
  }

  /// Asks the running task to send a heartbeat immediately.
  static void beatNow() =>
      FlutterForegroundTask.sendDataToTask(_beatNowCommand);
}

/// UI-facing state of the heartbeat: toggle, running flag and last result.
class HeartbeatController extends ChangeNotifier {
  HeartbeatController() {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  bool? _storedEnabled;
  bool _enabled = false;
  bool _running = false;
  bool _busy = false;
  HeartbeatResult? _last;
  bool _disposed = false;

  /// Whether the user wants the heartbeat (defaults to on once a key exists).
  bool get enabled => _enabled;
  bool get running => _running;
  bool get busy => _busy;
  HeartbeatResult? get lastResult => _last;

  bool shouldRun({required bool hasKey}) => _enabled && hasKey;

  Future<void> load({required bool hasKey}) async {
    _storedEnabled = await AppSettings.getHeartbeatEnabled();
    _enabled = _storedEnabled ?? hasKey;
    _last = await AppSettings.getLastHeartbeat();
    _running = await HeartbeatService.isRunning;
    notifyListeners();
  }

  /// Re-reads the running flag and last result (e.g. when the app resumes).
  Future<void> refresh() async {
    _running = await HeartbeatService.isRunning;
    _last = await AppSettings.getLastHeartbeat() ?? _last;
    notifyListeners();
  }

  /// Call after the API key was saved or cleared.
  void onApiKeyChanged({required bool hasKey}) {
    _enabled = _storedEnabled ?? hasKey;
    notifyListeners();
  }

  Future<String?> setEnabled(bool enabled, {required bool hasKey}) async {
    _enabled = enabled;
    _storedEnabled = enabled;
    notifyListeners();
    await AppSettings.setHeartbeatEnabled(enabled);
    return apply(hasKey: hasKey);
  }

  /// Starts or stops the service to match the toggle. Returns an error
  /// message, or `null` on success.
  Future<String?> apply({required bool hasKey}) async {
    final run = shouldRun(hasKey: hasKey);
    _busy = true;
    notifyListeners();
    try {
      final result = run
          ? await HeartbeatService.start()
          : await HeartbeatService.stop();
      _running = await HeartbeatService.isRunning;
      return switch (result) {
        ServiceRequestSuccess() => null,
        ServiceRequestFailure(:final error) =>
          'Could not ${run ? 'start' : 'stop'} the heartbeat: $error',
      };
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Sends a heartbeat now: via the service when it runs, else directly.
  Future<void> beatNow(YabosenApi api) async {
    if (_running) {
      HeartbeatService.beatNow();
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await performHeartbeat(api);
      await AppSettings.setLastHeartbeat(result);
      _last = result;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _onTaskData(Object data) {
    final result = HeartbeatResult.tryFromMap(data);
    if (result == null) return;
    _last = result;
    _running = true;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }
}
