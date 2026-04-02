class ApiError {
  final String code;
  final String message;
  final String? traceId;

  const ApiError({required this.code, required this.message, this.traceId});

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      code: (json['code'] as String?) ?? 'ERROR',
      message: (json['message'] as String?) ?? 'Unexpected error',
      traceId: json['traceId'] as String?,
    );
  }

  factory ApiError.unknown(String message) => ApiError(code: 'UNKNOWN', message: message);
  factory ApiError.network(String message) => ApiError(code: 'NETWORK', message: message);
  factory ApiError.parse(String message) => ApiError(code: 'PARSE', message: message);
  factory ApiError.unauthorized(String message) => ApiError(code: 'UNAUTHORIZED', message: message);
  factory ApiError.forbidden(String message) => ApiError(code: 'FORBIDDEN', message: message);
  factory ApiError.notFound(String message) => ApiError(code: 'NOT_FOUND', message: message);
  factory ApiError.server(String message) => ApiError(code: 'SERVER', message: message);
  factory ApiError.http(int statusCode, String message) => ApiError(code: 'HTTP_$statusCode', message: message);
}

class ApiResponse<T> {
  final T? data;
  final ApiError? error;
  final int statusCode;

  const ApiResponse._({this.data, this.error, required this.statusCode});

  bool get isSuccess => error == null && statusCode >= 200 && statusCode < 300;
  bool get isError => error != null || statusCode >= 400;

  static ApiResponse<T> success<T>(T data, int statusCode) => ApiResponse._(data: data, statusCode: statusCode);
  static ApiResponse<T> failure<T>(ApiError error, int statusCode) => ApiResponse._(error: error, statusCode: statusCode);
}

class Result<T> {
  final T? value;
  final ApiError? error;

  const Result._({this.value, this.error});

  bool get isOk => error == null;
  bool get isErr => error != null;

  static Result<T> ok<T>(T value) => Result._(value: value);
  static Result<T> err<T>(ApiError error) => Result._(error: error);
}
