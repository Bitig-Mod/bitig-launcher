import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../logging/logger.dart';
import '../../shared/platform_utils.dart';
import '../config/app_config.dart';
import '../fs/launcher_dirs.dart';

class LauncherCatalogConfig {
  final LauncherLinks launcher;
  final List<ModpackLinks> modpacks;

  const LauncherCatalogConfig({required this.launcher, required this.modpacks});

  static LauncherCatalogConfig? _cachedConfig;
  static Future<LauncherCatalogConfig?>? _inFlight;

  static Map<String, dynamic>? _decodePossiblyWrappedJson(String raw) {
    try {
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      try {
        final slice = raw.substring(start, end + 1);
        final data = jsonDecode(slice);
        return data is Map<String, dynamic> ? data : null;
      } catch (_) {
        return null;
      }
    }
  }

  static String? _httpsUrlOrNull(String s) {
    final u = Uri.tryParse(s.trim());
    if (u == null) return null;
    if (u.scheme != 'https') return null;
    if (u.userInfo.isNotEmpty) return null;
    if (u.host.isEmpty) return null;
    return u.toString();
  }

  static Future<LauncherCatalogConfig?> tryLoad({String fileName = 'config/launcher_catalog.json', bool forceRefresh = false}) async {
    if (!PlatformUtils.isDesktop) return null;
    if (!forceRefresh && _cachedConfig != null) return _cachedConfig;
    if (!forceRefresh && _inFlight != null) return _inFlight!;

    final future = _tryLoadInternal(fileName: fileName);
    _inFlight = future;
    final loaded = await future;
    _inFlight = null;
    if (loaded != null) _cachedConfig = loaded;
    return loaded;
  }

  static LauncherCatalogConfig? _configFromDecodedMap(Map<String, dynamic> data) {
    final launcherMap = data['launcher'];
    final modpacksJson = data['modpacks'];
    if (launcherMap is! Map || modpacksJson is! List) return null;
    final launcher = LauncherLinks.fromJson(launcherMap.cast<String, dynamic>());
    final modpacks =
        modpacksJson.whereType<Map>().map((e) => ModpackLinks.fromJson(e.cast<String, dynamic>())).toList();
    return LauncherCatalogConfig(launcher: launcher, modpacks: modpacks);
  }

  static Future<LauncherCatalogConfig?> _tryLoadFromFile(File f, String logLabel) async {
    if (!await f.exists()) return null;
    final raw = await f.readAsString();
    final decoded = _decodePossiblyWrappedJson(raw);
    if (decoded == null) return null;
    final cfg = _configFromDecodedMap(decoded);
    if (cfg != null) {
      Logger.info('Loaded launcher catalog from $logLabel', tag: 'LauncherCatalog');
    }
    return cfg;
  }

  static Future<LauncherCatalogConfig?> _tryLoadInternal({required String fileName}) async {
    try {
      final url = AppConfig.launcherCatalogUrl.trim();
      if (url.isNotEmpty) {
        final parsed = Uri.tryParse(url);
        if (parsed == null) {
          Logger.warning('launcherCatalogUrl is not a valid URL', tag: 'LauncherCatalog');
        } else if (parsed.scheme != 'https') {
          Logger.warning('launcherCatalogUrl must be https', tag: 'LauncherCatalog');
        } else {
          try {
            final res = await http.get(parsed).timeout(AppConfig.apiTimeout);
            if (res.statusCode == 200) {
              final raw = utf8.decode(res.bodyBytes, allowMalformed: true);
              final decoded = _decodePossiblyWrappedJson(raw);
              if (decoded != null) {
                final cfg = _configFromDecodedMap(decoded);
                if (cfg != null) {
                  Logger.info('Loaded launcher catalog from URL', tag: 'LauncherCatalog');
                  return cfg;
                }
                Logger.warning('launcherCatalogUrl response missing launcher map or modpacks list', tag: 'LauncherCatalog');
              } else {
                Logger.warning('launcherCatalogUrl body was not valid JSON', tag: 'LauncherCatalog');
              }
            } else {
              Logger.warning('launcherCatalogUrl returned ${res.statusCode}', tag: 'LauncherCatalog');
            }
          } catch (e) {
            Logger.warning('launcherCatalogUrl fetch failed: $e', tag: 'LauncherCatalog');
          }
        }
      }

      final dataRootPath = '${LauncherDirs.dataRoot().path}${Platform.pathSeparator}$fileName';
      final fromDataRoot = await _tryLoadFromFile(File(dataRootPath), 'data root $fileName');
      if (fromDataRoot != null) return fromDataRoot;

      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final fromExeDir = await _tryLoadFromFile(File('$exeDir${Platform.pathSeparator}$fileName'), 'executable directory $fileName');
      if (fromExeDir != null) return fromExeDir;

      final fromCwd = await _tryLoadFromFile(File(fileName), 'working directory $fileName');
      return fromCwd;
    } catch (e) {
      Logger.error('Failed to load $fileName: $e', tag: 'LauncherCatalog');
      return null;
    }
  }
}

class LauncherLinks {
  final String featuredVideoUrl;
  final String gameManifestUrl;
  final String forgePromotionsUrl;
  final String minecraftAssetUrl;
  final List<String> mavenRepositories;
  final String launcherVersion;
  final String launcherDownloadUrl;
  final Map<String, dynamic> javaRuntimes;

  const LauncherLinks({
    required this.featuredVideoUrl,
    required this.gameManifestUrl,
    required this.forgePromotionsUrl,
    required this.minecraftAssetUrl,
    required this.mavenRepositories,
    this.launcherVersion = '',
    this.launcherDownloadUrl = '',
    this.javaRuntimes = const {},
  });

  factory LauncherLinks.fromJson(Map<String, dynamic> json) {
    final featuredVideoUrl = (json['featuredVideoUrl'] as String?) ?? '';
    final gameManifestUrl = (json['gameManifestUrl'] as String?) ?? '';
    final forgePromotionsUrl = (json['forgePromotionsUrl'] as String?) ?? '';
    final minecraftAssetUrl = (json['minecraftAssetUrl'] as String?) ?? '';
    final launcherDownloadUrl = (json['launcherDownloadUrl'] as String?) ?? '';
    final javaRuntimes = (json['javaRuntimes'] is Map) ? (json['javaRuntimes'] as Map).cast<String, dynamic>() : const <String, dynamic>{};

    return LauncherLinks(
      featuredVideoUrl: LauncherCatalogConfig._httpsUrlOrNull(featuredVideoUrl) ?? '',
      gameManifestUrl: LauncherCatalogConfig._httpsUrlOrNull(gameManifestUrl) ?? '',
      forgePromotionsUrl: LauncherCatalogConfig._httpsUrlOrNull(forgePromotionsUrl) ?? '',
      minecraftAssetUrl: LauncherCatalogConfig._httpsUrlOrNull(minecraftAssetUrl) ?? '',
      mavenRepositories:
          (json['mavenRepositories'] as List?)
              ?.map((e) => e.toString())
              .map((e) => LauncherCatalogConfig._httpsUrlOrNull(e) ?? '')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      launcherVersion: (json['launcherVersion'] as String?) ?? '',
      launcherDownloadUrl: LauncherCatalogConfig._httpsUrlOrNull(launcherDownloadUrl) ?? '',
      javaRuntimes: javaRuntimes,
    );
  }
}

class ModpackLinks {
  final String name;
  final String mcVersion;
  final String forgeVersion;
  final String videoUrl;
  final String zipUrl;
  final String iconPng;
  final String modpackVersion;
  final String zipSha256;
  final bool live;

  const ModpackLinks({
    required this.name,
    required this.mcVersion,
    required this.forgeVersion,
    required this.videoUrl,
    required this.zipUrl,
    this.iconPng = '',
    this.modpackVersion = '',
    this.zipSha256 = '',
    this.live = false,
  });

  factory ModpackLinks.fromJson(Map<String, dynamic> json) {
    final liveVal = json['live'];
    final videoUrl = (json['videoUrl'] as String?) ?? '';
    final zipUrl = (json['zipUrl'] as String?) ?? '';
    final iconPng = (json['iconPng'] as String?) ?? '';
    final sha = (json['sha256'] as String?) ?? (json['zipSha256'] as String?) ?? '';
    return ModpackLinks(
      name: (json['name'] as String?) ?? '',
      mcVersion: (json['mcVersion'] as String?) ?? '',
      forgeVersion: (json['forgeVersion'] as String?) ?? '',
      videoUrl: LauncherCatalogConfig._httpsUrlOrNull(videoUrl) ?? '',
      zipUrl: LauncherCatalogConfig._httpsUrlOrNull(zipUrl) ?? '',
      iconPng: LauncherCatalogConfig._httpsUrlOrNull(iconPng) ?? '',
      modpackVersion: (json['modpackVersion'] as String?) ?? '',
      zipSha256: sha.trim(),
      live: liveVal == true || liveVal == 1 || (liveVal is String && liveVal.toLowerCase() == 'true'),
    );
  }
}
