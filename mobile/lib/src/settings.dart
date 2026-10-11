import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// Persistent settings shared by the UI and the heartbeat isolate.
///
/// Uses [SharedPreferencesAsync], which has no in-memory cache and always reads
/// through to the platform store, so a value written by one isolate is seen by
/// the other on its next read.
abstract final class AppSettings {
  static const _kApiKey = 'api_key';
  static const _kHeartbeatEnabled = 'heartbeat_enabled';
  static const _kLastHeartbeat = 'last_heartbeat';
  static const _kBatteryPromptShown = 'battery_prompt_shown';

  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static Future<String?> getApiKey() async {
    final value = await _prefs.getString(_kApiKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> setApiKey(String key) =>
      _prefs.setString(_kApiKey, key.trim());

  static Future<void> clearApiKey() => _prefs.remove(_kApiKey);

  /// `null` means the user never touched the toggle (treated as "on" once an
  /// API key exists).
  static Future<bool?> getHeartbeatEnabled() =>
      _prefs.getBool(_kHeartbeatEnabled);

  static Future<void> setHeartbeatEnabled(bool enabled) =>
      _prefs.setBool(_kHeartbeatEnabled, enabled);

  static Future<HeartbeatResult?> getLastHeartbeat() async {
    final raw = await _prefs.getString(_kLastHeartbeat);
    if (raw == null) return null;
    try {
      return HeartbeatResult.tryFromMap(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  static Future<void> setLastHeartbeat(HeartbeatResult result) =>
      _prefs.setString(_kLastHeartbeat, jsonEncode(result.toMap()));

  static Future<bool> getBatteryPromptShown() async =>
      await _prefs.getBool(_kBatteryPromptShown) ?? false;

  static Future<void> setBatteryPromptShown() =>
      _prefs.setBool(_kBatteryPromptShown, true);
}

/// Masked preview of an API key, e.g. "ab••••••yz".
String maskApiKey(String key) {
  const dots = '••••••';
  if (key.length <= 4) return '•' * key.length;
  final tail = key.substring(key.length - 2);
  if (key.length < 10) return '$dots$tail';
  return '${key.substring(0, 2)}$dots$tail';
}

/// Holds the API key for the UI isolate and keeps [api] in sync with it.
class ApiKeyController extends ChangeNotifier {
  ApiKeyController(this.api);

  final YabosenApi api;

  String? _key;
  bool _loaded = false;

  String? get key => _key;
  bool get hasKey => _key != null;
  bool get isLoaded => _loaded;
  String? get maskedKey => _key == null ? null : maskApiKey(_key!);

  Future<void> load() async {
    _apply(await AppSettings.getApiKey());
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return clear();
    await AppSettings.setApiKey(trimmed);
    _apply(trimmed);
    notifyListeners();
  }

  Future<void> clear() async {
    await AppSettings.clearApiKey();
    _apply(null);
    notifyListeners();
  }

  void _apply(String? key) {
    _key = key;
    api.apiKey = key;
  }
}
