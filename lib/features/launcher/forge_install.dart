import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;

import '../../core/install/download.dart';
import 'mc_downloads.dart' as mc;

Future<bool> downloadForgeInstaller({
  required void Function(String) log,
  required Directory mojangRoot,
  required String minecraftVersion,
  required String forgeInstallerUrlFallback,
  required List<String> mavenRepositories,
  required String forgeVersion,
  required String forgePromotionsUrl,
}) async {
  try {
    final installerFile = File('${mojangRoot.path}/forge-installer.jar');
    if (await installerFile.exists()) {
      log('DEBUG: Forge installer already exists, skipping download');
      return true;
    }

    final forgeVersionToUse = await _getLatestForgeVersion(
      log: log,
      minecraftVersion: minecraftVersion,
      forgePromotionsUrl: forgePromotionsUrl,
      forgeVersion: forgeVersion,
    );
    final installerUrl = _buildForgeInstallerUrl(minecraftVersion: minecraftVersion, forgeVersion: forgeVersionToUse, mavenRepositories: mavenRepositories);
    if (installerUrl.trim().isEmpty) {
      log('ERROR: Computed Forge installer URL is empty');
      return false;
    }

    final primary = Uri.tryParse(installerUrl);
    if (primary != null && primary.isAbsolute && primary.scheme == 'https') {
      try {
        await DownloadFileTask(url: primary, outFile: installerFile, timeout: const Duration(minutes: 5)).run((_, __) {});
        log('DEBUG: Forge installer downloaded successfully');
        return true;
      } catch (e) {
        log('WARNING: Primary Forge installer download failed: $e');
      }
    }

    if (forgeInstallerUrlFallback.trim().isEmpty) {
      log('ERROR: No Forge installer URL available from backend');
      return false;
    }
    final fallback = Uri.tryParse(forgeInstallerUrlFallback.trim());
    if (fallback == null || !fallback.isAbsolute || fallback.scheme != 'https') {
      log('ERROR: Forge installer fallback URL invalid');
      return false;
    }
    await DownloadFileTask(url: fallback, outFile: installerFile, timeout: const Duration(minutes: 5)).run((_, __) {});
    log('DEBUG: Forge installer downloaded successfully (fallback)');
    return true;
  } catch (e) {
    log('ERROR: Exception downloading Forge installer: $e');
    return false;
  }
}

Future<bool> extractForgeLibraries({
  required void Function(String) log,
  required Directory mojangRoot,
  required List<String> mavenRepositories,
  void Function(int processed, int total, String name)? onFile,
}) async {
  try {
    final installerFile = File('${mojangRoot.path}/forge-installer.jar');
    if (!await installerFile.exists()) {
      log('ERROR: Forge installer not found');
      return false;
    }

    log('DEBUG: Extracting install_profile.json from Forge installer...');
    final bytes = await installerFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    String? installProfileJson;
    for (final archiveFile in archive) {
      if (archiveFile.name == 'install_profile.json') {
        installProfileJson = String.fromCharCodes(archiveFile.content);
        break;
      }
    }
    if (installProfileJson == null) {
      log('ERROR: install_profile.json not found in Forge installer');
      return false;
    }

    log('DEBUG: Parsing install_profile.json...');
    final installProfile = jsonDecode(installProfileJson);
    final libraries = installProfile['versionInfo']['libraries'] as List;
    log('DEBUG: Found ${libraries.length} libraries in install_profile.json');

    final librariesDir = Directory('${mojangRoot.path}/libraries');
    await librariesDir.create(recursive: true);

    final total = libraries.length;
    for (int i = 0; i < libraries.length; i++) {
      final library = libraries[i];
      final name = library['name'] as String;
      onFile?.call(i + 1, total, name);

      final parts = name.split(':');
      if (parts.length < 3) continue;

      if (parts[0] == 'net.minecraftforge' && parts[1] == 'forge') {
        continue;
      }

      final groupId = parts[0].replaceAll('.', '/');
      final artifactId = parts[1];
      final version = parts[2];
      final classifier = parts.length > 3 ? parts[3] : null;

      String mavenPath = '$groupId/$artifactId/$version/$artifactId-$version';
      if (classifier != null) mavenPath += '-$classifier';
      mavenPath += '.jar';

      final targetFile = File('${librariesDir.path}/$mavenPath');
      if (await targetFile.exists()) continue;

      final repositories = <String>[];
      if (library['url'] != null) {
        final raw = library['url'].toString();
        final base = raw.replaceAll(RegExp(r'\/+$'), '');
        repositories.add('$base/$mavenPath');
      }
      if (parts[0] == 'net.minecraft' || parts[0] == 'lzma') {
        repositories.add('https://libraries.minecraft.net/$mavenPath');
      }
      for (final repo in mavenRepositories) {
        final base = repo.trim().replaceAll(RegExp(r'\/+$'), '');
        if (base.isEmpty) continue;
        repositories.add('$base/$mavenPath');
      }
      repositories.add('https://maven.minecraftforge.net/$mavenPath');

      final seen = <String>{};
      final uniqueRepos = <String>[];
      for (final u in repositories) {
        if (seen.add(u)) uniqueRepos.add(u);
      }

      bool downloaded = false;
      for (final downloadUrl in uniqueRepos) {
        final u = Uri.tryParse(downloadUrl);
        if (u == null || !u.isAbsolute || u.scheme != 'https') continue;
        try {
          await DownloadFileTask(url: u, outFile: targetFile, timeout: const Duration(minutes: 5)).run((_, __) {});
          bool verified = true;
          if (library['checksums'] is List) {
            final checksums = (library['checksums'] as List).cast<String>();
            verified = false;
            for (final sha in checksums) {
              if (await mc.verifyFile(targetFile, sha, 0)) {
                verified = true;
                break;
              }
            }
          }
          if (!verified) {
            try {
              await targetFile.delete();
            } catch (_) {}
            continue;
          }
          downloaded = true;
          break;
        } catch (_) {}
      }

      if (!downloaded) {
        log('WARNING: Failed to download $name from all repositories');
      }
    }

    log('DEBUG: Forge libraries downloaded successfully');
    return true;
  } catch (e) {
    log('ERROR: Exception extracting Forge libraries: $e');
    return false;
  }
}

Future<bool> installForge({
  required void Function(String) log,
  required Directory mojangRoot,
  required String minecraftVersion,
  required String forgeVersion,
  required Future<String?> Function() findJavaExecutable,
  required List<String> mavenRepositories,
  void Function(int processed, int total, String name)? onFile,
}) async {
  try {
    final installerFile = File('${mojangRoot.path}/forge-installer.jar');
    if (!await installerFile.exists()) {
      log('ERROR: Forge installer not found');
      return false;
    }

    final javaPath = await findJavaExecutable();
    if (javaPath == null) {
      log('ERROR: Java not found for Forge installation');
      return false;
    }

    if (!await extractForgeLibraries(log: log, mojangRoot: mojangRoot, mavenRepositories: mavenRepositories, onFile: onFile)) {
      log('ERROR: Failed to extract Forge libraries');
      return false;
    }

    final versionsDir = Directory('${mojangRoot.path}/versions/$minecraftVersion');
    await versionsDir.create(recursive: true);

    final v = forgeVersion.trim();
    if (v.isNotEmpty) {
      final expectedName = 'forge-$minecraftVersion-$v-$minecraftVersion-universal.jar';
      final targetJar = File('${versionsDir.path}/$expectedName');
      if (await targetJar.exists()) {
        log('DEBUG: Forge universal JAR already installed, skipping installer');
        return true;
      }
    } else {
      final listed = await versionsDir.list().toList();
      for (final e in listed) {
        if (e is File && e.path.contains('forge') && e.path.endsWith('-universal.jar')) {
          log('DEBUG: Forge universal JAR already present, skipping installer');
          return true;
        }
      }
    }

    final process = await Process.start(javaPath, ['-jar', installerFile.absolute.path, '--extract', '.'], workingDirectory: mojangRoot.path);
    process.stdout.listen((data) => log('FORGE INSTALLER OUTPUT: ${String.fromCharCodes(data)}'));
    process.stderr.listen((data) => log('FORGE INSTALLER ERROR: ${String.fromCharCodes(data)}'));
    final exitCode = await process.exitCode;
    if (exitCode != 0) return false;

    if (v.isEmpty) return false;

    final expectedName = 'forge-$minecraftVersion-$v-$minecraftVersion-universal.jar';
    final extractedJar = File('${mojangRoot.path}/$expectedName');
    final targetJar = File('${versionsDir.path}/$expectedName');

    if (await extractedJar.exists()) {
      await extractedJar.rename(targetJar.path);
      return true;
    }

    final candidates =
        Directory(mojangRoot.path).listSync().whereType<File>().where((f) => f.path.contains('forge-') && f.path.endsWith('-universal.jar')).toList();
    if (candidates.isNotEmpty) {
      final best = candidates.first;
      final dest = File('${versionsDir.path}/${best.uri.pathSegments.last}');
      await best.rename(dest.path);
      return true;
    }

    return false;
  } catch (e) {
    log('ERROR: Exception installing Forge: $e');
    return false;
  }
}

Future<String> _getLatestForgeVersion({
  required void Function(String) log,
  required String minecraftVersion,
  required String forgePromotionsUrl,
  required String forgeVersion,
}) async {
  if (forgeVersion.trim().isNotEmpty) return forgeVersion.trim();
  try {
    final response = await http.get(Uri.parse(forgePromotionsUrl)).timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final promos = json['promos'] as Map<String, dynamic>;
      final recommendedKey = '$minecraftVersion-recommended';
      final latestKey = '$minecraftVersion-latest';
      if (promos.containsKey(recommendedKey)) return promos[recommendedKey] as String;
      if (promos.containsKey(latestKey)) return promos[latestKey] as String;
    }
  } catch (_) {}
  log('WARNING: Could not fetch Forge version, using configured version: $forgeVersion');
  return forgeVersion;
}

String _buildForgeInstallerUrl({required String minecraftVersion, required String forgeVersion, required List<String> mavenRepositories}) {
  final mc = minecraftVersion.trim();
  final v = forgeVersion.trim();
  if (mc.isEmpty || v.isEmpty) return '';
  final full = '$mc-$v-$mc';
  final path = 'net/minecraftforge/forge/$full/forge-$full-installer.jar';
  final repos = <String>[...mavenRepositories.where((r) => r.trim().isNotEmpty), 'https://maven.minecraftforge.net'];
  final base = repos.first.replaceAll(RegExp(r'\/+$'), '');
  return '$base/$path';
}

