import 'package:flutter/material.dart';
import 'launcher_colors.dart';

class LauncherStyle {
  static const double chromeBarHeight = 48.0;

  static const LinearGradient profileScaffoldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [LauncherColors.backgroundDim, LauncherColors.backgroundPanel, LauncherColors.backgroundElevated],
  );

  static BoxDecoration chromeToggleDecoration({required bool selected}) {
    return BoxDecoration(
      color: selected ? LauncherColors.accentGold : Colors.transparent,
      borderRadius: BorderRadius.circular(radiusM),
      border: Border.all(color: LauncherColors.accentGold, width: 1),
      boxShadow: selected
          ? [BoxShadow(color: LauncherColors.accentGold.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)]
          : null,
    );
  }

  static const double spacingM = 16.0;
  static const double spacingL = 24.0;

  static const double radiusS = 4.0;
  static const double radiusM = 8.0;
  static const double radiusL = 12.0;

  static const TextStyle titleTextStyle =
      TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: LauncherColors.accentGold, letterSpacing: 2);
}
