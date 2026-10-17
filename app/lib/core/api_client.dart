import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'offline.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3100/api/v1',
);

/// Error with a user-facing message extracted from the API's `{success:false, error:{message}}` body.
class ApiException implements Exception {
  ApiException(this.message, {this.offline = false, this.code});
  final String message;

  /// The server's error code, e.g. LICENSE_REVOKED, when it sent one.
  final String? code;

  /// The server could not be reached at all (no connection, timeout), as opposed to answering with an error.
  final bool offline;

  factory ApiException.from(Object error, [StackTrace? stack]) {
    if (error is ApiException) return error;
    // A message already written for the user (cubits keep their errors as text).
    if (error is String && error.trim().isNotEmpty) return ApiException(error);
    // Checks the app makes itself (file formats, import rows) carry a message written for the user.
    if (error is FormatException && error.message.isNotEmpty) return ApiException(error.message);
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final msg = data['error']['message'];
        final code = data['error']['code']?.toString();
        if (msg is List && msg.isNotEmpty) return ApiException(msg.first.toString(), code: code);
        if (msg != null && msg.toString().isNotEmpty) return ApiException(msg.toString(), code: code);
      }
      if (error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.sendTimeout ||
          (error.type == DioExceptionType.unknown && error.response == null)) {
        return ApiException('Cannot reach the server. Check your internet connection.', offline: true);
      }
      if (error.type == DioExceptionType.receiveTimeout) return ApiException('The server took too long to answer. Please try again.');
      // The server (or something in front of it) answered, but not with our error format.
      final status = error.response?.statusCode;
      if (status != null) {
        return ApiException(switch (status) {
          401 => 'Your session has expired. Please sign in again.',
          403 => 'You do not have permission to do that.',
          404 => 'That could not be found. It may have been deleted.',
          413 => 'That file or request is too large.',
          429 => 'Too many requests. Please wait a moment and try again.',
          >= 500 => 'The server had a problem (error $status). Please try again in a moment.',
          _ => 'The server could not accept that request (error $status).',
        });
      }
    }
    // A bug, not something the user did: say so, keep the cause visible in the console, and name it so it can be reported.
    debugPrint('Unexpected ${error.runtimeType}: $error${stack == null ? '' : '\n$stack'}');
    return ApiException('Something went wrong (${error.runtimeType}). Please try again; if it keeps happening, report this message.');
  }

  @override
  String toString() => message;
}

/// Persists the JWT between app launches.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'access_token';

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  Future<void> clear() => _storage.delete(key: _key);
}

/// A save made without a connection was kept on this device and will be sent when the connection is back.
class QueuedOffline extends ApiException {
  QueuedOffline(this.label) : super('No connection: $label is saved on this device and will be sent when you are back online.');
  final String label;
}

/// Thin Dio wrapper: attaches the bearer token and converts every failure into [ApiException].
class ApiClient {
  ApiClient(this.tokens, {this.cache, this.queue})
      : _dio = Dio(BaseOptions(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await tokens.read();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
  }

  final TokenStore tokens;
  final Dio _dio;

  /// Offline support, when switched on: the last answer to each read, and saves waiting to be sent.
  final ResponseCache? cache;
  final SyncQueue? queue;

  final _online = StreamController<bool>.broadcast();
  bool isOnline = true;

  /// Emits whenever the server becomes reachable or unreachable.
  Stream<bool> get onlineChanges => _online.stream;

  void _setOnline(bool v) {
    if (isOnline == v) return;
    isOnline = v;
    _online.add(v);
  }

  /// The company the current login is for; caches and queued saves are kept apart per company.
  Future<String> scope() async => scopeOfToken(await tokens.read()) ?? '';

  Future<T> _send<T>(Future<Response<dynamic>> Function() call) async {
    try {
      return (await call()).data as T;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) async {
    try {
      final data = (await _dio.get(path, queryParameters: query)).data;
      _setOnline(true);
      final c = cache;
      if (c != null) unawaited(scope().then((s) => c.put(s, path, query, data)));
      return data as T;
    } catch (e) {
      final ex = ApiException.from(e);
      if (ex.offline) {
        _setOnline(false);
        final cached = cache?.get(await scope(), path, query);
        // Older answers are better than an error page; the app says it is offline.
        if (cached != null) return cached as T;
      }
      throw ex;
    }
  }
  Future<T> post<T>(String path, [Object? body]) => _send(() => _dio.post(path, data: body));

  /// A save that can wait: sent with a key that makes it apply only once; if there is no connection it is kept on this
  /// device and sent later, and [QueuedOffline] is thrown so the screen can say so.
  Future<T> postQueueable<T>(String path, Object body, {required String label, String? numberPath, Map<String, dynamic>? numberQuery, String? number}) async {
    final key = newIdempotencyKey();
    try {
      final r = await _dio.post(path, data: body, options: Options(headers: {'Idempotency-Key': key}));
      _setOnline(true);
      return r.data as T;
    } catch (e) {
      final ex = ApiException.from(e);
      final q = queue;
      if (!ex.offline || q == null) throw ex;
      _setOnline(false);
      final s = await scope();
      await q.add(PendingSave(id: key, scope: s, method: 'POST', path: path, body: body, label: label, createdAt: DateTime.now()));
      if (numberPath != null && number != null) await cache?.bumpNumber(s, numberPath, numberQuery, number);
      throw QueuedOffline(label);
    }
  }

  /// Sends one waiting save again, with the key it was first sent with.
  Future<void> replay(PendingSave p) async {
    try {
      await _dio.request<dynamic>(p.path, data: p.body, options: Options(method: p.method, headers: {'Idempotency-Key': p.id}));
      _setOnline(true);
    } catch (e) {
      final ex = ApiException.from(e);
      if (ex.offline) _setOnline(false);
      throw ex;
    }
  }
  Future<T> patch<T>(String path, [Object? body]) => _send(() => _dio.patch(path, data: body));
  Future<T> put<T>(String path, [Object? body]) => _send(() => _dio.put(path, data: body));
  Future<void> delete(String path) => _send<dynamic>(() => _dio.delete(path));
  Future<void> deleteWithBody(String path, Object body) => _send<dynamic>(() => _dio.delete(path, data: body));
}
