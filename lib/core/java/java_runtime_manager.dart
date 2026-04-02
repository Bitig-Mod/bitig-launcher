import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../fs/launcher_dirs.dart';
import '../install/download.dart';
import '../install/verifiers.dart';

class JavaRuntimeSpec {
  final String url;
  final String sha256;
  final int major;

  const JavaRuntimeSpec({required this.url, required this.sha256, required this.major});
}

class JavaRuntimeManager {
  static Directory _root() => Directory('${LauncherDirs.dataRoot().path}/runtimes');

  static Future<String?> ensureInstalled(JavaRuntimeSpec spec, {void Function(double, String)? progress}) async {
    final u = Uri.tryParse(spec.url.trim());
    if (u == null || !u.isAbsolute || u.scheme != 'https') return null;
    final id = 'java${spec.major}_${_platformId()}';
    final destRoot = Directory('${_root().path}/$id');
    final marker = File('${destRoot.path}/runtime.json');
    if (await marker.exists()) {
      try {
        final m = jsonDecode(await marker.readAsString());
        if (m is Map && (m['sha256'] as String?) == spec.sha256) {
          final exe = await _findJavaExe(destRoot);
          if (exe != null) return exe;
        }
      } catch (_) {}
    }

    if (await destRoot.exists()) {
      try {
        await destRoot.delete(recursive: true);
      } catch (_) {}
    }
    await destRoot.create(recursive: true);

    final archiveFile = File('${destRoot.path}/runtime.archive');
    final dl = DownloadFileTask(
      url: u,
      outFile: archiveFile,
      verifier: Sha256Verifier(spec.sha256),
      timeout: const Duration(minutes: 20),
    );
    await dl.run((p, msg) => progress?.call(p * 0.5, msg));

    await _extractArchive(archiveFile, destRoot, (p, msg) => progress?.call(0.5 + 0.5 * p, msg));

    final exe = await _findJavaExe(destRoot);
    if (exe == null) return null;

    await marker.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'url': spec.url,
        'sha256': spec.sha256,
        'major': spec.major,
        'platform': _platformId(),
        'installedAt': DateTime.now().toIso8601String(),
        'java': exe,
      }),
      flush: true,
    );
    return exe;
  }

  static String _platformId() {
    if (Platform.isWindows) return 'windows-x64';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'other';
  }

  static Future<void> _extractArchive(File archiveFile, Directory destRoot, void Function(double, String)? progress) async {
    final p = archiveFile.path.toLowerCase();
    if (p.endsWith('.zip')) {
      final input = InputFileStream(archiveFile.path);
      final archive = ZipDecoder().decodeBuffer(input);
      final files = archive.files;
      final total = files.isEmpty ? 1 : files.length;
      var i = 0;
      for (final f in files) {
        i++;
        final name = f.name.replaceAll('\\', '/');
        if (name.isEmpty) continue;
        final outPath = '${destRoot.path}/$name';
        final normalizedOut = File(outPath).absolute.path;
        final normalizedRoot = destRoot.absolute.path;
        if (!normalizedOut.startsWith(normalizedRoot)) continue;
        if (f.isFile) {
          final out = File(normalizedOut);
          await out.parent.create(recursive: true);
          await out.writeAsBytes(f.content as List<int>, flush: false);
        } else {
          await Directory(normalizedOut).create(recursive: true);
        }
        progress?.call((i / total).clamp(0.0, 1.0), '$i/$total');
      }
      return;
    }

    final input = InputFileStream(archiveFile.path);
    final bytes = GZipDecoder().decodeBuffer(input);
    final archive = TarDecoder().decodeBytes(bytes);
    final files = archive.files;
    final total = files.isEmpty ? 1 : files.length;
    var i = 0;
    for (final f in files) {
      i++;
      final name = f.name.replaceAll('\\', '/');
      if (name.isEmpty) continue;
      final outPath = '${destRoot.path}/$name';
      final normalizedOut = File(outPath).absolute.path;
      final normalizedRoot = destRoot.absolute.path;
      if (!normalizedOut.startsWith(normalizedRoot)) continue;
      if (f.isFile) {
        final out = File(normalizedOut);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>, flush: false);
      } else {
        await Directory(normalizedOut).create(recursive: true);
      }
      progress?.call((i / total).clamp(0.0, 1.0), '$i/$total');
    }
  }

  static Future<String?> _findJavaExe(Directory root) async {
    if (Platform.isWindows) {
      final cand = File('${root.path}/bin/javaw.exe');
      if (await cand.exists()) return cand.path;
      final cand2 = await _findFirst(root, (p) => p.endsWith('javaw.exe'));
      return cand2;
    }
    if (Platform.isMacOS) {
      final cand = File('${root.path}/jre.bundle/Contents/Home/bin/java');
      if (await cand.exists()) {
        await _ensureExecutable(cand);
        return cand.path;
      }
    }
    final cand = File('${root.path}/bin/java');
    if (await cand.exists()) {
      await _ensureExecutable(cand);
      return cand.path;
    }
    final found = await _findFirst(root, (p) => p.endsWith('/bin/java') || p.endsWith('${Platform.pathSeparator}bin${Platform.pathSeparator}java'));
    if (found != null) {
      await _ensureExecutable(File(found));
    }
    return found;
  }

  static Future<String?> _findFirst(Directory root, bool Function(String pathLower) match) async {
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final p = e.path.replaceAll('\\', '/').toLowerCase();
        if (match(p)) return e.path;
      }
    }
    return null;
  }

  static Future<void> _ensureExecutable(File f) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['+x', f.path], runInShell: false);
    } catch (_) {}
  }
}

