import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../fs/launcher_dirs.dart';
import '../install/download.dart';
import '../install/verifiers.dart';

class MojangJavaRuntimeManager {
  static const String _allJsonUrl = 'https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json';

  static Directory _root() => Directory('${LauncherDirs.dataRoot().path}/runtimes/mojang');

  static Future<String?> ensureForMajor(int major, {void Function(double, String)? progress}) async {
    final platform = await _platformKey();
    if (platform == null) return null;

    final component = _componentForMajor(major);
    if (component == null) return null;

    final all = await _fetchJson(Uri.parse(_allJsonUrl));
    final platformNode = (all[platform] is Map) ? (all[platform] as Map).cast<String, dynamic>() : null;
    if (platformNode == null) return null;
    final list = platformNode[component];
    if (list is! List || list.isEmpty) return null;

    final chosen = _pickLatestRuntime(list);
    if (chosen == null) return null;

    final versionName = _readString(chosen, ['version', 'name']);
    final manifestUrl = _readString(chosen, ['manifest', 'url']);
    final manifestSha1 = _readString(chosen, ['manifest', 'sha1']);
    final manifestSize = _readInt(chosen, ['manifest', 'size']);
    if (versionName.isEmpty || manifestUrl.isEmpty || manifestSha1.isEmpty || manifestSize <= 0) return null;

    final runtimeDir = Directory('${_root().path}/$component/$platform/$versionName');
    final marker = File('${runtimeDir.path}/runtime.json');
    if (await marker.exists()) {
      try {
        final m = jsonDecode(await marker.readAsString());
        if (m is Map && (m['manifestSha1'] as String?) == manifestSha1) {
          final exe = await _findJavaExe(runtimeDir);
          if (exe != null) return exe;
        }
      } catch (_) {}
    }

    if (await runtimeDir.exists()) {
      try {
        await runtimeDir.delete(recursive: true);
      } catch (_) {}
    }
    await runtimeDir.create(recursive: true);

    final manifestFile = File('${runtimeDir.path}/manifest.json');
    final manifestDl = DownloadFileTask(
      url: Uri.parse(manifestUrl),
      outFile: manifestFile,
      verifier: CompositeVerifier([SizeVerifier(manifestSize), Sha1Verifier(manifestSha1)]),
      timeout: const Duration(minutes: 2),
    );
    await manifestDl.run((p, msg) => progress?.call(p * 0.05, 'manifest_$msg'));

    final manifest = await _fetchJson(manifestFile.uri);
    final files = (manifest['files'] is Map) ? (manifest['files'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    if (files.isEmpty) return null;

    final keys = files.keys.toList()..sort();
    final total = keys.isEmpty ? 1 : keys.length;
    int done = 0;

    for (final rel in keys) {
      final node = files[rel];
      if (node is! Map) {
        done++;
        continue;
      }
      final type = (node['type'] as String?) ?? '';
      if (type == 'directory') {
        await Directory('${runtimeDir.path}/$rel').create(recursive: true);
        done++;
        progress?.call(0.05 + 0.90 * (done / total).clamp(0.0, 1.0), 'dir_$done/$total');
        continue;
      }
      final downloads = (node['downloads'] is Map) ? (node['downloads'] as Map).cast<String, dynamic>() : null;
      final raw = (downloads?['raw'] is Map) ? (downloads!['raw'] as Map).cast<String, dynamic>() : null;
      final url = (raw?['url'] as String?) ?? '';
      final sha1 = (raw?['sha1'] as String?) ?? '';
      final size = (raw?['size'] as num?)?.toInt() ?? 0;
      if (url.isEmpty || sha1.isEmpty || size <= 0) {
        done++;
        continue;
      }
      final out = File('${runtimeDir.path}/$rel');
      await out.parent.create(recursive: true);
      final task = DownloadFileTask(
        url: Uri.parse(url),
        outFile: out,
        verifier: CompositeVerifier([SizeVerifier(size), Sha1Verifier(sha1)]),
        timeout: const Duration(minutes: 10),
      );
      await task.run((p, msg) {
        final next = 0.05 + 0.90 * ((done + p) / total).clamp(0.0, 1.0);
        progress?.call(next, 'file_${done + 1}/${total}_$msg');
      });
      done++;
    }

    final exe = await _findJavaExe(runtimeDir);
    if (exe == null) return null;

    await marker.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'component': component,
        'platform': platform,
        'version': versionName,
        'major': major,
        'manifestSha1': manifestSha1,
        'installedAt': DateTime.now().toIso8601String(),
        'java': exe,
      }),
      flush: true,
    );
    progress?.call(1.0, 'ready');
    return exe;
  }

  static String? _componentForMajor(int major) {
    if (major <= 8) return 'jre-legacy';
    if (major == 16) return 'java-runtime-alpha';
    if (major == 17) return 'java-runtime-gamma';
    if (major >= 21 && major < 25) return 'java-runtime-delta';
    if (major >= 25) return 'java-runtime-epsilon';
    if (major > 17 && major < 21) return 'java-runtime-gamma';
    return null;
  }

  static Map<String, dynamic>? _pickLatestRuntime(List list) {
    Map<String, dynamic>? best;
    DateTime? bestTime;
    for (final e in list) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final released = _readString(m, ['version', 'released']);
      final t = DateTime.tryParse(released);
      if (t == null) continue;
      if (best == null || bestTime == null || t.isAfter(bestTime)) {
        best = m;
        bestTime = t;
      }
    }
    return best;
  }

  static Future<Map<String, dynamic>> _fetchJson(Uri uri) async {
    if (uri.scheme == 'file') {
      final f = File.fromUri(uri);
      final text = await f.readAsString();
      final v = jsonDecode(text);
      return (v is Map<String, dynamic>) ? v : <String, dynamic>{};
    }
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) return <String, dynamic>{};
    final v = jsonDecode(res.body);
    return (v is Map<String, dynamic>) ? v : <String, dynamic>{};
  }

  static String _readString(Map<String, dynamic> m, List<String> path) {
    dynamic cur = m;
    for (final k in path) {
      if (cur is Map && cur[k] != null) {
        cur = cur[k];
      } else {
        return '';
      }
    }
    return cur is String ? cur : '';
  }

  static int _readInt(Map<String, dynamic> m, List<String> path) {
    dynamic cur = m;
    for (final k in path) {
      if (cur is Map && cur[k] != null) {
        cur = cur[k];
      } else {
        return 0;
      }
    }
    if (cur is int) return cur;
    if (cur is num) return cur.toInt();
    return 0;
  }

  static Future<String?> _platformKey() async {
    final arch = await _archKey();
    if (Platform.isWindows) return arch == 'arm64' ? 'windows-arm64' : 'windows-x64';
    if (Platform.isMacOS) return arch == 'arm64' ? 'mac-os-arm64' : 'mac-os';
    if (Platform.isLinux) return arch == 'x86' ? 'linux-i386' : 'linux';
    return null;
  }

  static Future<String> _archKey() async {
    if (Platform.isWindows) {
      final env = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toLowerCase();
      if (env.contains('arm64')) return 'arm64';
      if (env.contains('x86')) return 'x86';
      return 'x64';
    }
    try {
      final res = await Process.run('uname', ['-m'], runInShell: false);
      final s = res.stdout.toString().trim().toLowerCase();
      if (s.contains('aarch64') || s.contains('arm64')) return 'arm64';
      if (s == 'i386' || s == 'i686' || s.contains('86')) return 'x86';
    } catch (_) {}
    return 'x64';
  }

  static Future<String?> _findJavaExe(Directory root) async {
    if (Platform.isWindows) {
      final cand = File('${root.path}/bin/javaw.exe');
      if (await cand.exists()) return cand.path;
      final cand2 = File('${root.path}/bin/java.exe');
      if (await cand2.exists()) return cand2.path;
      return null;
    }
    final cand = File('${root.path}/bin/java');
    if (await cand.exists()) {
      await _ensureExecutable(cand);
      return cand.path;
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

