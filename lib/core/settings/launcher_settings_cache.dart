import '../java/java_detector.dart';
import 'launcher_settings.dart';

class LauncherSettingsCache {
  static LauncherSettings? _settings;
  static List<JavaInstallation>? _detectedJavas;
  static bool? _javaMissing;
  static Future<void>? _inFlight;

  static LauncherSettings get settings => _settings ?? LauncherSettings.defaults;
  static List<JavaInstallation> get detectedJavas => _detectedJavas ?? const [];
  static bool get javaMissing => _javaMissing ?? false;

  static Future<void> warmup({bool forceRefresh = false}) async {
    if (!forceRefresh && _settings != null && _detectedJavas != null && _javaMissing != null) return;
    if (!forceRefresh && _inFlight != null) return _inFlight!;
    final f = _warmupInternal();
    _inFlight = f;
    await f;
    _inFlight = null;
  }

  static Future<void> refresh() => warmup(forceRefresh: true);

  static Future<void> _warmupInternal() async {
    final s = await LauncherSettings.load();
    final javas = await JavaDetector.detect();
    final missing = s.javaExecutablePath != null && s.javaExecutablePath!.trim().isNotEmpty && !await s.selectedJavaExists();
    _settings = s;
    _detectedJavas = javas;
    _javaMissing = missing;
  }

  static void updateSettings(LauncherSettings next) {
    _settings = next;
    _javaMissing = false;
  }
}

