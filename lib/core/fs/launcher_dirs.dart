import 'dart:io';

class LauncherDirs {
  static Directory dataRoot() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA']?.trim();
      if (appData != null && appData.isNotEmpty) {
        return Directory(_join2(appData, '.bitiglauncher'));
      }
    }
    final home = Platform.environment['HOME']?.trim() ?? Platform.environment['USERPROFILE']?.trim() ?? '.';
    return Directory(_join2(home, '.bitiglauncher'));
  }
}

String _join2(String a, String b) {
  final sep = Platform.pathSeparator;
  final aa = a.endsWith(sep) ? a.substring(0, a.length - 1) : a;
  final bb = b.startsWith(sep) ? b.substring(1) : b;
  return '$aa$sep$bb';
}

