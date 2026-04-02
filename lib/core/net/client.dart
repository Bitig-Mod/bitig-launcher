import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../../features/auth/ms_auth.dart' show MsAuth;

class HttpClient {
  static Future<http.Response> get(String path) async {
    if (AppConfig.offlineMode) {
      return http.Response('{"error":"offline_mode","path":"$path"}', 503);
    }
    final headers = await _hAuth();
    final uri = _u(path);
    final res = await _retry(() => http.get(uri, headers: headers).timeout(AppConfig.apiTimeout));
    if (res.statusCode == 401) {
      final retried = await _tryRefreshAndRetry(() async {
        final fut = http.get(uri, headers: await _hAuth());
        return fut.timeout(AppConfig.apiTimeout);
      });
      return retried ?? res;
    }
    return res;
  }

  static Uri _u(String path) => Uri.parse('${AppConfig.baseUrl}$path');
  static Future<Map<String, String>> _hAuth() async {
    final base = {'Content-Type': 'application/json', 'Accept': 'application/json', 'User-Agent': 'Bitig-Launcher/1.0'};
    final token = MsAuth.appAccessToken;
    if (token != null && token.isNotEmpty) {
      return {...base, 'Authorization': 'Bearer $token'};
    }
    return base;
  }

  static Future<T> _retry<T>(Future<T> Function() f) async {
    for (int attempt = 0; attempt < AppConfig.maxRetries; attempt++) {
      try {
        return await f();
      } catch (e) {
        if (attempt == AppConfig.maxRetries - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
    throw Exception('network');
  }

  static Future<http.Response?> _tryRefreshAndRetry(Future<http.Response> Function() retrier) async {
    try {
      final ok = await MsAuth.trySilentSignIn();
      if (!ok) return null;
      return await retrier();
    } catch (_) {
      return null;
    }
  }
}
