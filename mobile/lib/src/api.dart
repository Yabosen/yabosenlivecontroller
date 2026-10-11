import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Error raised for any failed API call, with a message fit for a snackbar.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  /// Builds an exception from a non-2xx response and its (optional) JSON body.
  factory ApiException.fromResponse(
    int statusCode,
    Map<String, dynamic>? body,
  ) {
    final serverError = body?['error'];
    final details = body?['details'];
    if (statusCode == 401) {
      return ApiException(
        'Invalid API key (401). Check it in Settings.',
        statusCode: statusCode,
      );
    }
    final buffer = StringBuffer(
      serverError is String && serverError.isNotEmpty
          ? serverError
          : 'Server error',
    );
    if (details is String && details.isNotEmpty) buffer.write(': $details');
    buffer.write(' ($statusCode)');
    return ApiException(buffer.toString(), statusCode: statusCode);
  }

  final String message;

  /// HTTP status code, or `null` for network/client-side errors.
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Client for the yabosen.live status API.
class YabosenApi {
  YabosenApi({http.Client? client, Uri? baseUri, this.apiKey})
    : _client = client ?? http.Client(),
      baseUri = baseUri ?? defaultBaseUri;

  static final Uri defaultBaseUri = Uri.parse('https://yabosen.live');
  static const Duration timeout = Duration(seconds: 10);

  /// Server-side limit for the decoded avatar image.
  static const int maxAvatarBytes = 500 * 1024;

  final http.Client _client;
  final Uri baseUri;

  /// The STATUS_API_KEY used for authenticated calls.
  String? apiKey;

  bool get hasApiKey => apiKey?.isNotEmpty ?? false;

  // ---------------------------------------------------------------- status

  /// `debug=1` makes the server also report the stored status, so the UI can
  /// explain when it is showing "idle" only because the PC heartbeat is stale.
  Future<LiveStatus> fetchStatus() async => LiveStatus.fromJson(
    await _getJson('/api/status', query: const {'debug': '1'}),
  );

  Future<void> setStatus(StatusUpdate update) async {
    await _postJson('/api/status', update.toJson());
  }

  // ------------------------------------------------------------- heartbeat

  /// Sends a mobile heartbeat. A 404 ("No status data found") is reported via
  /// [HeartbeatResponse.statusMissing] rather than thrown.
  Future<HeartbeatResponse> sendHeartbeat() async {
    try {
      final json = await _postJson('/api/heartbeat', {'source': 'mobile'});
      final updatedAt = json['updatedAt'];
      return HeartbeatResponse(
        updatedAt: updatedAt is num
            ? DateTime.fromMillisecondsSinceEpoch(updatedAt.toInt())
            : null,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return const HeartbeatResponse(statusMissing: true);
      }
      rethrow;
    }
  }

  // -------------------------------------------------------- sleep schedule

  Future<SleepSchedule> fetchSleepSchedule() async =>
      SleepSchedule.fromJson(await _getJson('/api/sleep-schedule'));

  Future<void> saveSleepSchedule(SleepSchedule schedule) async {
    if (!schedule.isValid) {
      throw const ApiException('Times must be in HH:mm (24h) format.');
    }
    await _postJson('/api/sleep-schedule', schedule.toJson());
  }

  // ---------------------------------------------------------------- avatar

  /// URL of the current avatar image. Pass a changing [version] to bypass the
  /// HTTP and in-memory image caches after an upload or manual refresh.
  Uri avatarUri({int? version}) => baseUri.replace(
    path: '/api/avatar',
    queryParameters: version == null ? null : {'v': '$version'},
  );

  /// Uploads [bytes] as the new avatar. Returns the size reported by the
  /// server (e.g. "143KB").
  Future<String> uploadAvatar(
    Uint8List bytes, {
    required String mimeType,
  }) async {
    if (!_avatarMimeTypes.contains(mimeType)) {
      throw ApiException('Unsupported image type ($mimeType).');
    }
    if (bytes.length > maxAvatarBytes) {
      throw ApiException(
        'Image is ${(bytes.length / 1024).round()} KB; the limit is 500 KB.',
      );
    }
    final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
    final json = await _postJson('/api/avatar', {'avatar': dataUrl});
    final size = json['size'];
    return size is String ? size : '${(bytes.length / 1024).round()}KB';
  }

  static const _avatarMimeTypes = {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
  };

  /// Maps a file name to one of the MIME types the server accepts, or `null`.
  static String? avatarMimeTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => null,
    };
  }

  /// Detects the image type from its leading "magic" bytes, or `null`.
  static String? sniffImageMimeType(Uint8List bytes) {
    bool startsWith(List<int> sig, [int offset = 0]) {
      if (bytes.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (bytes[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    return null;
  }

  void close() => _client.close();

  // --------------------------------------------------------------- plumbing

  Uri _uri(String path, {Map<String, String>? query}) =>
      baseUri.replace(path: path, queryParameters: query);

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
  }) => _send(
    () => _client.get(
      _uri(path, query: query),
      headers: const {'Accept': 'application/json'},
    ),
  );

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final key = apiKey;
    if (key == null || key.isEmpty) {
      throw const ApiException('No API key set. Add it in Settings.');
    }
    return _send(
      () => _client.post(
        _uri(path),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException('Request timed out. Check your connection.');
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on IOException catch (e) {
      throw ApiException('Network error: $e');
    }

    final body = _decodeJsonObject(response);
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) throw ApiException.fromResponse(response.statusCode, body);
    if (body == null) {
      throw ApiException(
        'Unexpected response from server (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  static Map<String, dynamic>? _decodeJsonObject(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
