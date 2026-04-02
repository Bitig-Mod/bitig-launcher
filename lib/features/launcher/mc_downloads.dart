import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../../core/install/download.dart';
import '../../core/install/verifiers.dart';

Future<bool> downloadClientJar({
  required void Function(String) log,
  required Directory mojangRoot,
  required String minecraftVersion,
  required Map<String, dynamic> versionData,
}) async {
  try {
    final downloads = versionData['downloads'];
    final clientJar = downloads['client'];
    if (clientJar == null) {
      log('ERROR: Client JAR not found in version data');
      return false;
    }

    final jarUrl = clientJar['url'];
    final expectedSha1 = clientJar['sha1'];
    final expectedSize = (clientJar['size'] as num?)?.toInt() ?? 0;
    final jarPath = '${mojangRoot.path}/versions/$minecraftVersion/';
    await Directory(jarPath).create(recursive: true);

    final jarFile = File('$jarPath/$minecraftVersion.jar');

    if (await jarFile.exists()) {
      if (await verifyFile(jarFile, expectedSha1, expectedSize)) {
        log('DEBUG: Client JAR already exists with correct hash');
        return true;
      } else {
        log('DEBUG: Client JAR hash mismatch, re-downloading');
      }
    }

    final u = Uri.tryParse(jarUrl.toString());
    if (u == null || !u.isAbsolute || u.scheme != 'https') return false;
    final v = verifierForSha1AndSize(expectedSha1?.toString() ?? '', expectedSize);
    await DownloadFileTask(url: u, outFile: jarFile, verifier: v, timeout: const Duration(minutes: 5)).run((_, __) {});
    log('DEBUG: Client JAR downloaded and verified successfully');
    return true;
  } catch (e) {
    log('ERROR: Exception downloading client JAR: $e');
    return false;
  }
}

Future<bool> downloadLibraries({
  required void Function(String) log,
  required Directory mojangRoot,
  required Map<String, dynamic> versionData,
  void Function(String name)? onFile,
}) async {
  try {
    final libraries = versionData['libraries'] as List;
    final librariesDir = Directory('${mojangRoot.path}/libraries');
    await librariesDir.create(recursive: true);

    log('DEBUG: Downloading ${libraries.length} libraries...');

    for (int i = 0; i < libraries.length; i++) {
      final library = libraries[i];
      final name = library['name'];
      final downloads = library['downloads'];

      if (downloads != null && downloads['artifact'] != null) {
        final artifact = downloads['artifact'];
        final url = artifact['url'];
        final path = artifact['path'];
        final expectedSha1 = artifact['sha1'];
        final expectedSize = (artifact['size'] as num?)?.toInt() ?? 0;

        final filePath = '${librariesDir.path}/$path';
        final file = File(filePath);

        bool needsDownload = true;
        if (await file.exists()) {
          if (await verifyFile(file, expectedSha1, expectedSize)) {
            needsDownload = false;
          } else {
              log('DEBUG: Library hash mismatch, re-downloading: $name');
          }
        }

        if (needsDownload) {
            log('DEBUG: Downloading library ${i + 1}/${libraries.length}: $name');
          final u = Uri.tryParse(url.toString());
          if (u != null && u.isAbsolute && u.scheme == 'https') {
            final v = verifierForSha1AndSize(expectedSha1?.toString() ?? '', expectedSize);
            await DownloadFileTask(url: u, outFile: file, verifier: v, timeout: const Duration(minutes: 5)).run((_, __) {});
              log('DEBUG: Library downloaded and verified: $name');
          }
        }
        onFile?.call(name.toString());
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
          final nativeArtifact = classifiers[classifierKey];
          final url = nativeArtifact['url'];
          final path = nativeArtifact['path'];
          final expectedSha1 = nativeArtifact['sha1'];
          final expectedSize = (nativeArtifact['size'] as num?)?.toInt() ?? 0;

          final filePath = '${librariesDir.path}/$path';
          final file = File(filePath);

          bool needsDownload = true;
          if (await file.exists()) {
            if (await verifyFile(file, expectedSha1, expectedSize)) {
              needsDownload = false;
            } else {
              log('DEBUG: Native library hash mismatch, re-downloading: $name ($classifierKey)');
            }
          }

          if (needsDownload) {
            log('DEBUG: Downloading native library: $name ($classifierKey)');
            final u = Uri.tryParse(url.toString());
            if (u != null && u.isAbsolute && u.scheme == 'https') {
              final v = verifierForSha1AndSize(expectedSha1?.toString() ?? '', expectedSize);
              await DownloadFileTask(url: u, outFile: file, verifier: v, timeout: const Duration(minutes: 5)).run((_, __) {});
              log('DEBUG: Native library downloaded and verified: $name ($classifierKey)');
            }
          }
          onFile?.call('$name ($classifierKey)');
        }
      }
    }

    await extractNativeLibraries(log: log, mojangRoot: mojangRoot);
    log('DEBUG: Libraries download completed');
    return true;
  } catch (e) {
    log('ERROR: Exception downloading libraries: $e');
    return false;
  }
}

Future<bool> extractNativeLibraries({required void Function(String) log, required Directory mojangRoot}) async {
  try {
    final librariesDir = Directory('${mojangRoot.path}/libraries');
    final nativesDir = Directory('${mojangRoot.path}/libraries/natives');
    await nativesDir.create(recursive: true);

    log('DEBUG: Extracting native libraries...');

    final files = librariesDir.listSync(recursive: true);
    for (final file in files) {
      if (file is File && file.path.endsWith('.jar')) {
        try {
          final bytes = await file.readAsBytes();
          final archive = ZipDecoder().decodeBytes(bytes);
          for (final archiveFile in archive) {
            if (archiveFile.name.startsWith('META-INF/')) continue;
            if (archiveFile.name.endsWith('.dll') || archiveFile.name.endsWith('.so') || archiveFile.name.endsWith('.dylib')) {
              final extractedFile = File('${nativesDir.path}/${archiveFile.name}');
              await extractedFile.parent.create(recursive: true);
              await extractedFile.writeAsBytes(archiveFile.content);
              log('DEBUG: Extracted native: ${archiveFile.name}');
            }
          }
        } catch (_) {}
      }
    }

    log('DEBUG: Native libraries extraction completed');
    return true;
  } catch (e) {
    log('ERROR: Exception extracting native libraries: $e');
    return false;
  }
}

Future<bool> downloadAssets({
  required void Function(String) log,
  required Directory mojangRoot,
  required String minecraftAssetBaseUrl,
  required Map<String, dynamic> versionData,
  void Function(int processed, int total)? onAsset,
}) async {
  try {
    final assetIndex = versionData['assetIndex'];
    if (assetIndex == null) {
      log('ERROR: Asset index not found in version data');
      return false;
    }

    final assetIndexUrl = assetIndex['url'];
    final assetIndexId = assetIndex['id'];
    final assetIndexSha1 = assetIndex['sha1'];
    final assetIndexSize = (assetIndex['size'] as num?)?.toInt() ?? 0;

    log('DEBUG: Downloading asset index: $assetIndexId from $assetIndexUrl');
    final indexFile = File('${mojangRoot.path}/assets/indexes/$assetIndexId.json');
    final indexUrl = Uri.tryParse(assetIndexUrl.toString());
    if (indexUrl == null || !indexUrl.isAbsolute || indexUrl.scheme != 'https') return false;
    final indexVerifier = verifierForSha1AndSize(assetIndexSha1?.toString() ?? '', assetIndexSize);
    await DownloadFileTask(url: indexUrl, outFile: indexFile, verifier: indexVerifier, timeout: const Duration(minutes: 2)).run((_, __) {});
    final assetIndexData = jsonDecode(await indexFile.readAsString());
    final objects = assetIndexData['objects'] as Map<String, dynamic>;

    final assetsDir = Directory('${mojangRoot.path}/assets');
    await assetsDir.create(recursive: true);

    final total = objects.length;
    int processed = 0;
    log('DEBUG: Downloading $total assets...');

    int downloaded = 0;
    int skipped = 0;
    int failed = 0;

    for (final entry in objects.entries) {
      try {
        final hash = entry.value['hash'];
        final size = (entry.value['size'] as num?)?.toInt() ?? 0;
        final hashPrefix = hash.substring(0, 2);
        final assetPath = 'objects/$hashPrefix/$hash';
        final assetFile = File('${assetsDir.path}/$assetPath');

        bool needsDownload = true;
        if (await assetFile.exists()) {
          if (await verifyFile(assetFile, hash, size)) {
            skipped++;
            processed++;
            onAsset?.call(processed, total);
            needsDownload = false;
          } else {
              log('DEBUG: Asset hash mismatch, re-downloading: ${entry.key}');
          }
        }

        if (needsDownload) {
          if (minecraftAssetBaseUrl.isEmpty) {
            failed++;
            continue;
          }
          final assetUrl = '$minecraftAssetBaseUrl/$hashPrefix/$hash';
          final u = Uri.tryParse(assetUrl);
          if (u == null || !u.isAbsolute || u.scheme != 'https') {
            failed++;
            processed++;
            onAsset?.call(processed, total);
            continue;
          }
          final v = verifierForSha1AndSize(hash.toString(), size);
          await DownloadFileTask(url: u, outFile: assetFile, verifier: v, timeout: const Duration(minutes: 2)).run((_, __) {});
          downloaded++;
          processed++;
          onAsset?.call(processed, total);
        }
      } catch (e) {
        log('ERROR: Exception downloading individual asset: $e');
        failed++;
        processed++;
        onAsset?.call(processed, total);
      }
    }

    log('DEBUG: Assets download completed - Downloaded: $downloaded, Skipped: $skipped, Failed: $failed');
    return true;
  } catch (e) {
    log('ERROR: Exception downloading assets: $e');
    return false;
  }
}

FileVerifier? verifierForSha1AndSize(String expectedSha1, int expectedSize) {
  final sha = expectedSha1.trim();
  final size = expectedSize;
  if (sha.isEmpty && size <= 0) return null;
  final list = <FileVerifier>[];
  if (size > 0) list.add(SizeVerifier(size));
  if (sha.isNotEmpty) list.add(Sha1Verifier(sha));
  return list.length == 1 ? list.first : CompositeVerifier(list);
}

Future<bool> verifyFile(File file, dynamic expectedSha1, int expectedSize) async {
  try {
    final sha = expectedSha1?.toString() ?? '';
    final v = verifierForSha1AndSize(sha, expectedSize);
    if (v == null) return await file.exists();
    await v.verify(file);
    return true;
  } catch (_) {
    return false;
  }
}

