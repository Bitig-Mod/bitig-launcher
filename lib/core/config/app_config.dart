import 'package:flutter/foundation.dart';

class AppConfig {
  static const bool offlineMode = true;

  static const String launcherCatalogUrl = 'https://raw.githubusercontent.com/Bitig-Mod/bitig-launcher/main/config/launcher_catalog.json';

  static const String appName = 'Bitig Launcher';
  static const String displayVersionLabel = 'v0.1.7';
  static const String version = '0.1.7';

  static const Duration apiTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;

  static const String productionBaseUrl = '';
  static const String developmentBaseUrl = '';

  static String get baseUrl {
    if (offlineMode) return '';
    return kReleaseMode ? productionBaseUrl : developmentBaseUrl;
  }

  AppConfig._();
}
