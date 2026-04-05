import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:archive/archive_io.dart';
import '../../core/logging/logger.dart';
import '../../../core/net/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../core/settings/launcher_settings.dart';
import '../../core/java/java_detector.dart';
import '../../core/java/java_runtime_manager.dart';
import '../../core/java/mojang_java_runtime.dart';
import '../../core/fs/launcher_dirs.dart';
import '../../core/install/tasks.dart';
import 'launcher.dart';
import '../../core/local_config/launcher_catalog_config.dart';
import 'mc_downloads.dart' as mc;
import 'forge_install.dart' as forge;

class _ParsedJarName {
  final String artifact;
  final String version;
  _ParsedJarName({required this.artifact, required this.version});
}

class _JarEntry {
  final String artifact;
  final String version;
  final String path;
  _JarEntry({required this.artifact, required this.version, required this.path});
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

_ParsedJarName? _parseJarName(String filename) {
  if (!filename.endsWith('.jar')) return null;
  final base = filename.substring(0, filename.length - 4);
  final lastDash = base.lastIndexOf('-');
  if (lastDash <= 0) return null;
  final artifact = base.substring(0, lastDash);
  final verAndClassifier = base.substring(lastDash + 1);
  final version = verAndClassifier.split('-').first;
  if (!RegExp(r'^\d+(?:\.\d+)*').hasMatch(version)) return null;
  return _ParsedJarName(artifact: artifact, version: version);
}

int _compareVersions(String a, String b) {
  if (a == b) return 0;
  final as = a.split('.').map(int.tryParse).whereType<int>().toList();
  final bs = b.split('.').map(int.tryParse).whereType<int>().toList();
  final len = as.length > bs.length ? as.length : bs.length;
  for (var i = 0; i < len; i++) {
    final av = i < as.length ? as[i] : 0;
    final bv = i < bs.length ? bs[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

class GameInstaller {
  static const _logger = TaggedLogger('GameInstaller');
  static Launcher? _launcherConfig;
  static String _selectedMcVersion = '';
  static String _selectedForgeVersion = '';
  static String _selectedModpackName = '';
  static String _selectedModpackZipUrl = '';
  static String _selectedModpackVersion = '';
  static String _selectedModpackZipSha256 = '';

  static String _normalizeForgeVersion(String input) {
    final v = input.trim();
    if (v.isEmpty) return '';
    final m = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(v);
    return m?.group(1) ?? v;
  }

  static Future<void> loadLauncherConfig() async {
    try {
      if (AppConfig.offlineMode) {
        final cfg = await LauncherCatalogConfig.tryLoad();
        final l = cfg?.launcher;
        if (l == null) {
          _logger.debug('Offline mode: launcher catalog missing or invalid (launcher)');
          _launcherConfig = null;
          return;
        }
        _launcherConfig = Launcher(
          videoUrl: l.featuredVideoUrl,
          gameManifestUrl: l.gameManifestUrl,
          forgePromotionsUrl: l.forgePromotionsUrl,
          minecraftAssetUrl: l.minecraftAssetUrl,
          mavenRepositories: l.mavenRepositories,
          javaRuntimes: l.javaRuntimes,
        );
        return;
      }

      _logger.debug('DEBUG: Loading launcher config from backend...');
      final api = ApiClient.instance;
      final response = await api.get<Launcher>(
        '/launcher',
        fromJson: (json) => Launcher.fromJson(json),
      );

      if (response.isSuccess && response.data != null) {
        _launcherConfig = response.data;
        _logger.debug('DEBUG: Launcher config loaded: ${_launcherConfig?.toJson()}');
      } else {
        _logger.debug('Failed to load launcher config: ${response.error}');
        _launcherConfig = null;
      }
    } catch (e) {
      _logger.debug('Failed to load launcher config: $e');
      _launcherConfig = null;
    }
  }

  static Future<void> setSelectedModpack({
    required String name,
    required String mcVersion,
    required String forgeVersion,
    required String zipUrl,
    required String modpackVersion,
    String zipSha256 = '',
  }) async {
    _selectedModpackName = name.trim();
    _selectedMcVersion = mcVersion.trim();
    _selectedForgeVersion = _normalizeForgeVersion(forgeVersion);
    _selectedModpackZipUrl = zipUrl.trim();
    _selectedModpackVersion = modpackVersion.trim();
    _selectedModpackZipSha256 = zipSha256.trim().toLowerCase();
    if (_dataRoot != null) {
      _instanceRoot = Directory('${_dataRoot!.path}/instances/$_instanceSlug');
      await _instanceRoot!.create(recursive: true);
      await _modpacksDownloadsRoot.create(recursive: true);
    }
  }

  static String get minecraftVersion => _selectedMcVersion;
  static String get versionInfoUrl => _launcherConfig?.gameManifestUrl ?? '';
  static String get forgeVersion => _selectedForgeVersion;
  static String get forgeInstallerUrl => '';
  static String get forgePromotionsUrl => _launcherConfig?.forgePromotionsUrl ?? '';
  static String get minecraftAssetBaseUrl => _launcherConfig?.minecraftAssetUrl ?? '';
  static List<String> get mavenRepositories => _launcherConfig?.mavenRepositories ?? [];
  static Directory? _dataRoot;
  static Directory? _cacheRoot;
  static Directory? _instanceRoot;

  static String get _instanceSlug => _slugify(_selectedModpackName.isEmpty ? 'default' : _selectedModpackName);
  static Directory get _downloadsRoot => Directory('${_dataRoot!.path}/downloads');
  static Directory get _modpacksDownloadsRoot => Directory('${_downloadsRoot.path}/modpacks/$_instanceSlug');
  static Directory get _mojangRoot => _cacheRoot!;
  static Directory get _instanceDir => _instanceRoot!;

  static Future<void> ensureVersionData() async {
    if (_cacheRoot == null || _instanceRoot == null) await initialize();
    await downloadVersionManifest();
    await downloadVersionJson();
  }

  static Future<IntegrityResult> calculateIntegrity() async {
    await ensureVersionData();
    final result = IntegrityResult();

    final clientJar = File('${_mojangRoot.path}/versions/$minecraftVersion/$minecraftVersion.jar');
    result.total++;
    if (!await clientJar.exists()) {
      result.missing++;
      result.missingClientJar = true;
    }

    final versionData = await getVersionData();
    if (versionData == null) return result;

    final libraries = (versionData['libraries'] as List?) ?? [];
    result.total += _countLibraryFiles(libraries);
    final librariesDir = Directory('${_mojangRoot.path}/libraries');
    for (final library in libraries) {
      final downloads = library['downloads'];
      if (downloads != null && downloads['artifact'] != null) {
        final path = downloads['artifact']['path'];
        if (!await File('${librariesDir.path}/$path').exists()) {
          result.missing++;
          result.missingLibraries++;
        }
      }
      if (downloads != null && downloads['classifiers'] != null) {
        final classifiers = downloads['classifiers'];
        String? classifierKey;
        if (Platform.isWindows) {
          if (classifiers.containsKey('natives-windows-64')) {
            classifierKey = 'natives-windows-64';
          } else if (classifiers.containsKey('natives-windows')) {
            classifierKey = 'natives-windows';
          }
        } else if (Platform.isLinux) {
          classifierKey = 'natives-linux';
        } else if (Platform.isMacOS) {
          classifierKey = 'natives-osx';
        }
        if (classifierKey != null && classifiers[classifierKey] != null) {
          final path = classifiers[classifierKey]['path'];
          if (!await File('${librariesDir.path}/$path').exists()) {
            result.missing++;
            result.missingLibraries++;
          }
        }
      }
    }

    final assetIndex = versionData['assetIndex'];
    if (assetIndex != null) {
      final id = assetIndex['id'];
      final idxFile = File('${_mojangRoot.path}/assets/indexes/$id.json');
      if (await idxFile.exists()) {
        try {
          final idxData = jsonDecode(await idxFile.readAsString());
          final objects = (idxData['objects'] as Map<String, dynamic>);
          result.total += objects.length;
          for (final e in objects.entries) {
            final hash = e.value['hash'];
            final prefix = hash.substring(0, 2);
            final file = File('${_mojangRoot.path}/assets/objects/$prefix/$hash');
            if (!await file.exists()) {
              result.missing++;
              result.missingAssets++;
            }
          }
        } catch (_) {}
      } else {
        result.total++;
        result.missing++;
        result.missingAssetIndex = true;
      }
    }

    final requiresForge = forgeVersion.trim().isNotEmpty;
    if (requiresForge) {
      final versionsDir = Directory('${_mojangRoot.path}/versions/$minecraftVersion');
      bool forgeFound = false;
      if (await versionsDir.exists()) {
        for (final f in versionsDir.listSync()) {
          if (f is File && f.path.contains('forge') && f.path.endsWith('.jar')) {
            forgeFound = true;
            break;
          }
        }
      }
      result.total++;
      if (!forgeFound) {
        result.missing++;
        result.missingForgeJar = true;
      }
    }

    if (_selectedModpackZipUrl.trim().isNotEmpty) {
      result.total++;
      final marker = File('${_instanceDir.path}/.modpack_installed.json');
      final installing = File('${_instanceDir.path}/.modpack_installing.json');
      if (await installing.exists()) {
        result.missing++;
        result.missingModpack = true;
      } else
      if (!await marker.exists()) {
        result.missing++;
        result.missingModpack = true;
      } else if (_selectedModpackVersion.isNotEmpty) {
        try {
          final raw = await marker.readAsString();
          final data = jsonDecode(raw);
          final v = data is Map ? (data['modpackVersion'] as String?) : null;
          if ((v ?? '').trim() != _selectedModpackVersion) {
            result.missing++;
            result.missingModpack = true;
          }
        } catch (_) {
          result.missing++;
          result.missingModpack = true;
        }
      }
    }

    return result;
  }

  static Future<bool> installAll({required void Function(double, String) reportProgress}) async {
    if (_cacheRoot == null || _instanceRoot == null) await initialize();

    if (_launcherConfig == null) {
      await loadLauncherConfig();
    }

    final queue = TaskQueue();
    queue.add(FnTask('manifest', (p) async {
      p(0.0, 'Fetching version manifest json');
      await downloadVersionManifest();
      p(1.0, 'Version manifest ready');
    }));
    queue.add(FnTask('version_json', (p) async {
      p(0.0, 'Fetching version json');
      await downloadVersionJson();
      p(1.0, 'Version json ready');
    }));
    queue.add(FnTask('client', (p) async {
      p(0.0, 'Downloading client jar');
      await downloadClientJar();
      p(1.0, 'Client jar ready');
    }));
    queue.add(FnTask('libraries', (p) async {
      final versionData = await getVersionData();
      final libraries = (versionData?['libraries'] as List?) ?? [];
      final libTotal = _countLibraryFiles(libraries);
      int processed = 0;
      p(0.0, 'Downloading libraries (0/$libTotal)');
      if (libraries.isNotEmpty) {
        await downloadLibraries(onFile: (_) {
          processed++;
          final pp = libTotal <= 0 ? 1.0 : (processed / libTotal).clamp(0.0, 1.0);
          p(pp, 'Downloading libraries ($processed/$libTotal)');
        });
      }
      p(1.0, 'Libraries ready');
    }));
    queue.add(FnTask('assets', (p) async {
      final versionData = await getVersionData();
      int assetsTotal = 0;
      try {
        final assetIndex = versionData?['assetIndex'];
        if (assetIndex != null) {
          final assetIndexUrl = assetIndex['url'];
          final resp = await http.get(Uri.parse(assetIndexUrl));
          if (resp.statusCode == 200) {
            final idx = jsonDecode(resp.body);
            assetsTotal = (idx['objects'] as Map<String, dynamic>).length;
          }
        }
      } catch (_) {}
      p(0.0, 'Downloading assets ($assetsTotal files)');
      await downloadAssets(onAsset: (processed, total) {
        final denom = total <= 0 ? assetsTotal : total;
        final pp = denom <= 0 ? 0.0 : (processed / denom).clamp(0.0, 1.0);
        p(pp, 'Downloading assets ($processed/$total)');
      });
      p(1.0, 'Assets ready');
    }));
    queue.add(FnTask('java', (p) async {
      p(0.0, 'Preparing Java runtime');
      final versionData = await getVersionData();
      final java = await _tryMojangRuntime(versionData) ?? await _findJavaExecutable();
      if (java == null) throw Exception('Java not found');
      p(1.0, 'Java ready');
    }));
    queue.add(FnTask('forge', (p) async {
      final requiresForge = forgeVersion.trim().isNotEmpty;
      if (!requiresForge) {
        p(1.0, 'Forge not required');
        return;
      }
      p(0.0, 'Preparing Forge installer');
      final okInstaller = await downloadForgeInstaller();
      if (!okInstaller) throw Exception('Forge installer download failed');
      int forgeProcessed = 0;
      int forgeTotal = 0;
      p(0.2, 'Installing Forge');
      final okForgeInstall = await installForge(onFile: (pp, tt, _) {
        forgeProcessed = pp;
        forgeTotal = tt;
        final denom = forgeTotal <= 0 ? 1 : forgeTotal;
        final p01 = 0.2 + 0.75 * (forgeProcessed / denom).clamp(0.0, 1.0);
        p(p01, 'Forge libraries ($forgeProcessed/$forgeTotal)');
      });
      if (!okForgeInstall) throw Exception('Forge install failed');
      p(1.0, 'Forge ready');
    }));
    queue.add(FnTask('modpack', (p) async {
      final zip = _selectedModpackZipUrl.trim();
      if (zip.isEmpty) {
        p(1.0, 'Modpack not required');
        return;
      }
      await _installModpackZip(zipUrl: zip, reportProgress: (pp, msg) => p(pp, msg));
      p(1.0, 'Modpack ready');
    }));
    queue.add(FnTask('verify', (p) async {
      p(0.0, 'Verifying installation');
      final okVerify = await _verifyRequiredLibraries();
      if (!okVerify) throw Exception('Required libraries missing');
      p(1.0, 'Ready to play');
    }));

    await queue.run(reportProgress);
    return true;
  }

  static String _slugify(String input) {
    final s = input.trim().toLowerCase();
    final cleaned = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.isEmpty ? 'modpack' : cleaned;
  }

  static File _modpackMetaFile(Directory dir) => File('${dir.path}/meta.json');

  static Future<Map<String, dynamic>> _readJsonFile(File f) async {
    try {
      if (!await f.exists()) return <String, dynamic>{};
      final text = await f.readAsString();
      final v = jsonDecode(text);
      return (v is Map<String, dynamic>) ? v : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> _writeJsonFile(File f, Map<String, dynamic> data) async {
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  static Future<String?> _sha256OfFile(File file) async {
    try {
      final digestSink = _DigestCollector();
      final sink = sha256.startChunkedConversion(digestSink);
      await for (final chunk in file.openRead()) {
        sink.add(chunk);
      }
      sink.close();
      return digestSink.value?.toString();
    } catch (_) {
      return null;
    }
  }

  static String _hexNorm(String? s) {
    if (s == null) return '';
    return s.trim().toLowerCase().replaceAll(RegExp(r'\s'), '');
  }

  static bool _zipRelativePathAllowed(String unixRelative) {
    final normalized = unixRelative.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.contains('://')) return false;
    for (final seg in normalized.split('/')) {
      if (seg.isEmpty || seg == '.' || seg == '..') return false;
      if (Platform.isWindows) {
        for (var i = 0; i < seg.length; i++) {
          if (seg.codeUnitAt(i) < 32) return false;
        }
        if (seg.endsWith(' ') || seg.endsWith('.')) return false;
        if (seg.contains(RegExp(r'[<>:"|?*]'))) return false;
      }
    }
    return true;
  }

  static bool _isRedirect(int code) => code == 301 || code == 302 || code == 303 || code == 307 || code == 308;

  static Future<http.StreamedResponse> _modpackGet(http.Client client, Uri start) async {
    Uri current = start;
    for (var hop = 0; hop < 12; hop++) {
      final req = http.Request('GET', current);
      req.followRedirects = false;
      final resp = await client.send(req);
      if (_isRedirect(resp.statusCode)) {
        await resp.stream.drain();
        final loc = resp.headers['location'];
        if (loc == null || loc.trim().isEmpty) {
          return resp;
        }
        final next = Uri.tryParse(loc);
        if (next == null) {
          return resp;
        }
        current = next.isAbsolute ? next : current.resolveUri(next);
        continue;
      }
      return resp;
    }
    throw Exception('Modpack download: too many redirects');
  }

  static Future<void> _installModpackZip({
    required String zipUrl,
    required void Function(double p01, String msg) reportProgress,
  }) async {
    if (_cacheRoot == null || _instanceRoot == null) await initialize();

    final targetDir = _instanceDir;
    final modpackDir = _modpacksDownloadsRoot;
    await modpackDir.create(recursive: true);

    final zipFile = File('${modpackDir.path}/modpack.zip');
    final metaFile = _modpackMetaFile(modpackDir);
    var meta = await _readJsonFile(metaFile);

    final markerFile = File('${targetDir.path}/.modpack_installed.json');
    final installingFile = File('${targetDir.path}/.modpack_installing.json');

    var markerMatchesCatalog = false;
    if (await markerFile.exists()) {
      try {
        final raw = await markerFile.readAsString();
        final data = jsonDecode(raw);
        if (data is Map) {
          final prevV = (data['modpackVersion'] as String?)?.trim() ?? '';
          final prevU = (data['zipUrl'] as String?)?.trim() ?? '';
          markerMatchesCatalog =
              prevV == _selectedModpackVersion.trim() && prevU == zipUrl.trim();
        }
      } catch (_) {}
    }

    final uri = Uri.parse(zipUrl);
    final catalogSha = kDebugMode ? '' : _hexNorm(_selectedModpackZipSha256);
    final ver = _selectedModpackVersion.trim();
    final zu = zipUrl.trim();

    final metaSource = (meta['sourceUrl'] as String?)?.trim() ?? '';
    final metaLogical = (meta['logicalVersion'] as String?)?.trim() ?? '';
    final metaContentSha256 = _hexNorm(meta['contentSha256'] as String?);
    final hasStoredSha256 = metaContentSha256.isNotEmpty;
    final metaIdentityOk = metaSource == zu &&
        (metaLogical == ver || (metaLogical.isEmpty && hasStoredSha256));

    var skipModpackDownload = false;
    if (await zipFile.exists()) {
      if (catalogSha.isNotEmpty && metaIdentityOk) {
        final d256 = await _sha256OfFile(zipFile);
        if (d256 != null && _hexNorm(d256) == catalogSha) {
          skipModpackDownload = true;
        }
      }
      if (!skipModpackDownload && metaIdentityOk && metaContentSha256.isNotEmpty) {
        final d256 = await _sha256OfFile(zipFile);
        if (d256 != null && _hexNorm(d256) == metaContentSha256) {
          skipModpackDownload = true;
        }
      }
    }

    const downloadPortion = 0.70;
    const extractPortion = 0.30;

    String? zipSha256 = meta['contentSha256'] as String?;

    if (!skipModpackDownload) {
      reportProgress(0.0, 'Downloading modpack');
      final tmp = File('${zipFile.path}.part');
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }

      final client = http.Client();
      try {
        final resp = await _modpackGet(client, uri).timeout(const Duration(minutes: 5));
        if (resp.statusCode != 200) {
          await resp.stream.drain();
          throw Exception('Modpack download failed: HTTP ${resp.statusCode}');
        }

        final total = resp.contentLength;
        int received = 0;
        final sink = tmp.openWrite();
        final d256 = _DigestCollector();
        final sha256Conv = sha256.startChunkedConversion(d256);
        try {
          await for (final chunk in resp.stream) {
            received += chunk.length;
            sink.add(chunk);
            sha256Conv.add(chunk);
            if (total != null && total > 0) {
              reportProgress((received / total).clamp(0.0, 1.0) * downloadPortion,
                  'Downloading modpack (${(received / (1024 * 1024)).toStringAsFixed(1)}MB / ${(total / (1024 * 1024)).toStringAsFixed(1)}MB)');
            } else {
              reportProgress(0.0, 'Downloading modpack (${(received / (1024 * 1024)).toStringAsFixed(1)}MB)');
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
          sha256Conv.close();
        }

        zipSha256 = d256.value?.toString();

        if (catalogSha.isNotEmpty) {
          final got = _hexNorm(zipSha256);
          if (got != catalogSha) {
            try {
              await tmp.delete();
            } catch (_) {}
            throw Exception('Modpack SHA-256 mismatch (catalog vs download)');
          }
        }

        if (await zipFile.exists()) {
          try {
            await zipFile.delete();
          } catch (_) {}
        }
        await tmp.rename(zipFile.path);

        final installedSha256Keep = meta['installedSha256'];
        meta = <String, dynamic>{
          'sourceUrl': zu,
          'logicalVersion': ver,
          'contentSha256': zipSha256,
          'installedSha256': installedSha256Keep,
          'downloadedAt': DateTime.now().toIso8601String(),
        };
        await _writeJsonFile(metaFile, meta);
      } finally {
        client.close();
      }
    } else {
      reportProgress(downloadPortion, 'Modpack already downloaded');
      zipSha256 = await _sha256OfFile(zipFile) ?? zipSha256;
    }

    meta = await _readJsonFile(metaFile);
    final contentSha = _hexNorm(meta['contentSha256'] as String?);
    final installedSha = _hexNorm(meta['installedSha256'] as String?);
    if (await markerFile.exists() &&
        markerMatchesCatalog &&
        contentSha.isNotEmpty &&
        installedSha.isNotEmpty &&
        contentSha == installedSha) {
      final disk256 = await _sha256OfFile(zipFile);
      if (disk256 != null && _hexNorm(disk256) == contentSha) {
        reportProgress(1.0, 'Modpack already installed');
        return;
      }
    }

    reportProgress(downloadPortion, 'Installing modpack');
    await installingFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'name': _selectedModpackName,
        'modpackVersion': _selectedModpackVersion,
        'zipUrl': zipUrl,
        'zipSha256': zipSha256,
        'startedAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
    final z256 = zipSha256?.trim();
    final stagingKey = (z256 != null && z256.isNotEmpty) ? z256 : 'unknown';
    final stagingDir = Directory('${modpackDir.path}/_staging/$stagingKey');
    if (await stagingDir.exists()) {
      try {
        await stagingDir.delete(recursive: true);
      } catch (_) {}
    }
    await stagingDir.create(recursive: true);

    final input = InputFileStream(zipFile.path);
    final archive = ZipDecoder().decodeBuffer(input);

    final entries = archive.files.where((f) => f.name.isNotEmpty).toList();
    final totalEntries = entries.isEmpty ? 1 : entries.length;
    int processed = 0;

    final stagedFiles = <File>[];
    for (final f in entries) {
      processed++;

      final rawName = f.name.replaceAll('\\', '/');
      final name = rawName.startsWith('/') ? rawName.substring(1) : rawName;
      if (name.isEmpty || !_zipRelativePathAllowed(name)) continue;

      final destPath = '${stagingDir.path}/$name';
      final normalizedDest = File(destPath).absolute.path;
      final normalizedRoot = Directory(stagingDir.path).absolute.path;
      if (!normalizedDest.startsWith(normalizedRoot)) {
        continue;
      }

      if (f.isFile) {
        final outFile = File(normalizedDest);
        await outFile.parent.create(recursive: true);
        final data = f.content as List<int>;
        await outFile.writeAsBytes(data, flush: false);
        stagedFiles.add(outFile);
      } else {
        await Directory(normalizedDest).create(recursive: true);
      }

      final p = downloadPortion + (extractPortion * (processed / totalEntries).clamp(0.0, 1.0) * 0.5);
      reportProgress(p, 'Unpacking modpack ($processed/$totalEntries)');
    }

    final totalFiles = stagedFiles.isEmpty ? 1 : stagedFiles.length;
    int copied = 0;

    for (final src in stagedFiles) {
      copied++;
      final rel = src.path.substring(stagingDir.path.length + 1).replaceAll('\\', '/');

      final out = File('${targetDir.path}/$rel');
      final normalizedOut = out.absolute.path;
      final normalizedRoot = Directory(targetDir.path).absolute.path;
      if (!normalizedOut.startsWith(normalizedRoot)) continue;
      await out.parent.create(recursive: true);
      await out.writeAsBytes(await src.readAsBytes(), flush: false);

      final p = downloadPortion + (extractPortion * (0.5 + 0.5 * (copied / totalFiles).clamp(0.0, 1.0)));
      reportProgress(p, 'Updating files ($copied/$totalFiles)');
    }

    await markerFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'name': _selectedModpackName,
        'modpackVersion': _selectedModpackVersion,
        'zipUrl': zipUrl,
        'zipSha256': zipSha256,
        'installedAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
    final updated = await _readJsonFile(metaFile);
    await _writeJsonFile(metaFile, <String, dynamic>{
      ...updated,
      'installedSha256': zipSha256,
      'installedAt': DateTime.now().toIso8601String(),
    });
    if (await installingFile.exists()) {
      try {
        await installingFile.delete();
      } catch (_) {}
    }
    reportProgress(1.0, 'Modpack installed');
  }

  static Future<void> initialize() async {
    _logger.debug('DEBUG: Initializing launcher service...');
    _dataRoot = LauncherDirs.dataRoot();
    await _dataRoot!.create(recursive: true);
    _cacheRoot = Directory('${_dataRoot!.path}/cache/mojang');
    await _cacheRoot!.create(recursive: true);
    _instanceRoot = Directory('${_dataRoot!.path}/instances/$_instanceSlug');
    await _instanceRoot!.create(recursive: true);
    await _modpacksDownloadsRoot.create(recursive: true);
    _logger.debug('DEBUG: Directories created successfully');
  }

  static Future<bool> downloadVersionManifest() async {
    try {
      if (_cacheRoot == null || _instanceRoot == null) await initialize();

      if (versionInfoUrl.isEmpty) {
        _logger.debug('ERROR: No version info URL available from backend');
        return false;
      }

      final manifestPath = '${_mojangRoot.path}/version_manifest.json';
      final manifestFile = File(manifestPath);
      if (await manifestFile.exists()) {
        return true;
      }

      _logger.debug('DEBUG: Downloading version manifest...');
      final response = await http.get(Uri.parse(versionInfoUrl));

      if (response.statusCode == 200) {
        await manifestFile.writeAsString(response.body);
        _logger.debug('DEBUG: Version manifest downloaded and saved as JSON');

        return true;
      } else {
        _logger.debug('ERROR: Failed to download version manifest: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _logger.debug('ERROR: Exception downloading version manifest: $e');
      return false;
    }
  }

  static Future<String?> getVersionUrl() async {
    try {
      if (_cacheRoot == null || _instanceRoot == null) await initialize();

      final manifestFile = File('${_mojangRoot.path}/version_manifest.json');
      if (!await manifestFile.exists()) {
        _logger.debug('ERROR: Version manifest not found');
        return null;
      }

      final content = await manifestFile.readAsString();
      final json = jsonDecode(content);
      final versions = json['versions'] as List;

      for (var version in versions) {
        if (version['id'] == minecraftVersion) {
          _logger.debug('DEBUG: Found version $minecraftVersion URL: ${version['url']}');
          return version['url'];
        }
      }

      _logger.debug('ERROR: Version $minecraftVersion not found in manifest');
      return null;
    } catch (e) {
      _logger.debug('ERROR: Exception parsing version manifest: $e');
      return null;
    }
  }

  static Future<bool> downloadVersionJson() async {
    try {
      if (_cacheRoot == null || _instanceRoot == null) await initialize();

      final versionFile = File('${_mojangRoot.path}/version_$minecraftVersion.json');
      if (await versionFile.exists()) {
        return true;
      }

      final versionUrl = await getVersionUrl();
      if (versionUrl == null) {
        _logger.debug('ERROR: Could not get version URL');
        return false;
      }

      _logger.debug('DEBUG: Downloading version JSON from: $versionUrl');
      final response = await http.get(Uri.parse(versionUrl));

      if (response.statusCode == 200) {
        await versionFile.writeAsString(response.body);
        _logger.debug('DEBUG: Version JSON downloaded successfully');
        return true;
      } else {
        _logger.debug('ERROR: Failed to download version JSON: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _logger.debug('ERROR: Exception downloading version JSON: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getVersionData() async {
    try {
      if (_cacheRoot == null || _instanceRoot == null) await initialize();

      final versionFile = File('${_mojangRoot.path}/version_$minecraftVersion.json');
      if (!await versionFile.exists()) {
        _logger.debug('ERROR: Version JSON not found');
        return null;
      }

      final content = await versionFile.readAsString();
      final json = jsonDecode(content);
      _logger.debug('DEBUG: Version JSON loaded successfully');
      return json;
    } catch (e) {
      _logger.debug('ERROR: Exception reading version JSON: $e');
      return null;
    }
  }

  static Future<bool> downloadClientJar() async {
    if (_cacheRoot == null || _instanceRoot == null) await initialize();
    final versionData = await getVersionData();
    if (versionData == null) return false;
    return mc.downloadClientJar(log: _logger.debug, mojangRoot: _mojangRoot, minecraftVersion: minecraftVersion, versionData: versionData);
  }

  static Future<bool> downloadLibraries({void Function(String name)? onFile}) async {
    if (_cacheRoot == null || _instanceRoot == null) await initialize();
    final versionData = await getVersionData();
    if (versionData == null) return false;
    return mc.downloadLibraries(log: _logger.debug, mojangRoot: _mojangRoot, versionData: versionData, onFile: onFile);
  }

  static int _countLibraryFiles(List libraries) {
    int total = 0;
    for (final library in libraries) {
      if (library is! Map) continue;
      final downloads = library['downloads'];
      if (downloads is Map && downloads['artifact'] != null) total++;
      if (downloads is Map && downloads['classifiers'] is Map) {
        final classifiers = downloads['classifiers'] as Map;
        if (Platform.isWindows) {
          if (classifiers.containsKey('natives-windows-64') || classifiers.containsKey('natives-windows')) total++;
        } else if (Platform.isLinux) {
          if (classifiers.containsKey('natives-linux')) total++;
        } else if (Platform.isMacOS) {
          if (classifiers.containsKey('natives-osx')) total++;
        }
      }
    }
    return total;
  }

  static Future<bool> downloadAssets({void Function(int processed, int total)? onAsset}) async {
    if (_cacheRoot == null || _instanceRoot == null) await initialize();
    final versionData = await getVersionData();
    if (versionData == null) return false;
    return mc.downloadAssets(
      log: _logger.debug,
      mojangRoot: _mojangRoot,
      minecraftAssetBaseUrl: minecraftAssetBaseUrl,
      versionData: versionData,
      onAsset: onAsset,
    );
  }

  static Future<bool> downloadForgeInstaller() async {
    if (_cacheRoot == null || _instanceRoot == null) await initialize();
    return forge.downloadForgeInstaller(
      log: _logger.debug,
      mojangRoot: _mojangRoot,
      minecraftVersion: minecraftVersion,
      forgeInstallerUrlFallback: forgeInstallerUrl,
      mavenRepositories: mavenRepositories,
      forgeVersion: forgeVersion,
      forgePromotionsUrl: forgePromotionsUrl,
    );
  }

  static Future<bool> installForge({void Function(int processed, int total, String name)? onFile}) async {
    if (_cacheRoot == null || _instanceRoot == null) await initialize();
    return forge.installForge(
      log: _logger.debug,
      mojangRoot: _mojangRoot,
      minecraftVersion: minecraftVersion,
      forgeVersion: forgeVersion,
      findJavaExecutable: _findJavaExecutable,
      mavenRepositories: mavenRepositories,
      onFile: onFile,
    );
  }

  static Future<String?> _findJavaExecutable() async {
    try {
      final cached = _resolvedJavaPath;
      if (cached != null && cached.trim().isNotEmpty) {
        if (await File(cached).exists()) return cached;
      }

      final settings = await LauncherSettings.load();
      final chosen = settings.javaExecutablePath;
      if (chosen != null && chosen.trim().isNotEmpty) {
        if (await File(chosen).exists()) return chosen;
      }

      final versionData = await getVersionData();
      final mojang = await _tryMojangRuntime(versionData);
      if (mojang != null) return mojang;

      final managed = await _tryManagedJava();
      if (managed != null) return managed;

      final detected = await JavaDetector.detect();
      if (detected.isNotEmpty) return detected.first.executablePath;

      return null;
    } catch (e) {
      _logger.debug('ERROR: Exception finding Java: $e');
      return null;
    }
  }

  static Future<String?> _tryManagedJava() async {
    final cfg = _launcherConfig?.javaRuntimes ?? const <String, dynamic>{};
    final byMajor = cfg['8'];
    if (byMajor is! Map) return null;
    final plat = _javaPlatformKey();
    final spec = byMajor[plat];
    if (spec is! Map) return null;
    final url = (spec['url'] as String?) ?? '';
    final sha256 = (spec['sha256'] as String?) ?? '';
    if (url.trim().isEmpty || sha256.trim().isEmpty) return null;
    return JavaRuntimeManager.ensureInstalled(JavaRuntimeSpec(url: url, sha256: sha256, major: 8));
  }

  static String _javaPlatformKey() {
    if (Platform.isWindows) return 'windows-x64';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'other';
  }

  static String? _resolvedJavaPath;

  static int _requiredJavaMajor(Map<String, dynamic>? versionData) {
    try {
      final jv = versionData?['javaVersion'];
      if (jv is Map) {
        final mv = jv['majorVersion'];
        if (mv is int) return mv;
        if (mv is num) return mv.toInt();
      }
    } catch (_) {}
    return 8;
  }

  static Future<String?> _tryMojangRuntime(Map<String, dynamic>? versionData) async {
    final major = _requiredJavaMajor(versionData);
    try {
      _logger.debug('DEBUG: Resolving Mojang Java runtime major=$major');
      final java = await MojangJavaRuntimeManager.ensureForMajor(major);
      if (java == null || java.trim().isEmpty) return null;
      _resolvedJavaPath = java;
      _logger.debug('DEBUG: Mojang Java runtime ready: $java');
      return java;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _buildClasspath() async {
    final librariesDir = Directory('${_mojangRoot.path}/libraries');
    final clientJar = '${_mojangRoot.path}/versions/$minecraftVersion/$minecraftVersion.jar';

    final classpathList = <String>[];

    // Deduplicate by artifact, prefer highest version
    final Map<String, _JarEntry> bestByArtifact = {};
    final files = librariesDir.listSync(recursive: true);
    for (final file in files) {
      if (file is! File) continue;
      if (!file.path.endsWith('.jar')) continue;

      final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : file.path.split('/').last;
      final parsed = _parseJarName(name);
      if (parsed == null) {
        // Fallback: include unknown naming once
        final key = name;
        bestByArtifact.putIfAbsent(key, () => _JarEntry(artifact: key, version: '0', path: file.path.replaceAll('\\', '/')));
        continue;
      }

      final current = bestByArtifact[parsed.artifact];
      if (current == null || _compareVersions(parsed.version, current.version) > 0) {
        bestByArtifact[parsed.artifact] = _JarEntry(artifact: parsed.artifact, version: parsed.version, path: file.path.replaceAll('\\', '/'));
      }
    }

    // Materialize in deterministic order
    final sorted = bestByArtifact.values.toList()..sort((a, b) => a.artifact.compareTo(b.artifact));
    for (final e in sorted) {
      classpathList.add(e.path);
    }

    // Add client JAR
    classpathList.add(clientJar.replaceAll('\\', '/'));

    // Add Forge universal JAR (find dynamically)
    final versionsDir = Directory('${_mojangRoot.path}/versions/$minecraftVersion');
    if (await versionsDir.exists()) {
      final versionFiles = await versionsDir.list().toList();
      for (final file in versionFiles) {
        if (file is File && file.path.contains('forge') && file.path.endsWith('.jar')) {
          classpathList.add(file.path.replaceAll('\\', '/'));
          _logger.debug('DEBUG: Added Forge JAR to classpath: ${file.path}');
          break;
        }
      }
    }

    return classpathList.join(';');
  }

  static Future<bool> _verifyRequiredLibraries() async {
    try {
      // Check for Minecraft client JAR
      final clientJar = '${_mojangRoot.path}/versions/$minecraftVersion/$minecraftVersion.jar';
      if (!await File(clientJar).exists()) {
        _logger.debug('ERROR: Minecraft client JAR not found: $clientJar');
        return false;
      }

      // Check for Forge universal JAR (name may vary based on version)
      final versionsDir = Directory('${_mojangRoot.path}/versions/$minecraftVersion');
      bool forgeJarFound = false;

      if (await versionsDir.exists()) {
        final files = await versionsDir.list().toList();
        for (final file in files) {
          if (file is File && file.path.contains('forge') && file.path.endsWith('.jar')) {
            forgeJarFound = true;
            break;
          }
        }
      }

      if (!forgeJarFound) {
        _logger.debug('ERROR: Forge universal JAR not found in versions directory');
        return false;
      }

      // Check for critical libraries (these should be downloaded from install_profile.json)
      final criticalLibraries = [
        'libraries/net/minecraft/launchwrapper/1.12/launchwrapper-1.12.jar',
        'libraries/org/ow2/asm/asm-all/5.0.3/asm-all-5.0.3.jar',
        'libraries/lzma/lzma/0.0.1/lzma-0.0.1.jar', // The missing LZMA library
      ];

      for (final libPath in criticalLibraries) {
        final fullPath = '${_mojangRoot.path}/$libPath';
        if (!await File(fullPath).exists()) {
          _logger.debug('ERROR: Critical library missing: $libPath');
          return false;
        }
      }

      _logger.debug('DEBUG: All required libraries verified');
      return true;
    } catch (e) {
      _logger.debug('ERROR: Exception verifying libraries: $e');
      return false;
    }
  }

  // Single unified play method: verify, download if missing, then launch
  static Future<bool> play({String? username, String? uuid, String? accessToken, void Function(String)? reportStatus}) async {
    try {
      if (_cacheRoot == null || _instanceRoot == null) await initialize();

      _logger.debug('DEBUG: Starting unified play flow...');
      void status(String s) {
        if (reportStatus != null) reportStatus(s);
      }

      // Reuse installAll to perform all setup; stream status/progress
      final okInstall = await installAll(reportProgress: (p, msg) => status(msg));
      if (!okInstall) return false;

      // Launch the game
      _logger.debug('DEBUG: Launching game...');
      status('Launching game');
      final settings = await LauncherSettings.load();
      final javaPath = await _findJavaExecutable();
      if (javaPath == null) {
        _logger.debug('ERROR: Java not found. Please install Java.');
        return false;
      }

      final classpath = await _buildClasspath();
      final assetsDir = '${_mojangRoot.path}/assets';
      final gameDir = _instanceDir.path;

      _logger.debug('DEBUG: Java: $javaPath');
      _logger.debug('DEBUG: Game Dir: $gameDir');

      final maxRamMb = settings.maxRamMb <= 0 ? LauncherSettings.defaults.maxRamMb : settings.maxRamMb;
      final command = [
        javaPath,
        '-Xmx${maxRamMb}M',
        ...settings.jvmFlags,
        '-Djava.library.path=${_mojangRoot.path}/libraries/natives',
        '-Dfml.ignoreInvalidMinecraftCertificates=true',
        '-Dfml.ignorePatchDiscrepancies=true',
        '-cp',
        classpath,
        'net.minecraft.launchwrapper.Launch',
        '--tweakClass',
        'cpw.mods.fml.common.launcher.FMLTweaker',
        '--version',
        minecraftVersion,
        '--userProperties',
        '{}',
        '--accessToken',
        accessToken ?? 'offline',
        '--assetIndex',
        minecraftVersion,
        '--assetsDir',
        assetsDir,
        '--gameDir',
        gameDir,
        '--username',
        username ?? 'Player',
        '--uuid',
        uuid ?? '00000000-0000-0000-0000-000000000000',
      ];

      _logger.debug('DEBUG: Launch command: ${command.join(' ')}');

      final process = await Process.start(
        command[0],
        command.sublist(1),
        workingDirectory: gameDir,
      );

      process.stdout.listen((data) {
        stdout.add(data);
      });

      process.stderr.listen((data) {
        stderr.add(data);
        final errorText = String.fromCharCodes(data);

        if (errorText.contains('ClassNotFoundException') || errorText.contains('NoClassDefFoundError')) {
          _logger.debug('ERROR: Missing dependency detected: $errorText');
          _logger.debug('ERROR: This usually means a required library is missing or corrupted.');
          _logger.debug('ERROR: Try running play() again to re-download missing files.');
        }
      });

      final exitCode = await process.exitCode;
      _logger.debug('DEBUG: Minecraft exited with code: $exitCode');

      if (exitCode != 0) {
        _logger.debug('ERROR: Game failed to launch. Check the error messages above for missing dependencies.');
      }

      return exitCode == 0;
    } catch (e) {
      _logger.debug('ERROR: Exception in play(): $e');
      return false;
    }
  }
}

class IntegrityResult {
  int total = 0;
  int missing = 0;
  bool missingClientJar = false;
  bool missingAssetIndex = false;
  bool missingForgeJar = false;
  bool missingModpack = false;
  int missingLibraries = 0;
  int missingAssets = 0;
  double get progress => total == 0 ? 0.0 : ((total - missing) / total).clamp(0.0, 1.0);

  String summary() {
    final parts = <String>[];
    if (missingClientJar) parts.add('Client');
    if (missingForgeJar) parts.add('Forge');
    if (missingAssetIndex) parts.add('Metadata');
    if (missingModpack) parts.add('Modpack');
    if (missingLibraries > 0) parts.add('Libs:$missingLibraries');
    if (missingAssets > 0) parts.add('Assets:$missingAssets');
    if (parts.isEmpty) return 'none';
    return parts.join(' ');
  }
}
