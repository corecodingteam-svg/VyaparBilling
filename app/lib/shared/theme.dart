import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'design/tokens.dart';

export 'design/motion.dart';
export 'design/progress.dart';
export 'design/refresh.dart';
export 'design/keyboard_nav.dart';
export 'design/theme_cubit.dart';
export 'design/tokens.dart';
export 'design/validation.dart';

/// Button looks that are not the default for their button type. Everything else comes from [buildTheme].
abstract final class AppButtons {
  /// A filled button that deletes or removes something.
  static final destructive = FilledButton.styleFrom(backgroundColor: AppColors.dangerStrong, foregroundColor: AppColors.onPrimary);

  /// An outlined button that deletes or removes something.
  static final destructiveOutlined = OutlinedButton.styleFrom(foregroundColor: AppColors.dangerText, side: const BorderSide(color: AppColors.dangerBorder));

  /// A tinted button for the second most important action beside a primary one.
  static ButtonStyle get tonal => FilledButton.styleFrom(backgroundColor: AppColors.primarySoft, foregroundColor: AppColors.primaryDark);

  /// A compact icon-only button, for rows and sidebars.
  static final compactIcon = IconButton.styleFrom(
    visualDensity: VisualDensity.compact,
    minimumSize: const Size(AppSize.control - 2, AppSize.control - 2),
    padding: EdgeInsets.zero,
    iconSize: AppIconSize.sm,
  );
}

ColorScheme get _scheme => ColorScheme(
  brightness: Brightness.light,
  primary: AppColors.primary,
  onPrimary: AppColors.onPrimary,
  primaryContainer: AppColors.primarySoft,
  onPrimaryContainer: AppColors.primaryDark,
  secondary: AppColors.primaryDark,
  onSecondary: AppColors.onPrimary,
  secondaryContainer: AppColors.primarySoft,
  onSecondaryContainer: AppColors.primaryDark,
  tertiary: AppColors.info,
  onTertiary: AppColors.onPrimary,
  error: AppColors.dangerStrong,
  onError: AppColors.onPrimary,
  errorContainer: AppColors.dangerSoft,
  onErrorContainer: AppColors.dangerOnSoft,
  surface: AppColors.surface,
  onSurface: AppColors.text,
  onSurfaceVariant: AppColors.textMuted,
  surfaceTint: Colors.transparent,
  surfaceDim: AppColors.background,
  surfaceBright: AppColors.surface,
  surfaceContainerLowest: AppColors.surface,
  surfaceContainerLow: AppColors.background,
  surfaceContainer: AppColors.surfaceHover,
  surfaceContainerHigh: AppColors.surfaceHover,
  surfaceContainerHighest: AppColors.neutralSoft,
  outline: AppColors.borderStrong,
  outlineVariant: AppColors.border,
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: AppColors.text,
  onInverseSurface: AppColors.surface,
  inversePrimary: AppColors.primarySoft,
);

final _controlShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
const _controlPadding = EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm);
const _controlSize = Size(0, AppSize.control);

OutlineInputBorder _inputBorder(Color color, [double width = 1]) =>
    OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: BorderSide(color: color, width: width));

ThemeData buildTheme() {
  const textTheme = TextTheme(
    displayLarge: AppText.display,
    displayMedium: AppText.display,
    displaySmall: AppText.headline,
    headlineLarge: AppText.display,
    headlineMedium: AppText.headline,
    headlineSmall: AppText.headline,
    titleLarge: AppText.title,
    titleMedium: AppText.subtitle,
    titleSmall: AppText.bodyStrong,
    bodyLarge: AppText.bodyLarge,
    bodyMedium: AppText.body,
    bodySmall: AppText.small,
    labelLarge: AppText.bodyStrong,
    labelMedium: TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.w600),
    labelSmall: AppText.label,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: _scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.surface,
    textTheme: textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    primaryTextTheme: textTheme,
    hoverColor: AppColors.primary.withValues(alpha: 0.04),
    highlightColor: AppColors.primary.withValues(alpha: 0.06),
    splashColor: AppColors.primary.withValues(alpha: 0.08),
    focusColor: AppColors.primary.withValues(alpha: 0.12),
    iconTheme: const IconThemeData(color: AppColors.textMuted, size: AppIconSize.md),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
    }),

    // ---- buttons
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: _controlSize,
        padding: _controlPadding,
        shape: _controlShape,
        textStyle: AppText.bodyStrong,
        iconSize: AppIconSize.sm,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.textSubtle,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: _controlSize,
        padding: _controlPadding,
        shape: _controlShape,
        elevation: 0,
        textStyle: AppText.bodyStrong,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: _controlSize,
        padding: _controlPadding,
        shape: _controlShape,
        textStyle: AppText.bodyStrong,
        iconSize: AppIconSize.sm,
        foregroundColor: AppColors.textBody,
        backgroundColor: AppColors.surfaceMuted,
        side: const BorderSide(color: AppColors.border),
        disabledForegroundColor: AppColors.textSubtle,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: _controlSize,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        shape: _controlShape,
        textStyle: AppText.bodyStrong,
        iconSize: AppIconSize.sm,
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.textSubtle,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: AppColors.textMuted, iconSize: AppIconSize.md, shape: _controlShape)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(_controlSize),
        shape: WidgetStatePropertyAll(_controlShape),
        textStyle: const WidgetStatePropertyAll(AppText.bodyStrong),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primarySoft : AppColors.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primaryDark : AppColors.textBody),
        iconSize: const WidgetStatePropertyAll(AppIconSize.sm),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary, elevation: 2),

    // ---- fields
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
      border: _inputBorder(AppColors.border),
      enabledBorder: _inputBorder(AppColors.border),
      focusedBorder: _inputBorder(AppColors.primary, 1.5),
      errorBorder: _inputBorder(AppColors.dangerText),
      focusedErrorBorder: _inputBorder(AppColors.dangerText, 1.5),
      disabledBorder: _inputBorder(AppColors.borderSoft),
      labelStyle: const TextStyle(fontSize: AppFont.body, color: AppColors.textMuted),
      floatingLabelStyle: TextStyle(fontSize: AppFont.body, color: AppColors.primaryDark),
      hintStyle: const TextStyle(fontSize: AppFont.body, color: AppColors.textSubtle),
      helperStyle: AppText.caption,
      errorStyle: const TextStyle(fontSize: AppFont.caption, color: AppColors.dangerText),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
      side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong)),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(AppColors.surface),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.primary, linearTrackColor: AppColors.primarySoft),
    sliderTheme: SliderThemeData(activeTrackColor: AppColors.primary, thumbColor: AppColors.primary),

    // ---- surfaces
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: const BorderSide(color: AppColors.border)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      titleTextStyle: AppText.title,
      contentTextStyle: const TextStyle(fontSize: AppFont.body, color: AppColors.textBody),
      insetPadding: const EdgeInsets.all(AppSpace.xxl),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpace.xxl, 0, AppSpace.xxl, AppSpace.lg),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surface, surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppText.title,
      shape: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.sidebar, surfaceTintColor: Colors.transparent, width: AppSize.drawer),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: const BorderSide(color: AppColors.border)),
      textStyle: const TextStyle(fontSize: AppFont.body, color: AppColors.text),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: const BorderSide(color: AppColors.border))),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.text, borderRadius: AppRadius.smAll),
      textStyle: const TextStyle(fontSize: AppFont.small, color: AppColors.surface),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs + 2),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      contentTextStyle: const TextStyle(fontSize: AppFont.body, color: AppColors.surface),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      actionTextColor: AppColors.primarySoft,
    ),
    scrollbarTheme: ScrollbarThemeData(thumbColor: const WidgetStatePropertyAll(AppColors.borderStrong), thickness: const WidgetStatePropertyAll(6), radius: const Radius.circular(3)),

    // ---- lists and tables
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textMuted,
      textColor: AppColors.text,
      titleTextStyle: TextStyle(fontSize: AppFont.body, color: AppColors.text),
      subtitleTextStyle: TextStyle(fontSize: AppFont.small, color: AppColors.textMuted),
      leadingAndTrailingTextStyle: TextStyle(fontSize: AppFont.small, color: AppColors.textMuted),
      minVerticalPadding: AppSpace.xs,
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.lg),
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(AppColors.surfaceMuted),
      headingTextStyle: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: AppColors.textMuted),
      dataTextStyle: TextStyle(fontSize: AppFont.small, color: AppColors.textBody),
      headingRowHeight: AppSize.control,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 52,
      dividerThickness: 1,
      horizontalMargin: AppSpace.lg,
      columnSpacing: AppSpace.xxl,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.neutralSoft,
      selectedColor: AppColors.primarySoft,
      labelStyle: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600, color: AppColors.neutralText),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.primary,
      dividerColor: AppColors.border,
      labelStyle: AppText.bodyStrong,
      unselectedLabelStyle: TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.w500),
    ),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border(), iconColor: AppColors.textMuted, collapsedIconColor: AppColors.textMuted),
  );
}

/// Accent colours offered for printed documents, as #RRGGBB. Printed documents keep their own, user-chosen colour.
const themeColorChoices = ['#1E5EFF', '#0F766E', '#16A34A', '#B45309', '#DC2626', '#7C3AED', '#DB2777', '#334155'];

/// Parses '#RRGGBB'; anything else gives the default document accent.
Color colorFromHex(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null || hex.length != 7 ? const Color(0xFF1E5EFF) : Color(0xFF000000 | value);
}

// ---------------------------------------------------------------- legacy names (being removed as screens are migrated)
const sidebarBg = AppColors.sidebar;
const receiveGreen = AppColors.moneyIn;
const payRed = AppColors.moneyOut;
const pageBg = AppColors.background;
