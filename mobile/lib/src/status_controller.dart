import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

/// Fetches the live status and polls it while the app is in the foreground.
class StatusController extends ChangeNotifier {
  StatusController(this.api);

  static const Duration pollInterval = Duration(seconds: 15);

  final YabosenApi api;

  LiveStatus? _status;
  String? _error;
  bool _loading = false;
  int _avatarVersion = DateTime.now().millisecondsSinceEpoch;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _disposed = false;

  LiveStatus? get status => _status;

  /// Message of the last failed refresh, cleared on the next success.
  String? get error => _error;

  bool get loading => _loading;

  /// Changes whenever the avatar should be re-downloaded.
  int get avatarVersion => _avatarVersion;

  /// Fetches the status. Concurrent calls share one request.
  Future<void> refresh({bool reloadAvatar = false}) {
    if (reloadAvatar) bumpAvatar();
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    _loading = true;
    notifyListeners();
    try {
      _status = await api.fetchStatus();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Posts a new status, then refreshes. Throws [ApiException] on failure.
  Future<void> setStatus(StatusUpdate update) async {
    await api.setStatus(update);
    await refresh();
  }

  void bumpAvatar() {
    _avatarVersion = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// Refreshes now and then every [pollInterval] until [stopPolling].
  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    refresh();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
