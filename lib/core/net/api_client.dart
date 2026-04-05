import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'errors.dart';
import '../../features/auth/ms_auth.dart' show MsAuth;

class ApiClient {
  static ApiClient? _instance;
  static ApiClient get instance => _instance ??= ApiClient._();

  ApiClient._();

  static const Duration _timeout = AppConfig.apiTimeout;
  static const int _maxRetries = AppConfig.maxRetries;

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? headers,
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    return _makeRequest<T>(
      () async => http.get(
        Uri.parse('${AppConfig.baseUrl}$path'),
        headers: await _buildHeaders(headers),
      ),
      fromJson: fromJson,
    );
  }

  Future<Map<String, String>> _buildHeaders(Map<String, String>? additionalHeaders) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Bitig-Launcher/1.0',
      ...?additionalHeaders,
    };

    final token = MsAuth.appAccessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<ApiResponse<T>> _makeRequest<T>(
    Future<http.Response> Function() request, {
    T Function(Map<String, dynamic>)? fromJson,
  }) async {
    if (AppConfig.offlineMode) {
      return ApiResponse.failure(
        ApiError.network('Offline mode: backend is disabled'),
        0,
      );
    }

    int attempts = 0;
    Exception? lastException;

    while (attempts < _maxRetries) {
      try {
        var response = await request().timeout(_timeout);
        if (response.statusCode == 401) {
          final ok = await MsAuth.trySilentSignIn();
          if (ok) {
            response = await request().timeout(_timeout);
          }
        }
        return _handleResponse<T>(response, fromJson: fromJson);
      } on SocketException catch (e) {
        lastException = e;
        attempts++;
        if (attempts < _maxRetries) {
          await Future.delayed(Duration(milliseconds: 1000 * attempts));
          continue;
        }
      } on HttpException catch (e) {
        lastException = e;
        attempts++;
        if (attempts < _maxRetries) {
          await Future.delayed(Duration(milliseconds: 1000 * attempts));
          continue;
        }
      } catch (e) {
        return ApiResponse.failure(ApiError.unknown(e.toString()), 500);
      }
    }

    return ApiResponse.failure(ApiError.network(lastException?.toString() ?? 'Network error'), 0);
  }

  ApiResponse<T> _handleResponse<T>(
    http.Response response, {
    T Function(Map<String, dynamic>)? fromJson,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        if (response.body.isEmpty) {
          return ApiResponse.success(null as T, response.statusCode);
        }

        final data = json.decode(response.body);

        if (fromJson != null && data is Map<String, dynamic>) {
          return ApiResponse.success(fromJson(data), response.statusCode);
        }

        return ApiResponse.success(data as T, response.statusCode);
      } catch (e) {
        return ApiResponse.failure(ApiError.parse(e.toString()), response.statusCode);
      }
    } else if (response.statusCode == 401) {
      return ApiResponse.failure(ApiError.unauthorized('Unauthorized'), response.statusCode);
    } else if (response.statusCode == 403) {
      return ApiResponse.failure(ApiError.forbidden('Forbidden'), response.statusCode);
    } else if (response.statusCode == 404) {
      return ApiResponse.failure(ApiError.notFound('Not Found'), response.statusCode);
    } else if (response.statusCode >= 500) {
      return ApiResponse.failure(ApiError.server('Server Error'), response.statusCode);
    } else {
      return ApiResponse.failure(ApiError.http(response.statusCode, 'HTTP Error'), response.statusCode);
    }
  }
}
