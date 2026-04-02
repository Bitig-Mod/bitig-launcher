import 'package:flutter/material.dart';
import '../launcher_colors.dart';

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: LauncherColors.gold,
          secondary: LauncherColors.airXP,
          surface: LauncherColors.black,
          error: LauncherColors.airXP,
          onPrimary: LauncherColors.black,
          onSecondary: LauncherColors.black,
          onSurface: LauncherColors.lightGray,
          onError: LauncherColors.black,
        ),
        scaffoldBackgroundColor: LauncherColors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: LauncherColors.black,
          foregroundColor: LauncherColors.lightGray,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: LauncherColors.gold,
            foregroundColor: LauncherColors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: LauncherColors.gold,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: LauncherColors.backgroundPanel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: LauncherColors.borderDefault),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: LauncherColors.borderDefault),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: LauncherColors.gold, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: LauncherColors.airXP),
          ),
        ),
        cardTheme: CardTheme(
          color: LauncherColors.backgroundPanel,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: LauncherColors.borderDefault,
          thickness: 1,
        ),
      );
}
