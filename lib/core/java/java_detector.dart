import 'dart:io';

class JavaInstallation {
  final String executablePath;
  final String versionLabel;

  const JavaInstallation({required this.executablePath, required this.versionLabel});

  @override
  String toString() => '$versionLabel ($executablePath)';
}

class JavaDetector {
  static Future<List<JavaInstallation>> detect() async {
    final candidates = <String>{};

    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.trim().isNotEmpty) {
      if (Platform.isWindows) {
        candidates.add(_join(javaHome, 'bin', 'javaw.exe'));
      } else {
        candidates.add(_join(javaHome, 'bin', 'java'));
      }
    }

    if (Platform.isWindows) {
      final where = await Process.run('where', ['javaw'], runInShell: false);
      if (where.exitCode == 0) {
        for (final line in where.stdout.toString().split(RegExp(r'\r?\n'))) {
          final p = line.trim();
          if (p.isNotEmpty) candidates.add(p);
        }
      }

      for (final base in <String>[
        r'C:\Program Files\Java',
        r'C:\Program Files (x86)\Java',
      ]) {
        try {
          final dir = Directory(base);
          if (!await dir.exists()) continue;
          for (final e in dir.listSync(followLinks: false)) {
            if (e is! Directory) continue;
            candidates.add(_join(e.path, 'bin', 'javaw.exe'));
          }
        } catch (_) {}
      }
    }

    final installs = <JavaInstallation>[];
    for (final path in candidates) {
      if (!await File(path).exists()) continue;
      final version = await _readJavaVersion(path);
      installs.add(JavaInstallation(executablePath: path, versionLabel: version));
    }

    installs.sort((a, b) => a.versionLabel.compareTo(b.versionLabel));
    return _dedupeByPath(installs);
  }

  static List<JavaInstallation> _dedupeByPath(List<JavaInstallation> list) {
    final seen = <String>{};
    final out = <JavaInstallation>[];
    for (final j in list) {
      final key = j.executablePath.toLowerCase();
      if (seen.add(key)) out.add(j);
    }
    return out;
  }

  static Future<String> _readJavaVersion(String javaExe) async {
    try {
      final res = await Process.run(javaExe, ['-version'], runInShell: false);
      final raw = (res.stderr.toString().trim().isNotEmpty ? res.stderr.toString() : res.stdout.toString()).trim();
      final firstLine = raw.split(RegExp(r'\r?\n')).firstOrNull?.trim();
      if (firstLine != null && firstLine.isNotEmpty) return firstLine;
      return 'java';
    } catch (_) {
      return 'java';
    }
  }
}

String _join(String a, String b, String c) {
  final sep = Platform.pathSeparator;
  final aa = a.endsWith(sep) ? a.substring(0, a.length - 1) : a;
  return '$aa$sep$b$sep$c';
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

