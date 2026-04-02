import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/launcher_colors.dart';

class AppVersionCorner extends StatelessWidget {
  const AppVersionCorner({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: Text(
          AppConfig.displayVersionLabel,
          style: const TextStyle(
            color: LauncherColors.accentGold,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
