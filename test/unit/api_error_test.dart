import 'package:flutter_test/flutter_test.dart';
import 'package:mc_ui/core/net/errors.dart';

void main() {
  group('ApiError', () {
    test('creates error with code and message', () {
      final error = ApiError(code: 'TEST_ERROR', message: 'Test message');

      expect(error.code, 'TEST_ERROR');
      expect(error.message, 'Test message');
      expect(error.traceId, isNull);
    });

    test('creates error from JSON', () {
      final json = {
        'code': 'VALIDATION_ERROR',
        'message': 'Invalid input',
        'traceId': 'trace-123',
      };

      final error = ApiError.fromJson(json);

      expect(error.code, 'VALIDATION_ERROR');
      expect(error.message, 'Invalid input');
      expect(error.traceId, 'trace-123');
    });

    test('handles missing fields in JSON gracefully', () {
      final json = <String, dynamic>{};

      final error = ApiError.fromJson(json);

      expect(error.code, 'ERROR');
      expect(error.message, 'Unexpected error');
      expect(error.traceId, isNull);
    });

    test('factory constructors create correct errors', () {
      expect(ApiError.unknown('msg').code, 'UNKNOWN');
      expect(ApiError.network('msg').code, 'NETWORK');
      expect(ApiError.parse('msg').code, 'PARSE');
      expect(ApiError.unauthorized('msg').code, 'UNAUTHORIZED');
      expect(ApiError.forbidden('msg').code, 'FORBIDDEN');
      expect(ApiError.notFound('msg').code, 'NOT_FOUND');
      expect(ApiError.server('msg').code, 'SERVER');
      expect(ApiError.http(404, 'msg').code, 'HTTP_404');
    });
  });

  group('ApiResponse', () {
    test('success response has correct properties', () {
      final response = ApiResponse.success('data', 200);

      expect(response.isSuccess, isTrue);
      expect(response.isError, isFalse);
      expect(response.data, 'data');
      expect(response.statusCode, 200);
      expect(response.error, isNull);
    });

    test('failure response has correct properties', () {
      final error = ApiError(code: 'ERROR', message: 'Failed');
      final response = ApiResponse.failure(error, 400);

      expect(response.isSuccess, isFalse);
      expect(response.isError, isTrue);
      expect(response.data, isNull);
      expect(response.statusCode, 400);
      expect(response.error, error);
    });
  });

  group('Result', () {
    test('ok result has correct properties', () {
      final result = Result.ok('value');

      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.value, 'value');
      expect(result.error, isNull);
    });

    test('error result has correct properties', () {
      final error = ApiError(code: 'ERROR', message: 'Failed');
      final result = Result.err(error);

      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.value, isNull);
      expect(result.error, error);
    });
  });
}
