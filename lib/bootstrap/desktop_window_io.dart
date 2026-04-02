import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/app_config.dart';

Future<void> setupDesktopWindow() async {
  if (Platform.isAndroid || Platform.isIOS) return;

  await windowManager.ensureInitialized();

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(1280, 720),
      center: true,
      title: AppConfig.appName,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(true);
      await windowManager.show();
      await windowManager.focus();
    },
  );
}
