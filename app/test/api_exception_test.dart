import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/core/api_client.dart';

DioException dio(int status, Object? body) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: status, data: body),
      type: DioExceptionType.badResponse,
    );

void main() {
  test('server validation messages are shown as written', () {
    expect(ApiException.from(dio(400, {'success': false, 'error': {'code': 'BADREQUEST', 'message': ['name must be a string', 'x']}})).message, 'name must be a string');
    expect(ApiException.from(dio(409, {'success': false, 'error': {'code': 'CONFLICT', 'message': 'Already exists.'}})).message, 'Already exists.');
  });

  test("the app's own file and import checks keep their message", () {
    expect(ApiException.from(const FormatException('GST Rate 7% is not a valid GST slab')).message, 'GST Rate 7% is not a valid GST slab');
  });

  test('answers in another format are explained by status, not "something went wrong"', () {
    expect(ApiException.from(dio(413, '<html>too big</html>')).message, contains('too large'));
    expect(ApiException.from(dio(429, 'slow down')).message, contains('Too many requests'));
    expect(ApiException.from(dio(502, '<html>bad gateway</html>')).message, contains('502'));
    expect(ApiException.from(dio(401, null)).message, contains('sign in'));
  });

  test('no connection is reported as offline', () {
    final e = ApiException.from(DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError));
    expect(e.offline, isTrue);
  });

  test('a program error is named so it can be reported', () {
    expect(ApiException.from(TypeError()).message, contains('TypeError'));
  });

  test('a message that is already text is shown as written', () {
    expect(ApiException.from('Select a customer.').message, 'Select a customer.');
  });
}
