import 'dart:convert';
import 'dart:io';

import '../fs/launcher_dirs.dart';

class LauncherSettings {
  final String? javaExecutablePath;
  final int maxRamMb;
  final String jvmFlagsRaw;

  const LauncherSettings({
    required this.javaExecutablePath,
    required this.maxRamMb,
    required this.jvmFlagsRaw,
  });

  static const LauncherSettings defaults = LauncherSettings(
    javaExecutablePath: null,
    maxRamMb: 2048,
    jvmFlagsRaw: '',
  );

  static Future<File> _settingsFile() async {
    final dir = Directory('${LauncherDirs.dataRoot().path}/settings');
    await dir.create(recursive: true);
    final file = File('${dir.path}/launcher_settings.json');
    return file;
  }

  static Future<LauncherSettings> load() async {
    try {
      final f = await _settingsFile();
      if (!await f.exists()) return defaults;
      final raw = await f.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map) return defaults;
      final map = json.cast<String, dynamic>();
      return LauncherSettings(
        javaExecutablePath: (map['javaExecutablePath'] as String?)?.trim().isEmpty == true ? null : (map['javaExecutablePath'] as String?),
        maxRamMb: (map['maxRamMb'] as num?)?.toInt() ?? defaults.maxRamMb,
        jvmFlagsRaw: (map['jvmFlagsRaw'] as String?) ?? defaults.jvmFlagsRaw,
      );
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() async {
    final normalized = _normalizeJavaPath(javaExecutablePath);
    final f = await _settingsFile();
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(copyWith(javaExecutablePath: normalized).toJson()),
      flush: true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'javaExecutablePath': javaExecutablePath,
        'maxRamMb': maxRamMb,
        'jvmFlagsRaw': jvmFlagsRaw,
      };

  LauncherSettings copyWith({
    String? javaExecutablePath,
    int? maxRamMb,
    String? jvmFlagsRaw,
  }) {
    return LauncherSettings(
      javaExecutablePath: javaExecutablePath ?? this.javaExecutablePath,
      maxRamMb: maxRamMb ?? this.maxRamMb,
      jvmFlagsRaw: jvmFlagsRaw ?? this.jvmFlagsRaw,
    );
  }

  List<String> get jvmFlags {
    final s = jvmFlagsRaw.trim();
    if (s.isEmpty) return const [];

    final flags = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      final isSpace = ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
      if (!inQuotes && isSpace) {
        final part = buf.toString().trim();
        if (part.isNotEmpty) flags.add(part);
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) flags.add(tail);
    return flags;
  }

  Future<bool> selectedJavaExists() async {
    final p = javaExecutablePath;
    if (p == null || p.trim().isEmpty) return false;
    return File(p).exists();
  }
}

String? _normalizeJavaPath(String? path) {
  if (!Platform.isWindows) return path;
  final p = path?.trim();
  if (p == null || p.isEmpty) return null;
  final lower = p.toLowerCase();
  if (!lower.endsWith(r'\java.exe') && !lower.endsWith('/java.exe')) return p;
  final javaw = '${p.substring(0, p.length - 'java.exe'.length)}javaw.exe';
  if (File(javaw).existsSync()) return javaw;
  return p;
}

