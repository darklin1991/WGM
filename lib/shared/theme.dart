import 'package:flutter/material.dart';

import '../core/models/role.dart';

/// 法官在昏暗環境操作，因此固定深色主題、降低亮度刺激，
/// 並放大觸控目標（現場動作快、光線差、容易誤觸）。
abstract final class WgmTheme {
  /// 觸控目標最小高度。Material 建議 48，現場操作再放大。
  static const double tapTargetSize = 56;

  static const Color _bg = Color(0xFF12141A);
  static const Color _surface = Color(0xFF1C1F27);
  static const Color _surfaceHigh = Color(0xFF262A34);

  static const Color wolfColor = Color(0xFFE06C6C);
  static const Color godColor = Color(0xFF62B6E8);
  static const Color villagerColor = Color(0xFF9AA3B2);
  static const Color deadColor = Color(0xFF5A616E);

  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7E57C2),
      brightness: Brightness.dark,
    ).copyWith(surface: _surface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _surfaceHigh),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(tapTargetSize),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(tapTargetSize),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 依角色類別取顯示色，方便法官快速掃視。
  static Color colorOf(Role? role) {
    if (role == null) return villagerColor;
    return switch (role.kind) {
      RoleKind.wolf => wolfColor,
      RoleKind.god => godColor,
      RoleKind.villager => villagerColor,
    };
  }
}
