import 'package:flutter/material.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:media_kit/media_kit.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'bootstrap/desktop_window.dart';
import 'core/fs/launcher_dirs.dart';
import 'core/logging/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await setupDesktopWindow();

  await LauncherDirs.dataRoot().create(recursive: true);
  await Logger.initFileLogging();
  await _initializeServices();

  runApp(const MyApp());
}

Future<void> _initializeServices() async {
  MediaKit.ensureInitialized();
  VideoPlayerMediaKit.ensureInitialized();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConfig.appName,
      theme: AppTheme.theme,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}
