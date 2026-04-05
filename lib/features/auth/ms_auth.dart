import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/entities.dart';
import 'ms_auth_web.dart' show launchPopupAndWaitWeb;
import '../../core/config/app_config.dart';
import '../../core/net/api_client.dart';
import '../../core/logging/logger.dart';

class MsAuth {
  static const _logger = TaggedLogger('MsAuth');

  static const String _clientId = 'b96118f1-662d-4eb6-8c11-fb133027eae1';

  static const String _tokenUrl = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';

  static const String _scope = 'XboxLive.signin XboxLive.offline_access';

  static const String _xblUrl = 'https://user.auth.xboxlive.com/user/authenticate';
  static const String _xstsUrl = 'https://xsts.auth.xboxlive.com/xsts/authorize';
  static const String _mcLoginUrl = 'https://api.minecraftservices.com/launcher/login';
  static const String _mcProfileUrl = 'https://api.minecraftservices.com/minecraft/profile';
  static const String _mcEntitlementsUrl = 'https://api.minecraftservices.com/entitlements/license';

  static const _ua = 'bitig-launcher/1.0 (+flutter)';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );

  static Future<void> _launchUrl(Uri url) async {
    if (kIsWeb) {
      final urlString = url.toString();
      _logger.debug('WEB: Launching URL in popup: $urlString');
    } else {
      if (Platform.isWindows) {
        await Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', url.toString()]);
      } else {
        _logger.debug('PLATFORM: Would launch URL: $url');
      }
    }
  }

  static String? _mcAccessToken;
  static DateTime? _mcExp;
  static String? _appAccessToken;

  static Future<MsAuthResult> interactiveSignIn() async {
    _assertClientId();
    await _clearTransientState();

    if (kIsWeb) {
      final backend = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1) : AppConfig.baseUrl;
      final redirectUri = '$backend/auth/callback';
      final expectedOrigin = Uri.parse(redirectUri).origin;

      final verifier = _codeVerifier();
      final challenge = _codeChallenge(verifier);
      final state = 'st_${DateTime.now().millisecondsSinceEpoch}';

      final authUrl = Uri.https(
        'login.microsoftonline.com',
        '/consumers/oauth2/v2.0/authorize',
        {
          'client_id': _clientId,
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'response_mode': 'query',
          'scope': _scope,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
        },
      );

      final code = await launchPopupAndWaitWeb(
        authUrl,
        expectedState: state,
        expectedOrigin: expectedOrigin,
      );
      if (code == null || code.isEmpty) {
        throw Exception('User cancelled or no code received.');
      }

      final token = await _exchangeAuthCodeForTokens(
        code: code,
        redirectUri: redirectUri,
        verifier: verifier,
      );

      final resp = await _postWithMsToken('/auth/mc/web-exchange', token.accessToken);
      if (resp.statusCode != 200) {
        throw Exception('Web exchange failed: ${resp.statusCode} ${resp.body}');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      _appAccessToken = data['accessToken'] as String?;
      if (_appAccessToken == null || _appAccessToken!.isEmpty) {
        throw Exception('Invalid backend access token');
      }

      return token;
    }

    if (Platform.isWindows) {
      return await _interactiveSignInWindows();
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://localhost:${server.port}';

    final verifier = _codeVerifier();
    final challenge = _codeChallenge(verifier);
    final state = 'st_${DateTime.now().millisecondsSinceEpoch}';

    final authUrl = Uri.https(
      'login.microsoftonline.com',
      '/consumers/oauth2/v2.0/authorize',
      {
        'client_id': _clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'response_mode': 'query',
        'scope': _scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'prompt': 'select_account',
      },
    );

    await _launchUrl(authUrl);

    final req = await server.first;
    final uri = req.requestedUri;

    if (uri.path.isNotEmpty && uri.path != '/' && uri.path != '/callback') {
      throw Exception('Unexpected path: ${uri.path}');
    }

    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('<html><body style="font-family:sans-serif">Sign-in complete. You can close this window.</body></html>');
    await req.response.close();
    await server.close(force: true);

    if (uri.queryParameters['error'] != null) {
      throw Exception('Auth error: ${uri.queryParameters['error_description'] ?? uri.queryParameters['error']}');
    }
    if (uri.queryParameters['state'] != state) {
      throw Exception('STATE_MISMATCH');
    }
    final code = uri.queryParameters['code'];
    if (code == null) {
      throw Exception('Missing authorization code.');
    }

    final token = await _exchangeAuthCodeForTokens(code: code, redirectUri: redirectUri, verifier: verifier);

    await _mintMinecraftToken(token.accessToken);

    await exchangeWithBackend(_mcAccessToken!);

    return token;
  }

  static Future<bool> trySilentSignIn() async {
    _assertClientId();

    if (kIsWeb) {
      return false;
    }

    if (Platform.isWindows) {
      return await _trySilentSignInWindows();
    }

    final rt = await _storage.read(key: 'ms_refresh');
    if (rt == null || rt.length < 64) return false;

    try {
      await refreshSilently(rt);
      if (_mcAccessToken != null) {
        await exchangeWithBackend(_mcAccessToken!);
      }
      return true;
    } on MsAuthRefreshRevokedException {
      await _storage.delete(key: 'ms_refresh');
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<MsAuthResult> refreshSilently(String refreshToken) async {
    final body = {'client_id': _clientId, 'grant_type': 'refresh_token', 'refresh_token': refreshToken, 'scope': _scope};

    final res = await _postForm(_tokenUrl, body);
    if (res.statusCode != 200) {
      if (res.body.isNotEmpty) {
        try {
          final err = jsonDecode(res.body);
          if (err is Map && err['error'] == 'invalid_grant') {
            throw MsAuthRefreshRevokedException();
          }
        } catch (e) {
          if (e is MsAuthRefreshRevokedException) rethrow;
        }
      }
      if (res.statusCode >= 500 || res.statusCode == 408 || res.statusCode == 429) {
        throw MsAuthTransientException('Token refresh ${res.statusCode}');
      }
      throw Exception('Token refresh failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String;
    final newRefreshToken = (data['refresh_token'] as String?) ?? refreshToken;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

    await _storage.write(key: 'ms_refresh', value: newRefreshToken);

    await _mintMinecraftToken(accessToken);

    return MsAuthResult(accessToken: accessToken, refreshToken: newRefreshToken, expiresIn: expiresIn);
  }

  static Future<Map<String, dynamic>> getMcProfile() async {
    if (kIsWeb) {
      if (_appAccessToken == null || _appAccessToken!.isEmpty) {
        throw Exception('No app access token; user needs to sign in.');
      }
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/auth/me',
        fromJson: (json) => json,
      );
      if (!res.isSuccess || res.data == null) {
        final msg = res.error?.message ?? 'request failed';
        throw Exception('auth/me ${res.statusCode}: $msg');
      }
      return res.data!;
    } else {
      await _ensureMcFresh();
      _logger.debug('GET $_mcProfileUrl');
      final r = await http
          .get(Uri.parse(_mcProfileUrl), headers: {'Authorization': 'Bearer $_mcAccessToken', 'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(AppConfig.apiTimeout);
      if (r.statusCode != 200) {
        _logger.error('Profile request failed: ${r.statusCode} ${r.body}');
        throw Exception('profile ${r.statusCode}: ${r.body}');
      }
      return json.decode(r.body) as Map<String, dynamic>;
    }
  }

  static Future<bool> hasMinecraftOwnership() async {
    await _ensureMcFresh();
    final reqId = _uuidV4();
    final url = '$_mcEntitlementsUrl?requestId=$reqId';
    _logger.debug('GET $url');
    final r = await http
        .get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $_mcAccessToken', 'User-Agent': _ua, 'Accept': 'application/json'},
        )
        .timeout(AppConfig.apiTimeout);
    if (r.statusCode != 200) {
      _logger.error('Entitlements request failed: ${r.statusCode} ${r.body}');
      throw Exception('entitlements ${r.statusCode}: ${r.body}');
    }
    final data = json.decode(r.body) as Map<String, dynamic>;
    final items = (data['items'] as List?) ?? const [];
    bool hasGame = items.any((i) => (i is Map && (i['name'] as String?)?.toLowerCase() == 'game_minecraft'));
    bool hasProduct = items.any((i) => (i is Map && (i['name'] as String?)?.toLowerCase() == 'product_minecraft'));
    return hasGame && hasProduct;
  }

  static Future<void> signOut() async {
    _mcAccessToken = null;
    _mcExp = null;
    _appAccessToken = null;
    await _storage.delete(key: 'ms_refresh');
    await _storage.delete(key: 'app_refresh');
  }

  static String? get mcAccessToken => _mcAccessToken;
  static String? get appAccessToken => _appAccessToken;

  static Future<AppTokens> exchangeWithBackend(String mcAccessToken) async {
    if (AppConfig.offlineMode) {
      _appAccessToken = 'offline';
      return AppTokens(accessToken: 'offline', refreshToken: null);
    }
    final r = await _postWithMcToken('/auth/mc/exchange', mcAccessToken);
    if (r.statusCode != 200) {
      throw Exception('Exchange failed: ${r.statusCode} ${r.body}');
    }
    final data = json.decode(r.body) as Map<String, dynamic>;
    final access = data['accessToken'] as String;
    final refresh = data['refreshToken'] as String?;

    if (refresh != null) {
      await _storage.write(key: 'app_refresh', value: refresh);
    }
    _appAccessToken = access;
    return AppTokens(accessToken: access, refreshToken: refresh);
  }

  static void _assertClientId() {
    if (_clientId == 'YOUR-APP-CLIENT-ID-HERE' || _clientId.trim().isEmpty) {
      throw Exception('Set your approved Microsoft App (client) ID in MsAuth._clientId.');
    }
  }

  static Future<void> _clearTransientState() async {
    _mcAccessToken = null;
    _mcExp = null;
    _appAccessToken = null;
  }

  static String _codeVerifier() {
    final r = Random.secure();
    final bytes = List<int>.generate(64, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _codeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static Future<MsAuthResult> _exchangeAuthCodeForTokens({required String code, required String redirectUri, required String verifier}) async {
    final body = {
      'client_id': _clientId,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
      'scope': _scope,
    };

    final res = await _postForm(_tokenUrl, body);
    if (res.statusCode != 200) {
      throw Exception('Token exchange failed: ${res.statusCode} ${res.body}');
    }

    final tok = jsonDecode(res.body) as Map<String, dynamic>;
    final msAccess = tok['access_token'] as String;
    final msRefresh = tok['refresh_token'] as String? ?? '';
    final expiresIn = (tok['expires_in'] as num?)?.toInt() ?? 3600;

    if (msRefresh.isNotEmpty) {
      await _storage.write(key: 'ms_refresh', value: msRefresh);
    }

    return MsAuthResult(accessToken: msAccess, refreshToken: msRefresh, expiresIn: expiresIn);
  }

  static Future<void> _ensureMcFresh() async {
    final needsMint = _mcAccessToken == null || _mcExp == null || DateTime.now().isAfter(_mcExp!.subtract(const Duration(minutes: 5)));

    if (needsMint) {
      final rt = await _storage.read(key: 'ms_refresh');
      if (rt != null) {
        await refreshSilently(rt);
      } else {
        throw Exception('No refresh token available; user needs to sign in.');
      }
    }
  }

  static Future<void> _mintMinecraftToken(String msAccessToken) async {
    final xblRes = await _postJson(_xblUrl, {
      'Properties': {'AuthMethod': 'RPS', 'SiteName': 'user.auth.xboxlive.com', 'RpsTicket': 'd=$msAccessToken'},
      'RelyingParty': 'http://auth.xboxlive.com',
      'TokenType': 'JWT',
    });
    if (xblRes.statusCode != 200) {
      throw Exception('XBL auth failed: ${xblRes.statusCode} ${xblRes.body}');
    }
    final xbl = json.decode(xblRes.body) as Map<String, dynamic>;
    final xblToken = xbl['Token'] as String;
    final uhs = ((xbl['DisplayClaims'] as Map)['xui'] as List).first['uhs'] as String;

    final xstsRes = await _postJson(_xstsUrl, {
      'Properties': {
        'SandboxId': 'RETAIL',
        'UserTokens': [xblToken],
      },
      'RelyingParty': 'rp://api.minecraftservices.com/',
      'TokenType': 'JWT',
    });
    if (xstsRes.statusCode != 200) {
      throw Exception('XSTS failed: ${xstsRes.statusCode} ${xstsRes.body}');
    }
    final xsts = json.decode(xstsRes.body) as Map<String, dynamic>;
    final xstsToken = xsts['Token'] as String;

    final mcRes = await _postJson(_mcLoginUrl, {'xtoken': 'XBL3.0 x=$uhs;$xstsToken', 'platform': 'PC_LAUNCHER'});
    if (mcRes.statusCode != 200) {
      throw Exception('MC login failed: ${mcRes.statusCode} ${mcRes.body}');
    }
    final mc = json.decode(mcRes.body) as Map<String, dynamic>;
    _mcAccessToken = mc['access_token'] as String;
    final expiresIn = (mc['expires_in'] as num?)?.toInt() ?? (24 * 3600);
    _mcExp = DateTime.now().add(Duration(seconds: expiresIn));
  }

  static Future<http.Response> _postForm(String url, Map<String, String> body, {int attempts = 3}) async {
    return _retry(
      () => http
          .post(Uri.parse(url), headers: {'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': _ua}, body: body)
          .timeout(AppConfig.apiTimeout),
      attempts: attempts,
    );
  }

  static Future<http.Response> _postJson(String url, Map<String, dynamic> jsonBody, {int attempts = 3}) async {
    return _retry(
      () => http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'User-Agent': _ua},
            body: json.encode(jsonBody),
          )
          .timeout(AppConfig.apiTimeout),
      attempts: attempts,
    );
  }

  static Future<http.Response> _retry(Future<http.Response> Function() send, {int attempts = 3}) async {
    http.Response? last;
    for (int i = 0; i < attempts; i++) {
      try {
        final res = await send();
        if (res.statusCode == 408 || res.statusCode == 429 || (res.statusCode >= 500 && res.statusCode <= 599)) {
          last = res;
          await _sleepBackoff(i);
          continue;
        }
        return res;
      } on SocketException catch (e) {
        if (kDebugMode) {
          _logger.debug('HTTP retry due to network error: $e');
        }
        await _sleepBackoff(i);
      } on HttpException catch (e) {
        if (kDebugMode) {
          _logger.debug('HTTP retry due to http error: $e');
        }
        await _sleepBackoff(i);
      } on TimeoutException catch (e) {
        if (kDebugMode) {
          _logger.debug('HTTP retry due to timeout: $e');
        }
        await _sleepBackoff(i);
      }
    }
    if (last != null) return last;
    throw Exception('HTTP request failed after $attempts attempts.');
  }

  static Future<void> _sleepBackoff(int attempt) async {
    final base = pow(2, attempt).toInt();
    final jitterMs = 200 + Random.secure().nextInt(400);
    await Future.delayed(Duration(milliseconds: base * jitterMs));
  }

  static String _uuidV4() {
    final r = Random.secure();
    int next(int bits) => r.nextInt(1 << bits);
    final bytes = List<int>.generate(16, (_) => next(8));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String b(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    return '${b(0)}${b(1)}${b(2)}${b(3)}-'
        '${b(4)}${b(5)}-'
        '${b(6)}${b(7)}-'
        '${b(8)}${b(9)}-'
        '${b(10)}${b(11)}${b(12)}${b(13)}${b(14)}${b(15)}';
  }

  static Future<http.Response> _postWithMsToken(String path, String msToken) async {
    if (AppConfig.offlineMode) {
      return http.Response('{"error":"offline_mode","path":"$path"}', 503);
    }
    return http.post(
      Uri.parse('${AppConfig.baseUrl}$path'),
      headers: {'Authorization': 'Bearer $msToken', 'User-Agent': _ua},
    );
  }

  static Future<http.Response> _postWithMcToken(String path, String mcToken) async {
    if (AppConfig.offlineMode) {
      return http.Response('{"error":"offline_mode","path":"$path"}', 503);
    }
    return http.post(
      Uri.parse('${AppConfig.baseUrl}$path'),
      headers: {'Authorization': 'Bearer $mcToken', 'X-Client-Platform': 'desktop'},
    );
  }

  static User? _currentUser;

  static Future<User?> getLastUser() async {
    return _currentUser;
  }

  static Future<User?> getCurrentUser() async {
    if (_currentUser != null) return _currentUser;

    try {
      final profile = await getMcProfile();

      final Map<String, dynamic> root = profile;
      final Map<String, dynamic> userMap = (root['user'] is Map<String, dynamic>) ? (root['user'] as Map<String, dynamic>) : root;

      final String uuid = (userMap['mcUuid'] as String?) ?? (userMap['id'] as String?) ?? '';
      final String? name = (userMap['mcName'] as String?) ?? (userMap['name'] as String?);

      _currentUser = User(id: (name != null && name.isNotEmpty) ? name : uuid, uuid: uuid, username: name);
      return _currentUser;
    } catch (e) {
      if (e.toString().contains('profile 404')) {
        try {
          final owned = await hasMinecraftOwnership();
          if (!owned) {
            _logger.error('getCurrentUser failed: no Minecraft ownership (entitlements missing)');
          } else {
            _logger.error('getCurrentUser failed: Minecraft profile not found (likely no Java profile name created yet)');
          }
        } catch (ee) {
          _logger.error('getCurrentUser failed: profile 404; entitlement check also failed: $ee');
        }
      } else {
        _logger.error('getCurrentUser failed: $e');
      }
      return null;
    }
  }

  static Future<MsAuthResult> _interactiveSignInWindows() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://localhost:${server.port}';

    final verifier = _codeVerifier();
    final challenge = _codeChallenge(verifier);
    final state = 'st_${DateTime.now().millisecondsSinceEpoch}';

    final authUrl = Uri.https(
      'login.microsoftonline.com',
      '/consumers/oauth2/v2.0/authorize',
      {
        'client_id': _clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'response_mode': 'query',
        'scope': _scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'prompt': 'select_account',
      },
    );

    try {
      await _launchUrl(authUrl);
    } catch (e) {
      throw Exception('Failed to launch authentication URL: $e');
    }

    try {
      final req = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw Exception('Authentication timeout - please try again');
        },
      );
      final uri = req.requestedUri;

      if (uri.path.isNotEmpty && uri.path != '/' && uri.path != '/callback') {
        throw Exception('Unexpected path: ${uri.path}');
      }

      final q = uri.queryParameters;
      if (q['error'] != null) {
        throw Exception('Auth error: ${q['error']} ${q['error_description'] ?? ''}');
      }

      final code = q['code'];
      final recvState = q['state'] ?? '';
      if (code == null || code.isEmpty) {
        throw Exception('No authorization code received');
      }
      if (recvState != state) {
        throw Exception('State mismatch');
      }

      req.response
        ..statusCode = 200
        ..headers.set('Content-Type', 'text/html; charset=utf-8')
        ..write('''
<!DOCTYPE html>
<html>
<head><title>Success</title></head>
<body>
<h1>Success!</h1>
<p>You can close this window and return to the app.</p>
<script>window.close();</script>
</body>
</html>
        ''');
      await req.response.close();

      final tokenResult = await _exchangeAuthCodeForTokens(code: code, redirectUri: redirectUri, verifier: verifier);

      if (tokenResult.refreshToken.isNotEmpty) {
        await _storage.write(key: 'ms_refresh', value: tokenResult.refreshToken);
      }

      await _mintMinecraftToken(tokenResult.accessToken);

      await exchangeWithBackend(_mcAccessToken!);

      return tokenResult;
    } catch (e) {
      rethrow;
    } finally {
      await server.close();
    }
  }

  static Future<bool> _trySilentSignInWindows() async {
    final rt = await _storage.read(key: 'ms_refresh');
    if (rt == null || rt.length < 64) return false;

    try {
      await refreshSilently(rt);
      if (_mcAccessToken != null) {
        await exchangeWithBackend(_mcAccessToken!);
      }
      return true;
    } on MsAuthRefreshRevokedException {
      await _storage.delete(key: 'ms_refresh');
      return false;
    } catch (_) {
      return false;
    }
  }
}

class MsAuthRefreshRevokedException implements Exception {}

class MsAuthTransientException implements Exception {
  final String message;
  MsAuthTransientException(this.message);
}

class MsAuthResult {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  MsAuthResult({required this.accessToken, required this.refreshToken, required this.expiresIn});
}

class AppTokens {
  final String accessToken;
  final String? refreshToken;

  AppTokens({required this.accessToken, this.refreshToken});
}
