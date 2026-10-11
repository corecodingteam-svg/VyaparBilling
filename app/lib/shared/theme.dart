import 'package:flutter/material.dart';

const brandBlue = Color(0xFF1E5EFF);
const sidebarBg = Color(0xFF0F172A);
const receiveGreen = Color(0xFF16A34A);
const payRed = Color(0xFFDC2626);
const pageBg = Color(0xFFF1F4F9);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: brandBlue, primary: brandBlue, surface: Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: pageBg,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE3E8EF))),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: Color(0xFFE3E8EF), space: 1),
  );
}

/// Accent colours offered for printed documents, as #RRGGBB.
const themeColorChoices = ['#1E5EFF', '#0F766E', '#16A34A', '#B45309', '#DC2626', '#7C3AED', '#DB2777', '#334155'];

/// Parses '#RRGGBB'; anything else gives the brand blue.
Color colorFromHex(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null || hex.length != 7 ? brandBlue : Color(0xFF000000 | value);
}
