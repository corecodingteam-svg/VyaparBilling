import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3100/api/v1',
);

/// Error with a user-facing message extracted from the API's `{success:false, error:{message}}` body.
class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  factory ApiException.from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final msg = data['error']['message'];
        if (msg is List && msg.isNotEmpty) return ApiException(msg.first.toString());
        if (msg != null) return ApiException(msg.toString());
      }
      if (error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout) {
        return ApiException('Cannot reach the server. Check your internet connection.');
      }
    }
    return ApiException('Something went wrong. Please try again.');
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

/// Thin Dio wrapper: attaches the bearer token and converts every failure into [ApiException].
class ApiClient {
  ApiClient(this.tokens)
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

  Future<T> _send<T>(Future<Response<dynamic>> Function() call) async {
    try {
      return (await call()).data as T;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) => _send(() => _dio.get(path, queryParameters: query));
  Future<T> post<T>(String path, [Object? body]) => _send(() => _dio.post(path, data: body));
  Future<T> patch<T>(String path, [Object? body]) => _send(() => _dio.patch(path, data: body));
  Future<T> put<T>(String path, [Object? body]) => _send(() => _dio.put(path, data: body));
  Future<void> delete(String path) => _send<dynamic>(() => _dio.delete(path));
  Future<void> deleteWithBody(String path, Object body) => _send<dynamic>(() => _dio.delete(path, data: body));
}
