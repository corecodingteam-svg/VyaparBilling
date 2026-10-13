import 'package:flutter/material.dart';

/// The design tokens of the app: every colour, size, radius and type style a screen may use.
///
/// The palette comes from the MotiPaper admin panel (`admin-panel/src/theme.ts` and `index.css`): violet brand, slate
/// sidebar, grey surfaces, tinted status badges, 13 px body text, 10 px cards and 8 px buttons. A screen never writes
/// a colour, font size, radius or spacing number of its own; if something is missing, it is added here and listed in
/// DESIGN.md first. Printed documents (PDF invoices, receipts) have their own user-chosen themes and are outside this.

// ---------------------------------------------------------------- colour

abstract final class AppColors {
  // Brand
  // The accent is chosen by the user (Settings › Theme) and set once at start-up and when it changes.
  static const defaultAccent = Color(0xFF7C3AED);
  static Color primary = defaultAccent;
  static Color primaryDark = const Color(0xFF6D28D9);
  static Color primarySoft = const Color(0xFFEDE9FE);

  /// Makes [accent] the brand colour; its dark and soft tints are derived from it.
  static void applyAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    primary = accent;
    primaryDark = hsl.withLightness((hsl.lightness - 0.07).clamp(0.0, 1.0)).toColor();
    primarySoft = hsl.withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0)).withLightness(0.94).toColor();
  }
  static const onPrimary = Color(0xFFFFFFFF);

  /// The colours of the start-up and long-wait progress bar.
  /// Slices of a pie chart, in order.
  static const chartPalette = [Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF16A34A), Color(0xFFEA580C), Color(0xFFDB2777), Color(0xFF0F766E), Color(0xFFCA8A04), Color(0xFF64748B)];

  static const loaderGradient = [Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853), Color(0xFF4285F4)];

  // Surfaces and lines
  static const background = Color(0xFFF9FAFB);
  static const surface = Color(0xFFFFFFFF);
  /// Table headers, read-only fields, hovered rows.
  static const surfaceMuted = Color(0xFFF9FAFB);
  static const surfaceHover = Color(0xFFF3F4F6);
  static const border = Color(0xFFE5E7EB);
  /// Dividers between table rows.
  static const borderSoft = Color(0xFFF3F4F6);
  static const borderStrong = Color(0xFFD1D5DB);
  static const scrim = Color(0x80000000);

  // Text
  static const text = Color(0xFF111827);
  static const textBody = Color(0xFF374151);
  static const textMuted = Color(0xFF6B7280);
  static const textSubtle = Color(0xFF9CA3AF);

  // Sidebar
  static const sidebar = Color(0xFF1F2937);
  static const sidebarHover = Color(0xFF374151);
  static const sidebarDivider = Color(0xFF374151);
  /// The current page's row.
  static Color get sidebarActive => primary;
  static const sidebarText = Color(0xFF9CA3AF);
  static const sidebarLabel = Color(0xFF6B7280);
  static const onSidebar = Color(0xFFFFFFFF);

  // Status. Each has a bright tone for icons and fills, a text tone that is readable on white, and a soft tint for badges.
  static const success = Color(0xFF10B981);
  static const successText = Color(0xFF2B8A3E);
  static const successOnSoft = Color(0xFF166534);
  static const successSoft = Color(0xFFDCFCE7);

  static const danger = Color(0xFFEF4444);
  /// Filled destructive buttons: white text on this passes contrast.
  static const dangerStrong = Color(0xFFDC2626);
  static const dangerText = Color(0xFFC92A2A);
  static const dangerOnSoft = Color(0xFF991B1B);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const dangerBorder = Color(0xFFFCA5A5);

  static const warning = Color(0xFFF59E0B);
  static const warningText = Color(0xFF92400E);
  static const warningSoft = Color(0xFFFEF3C7);

  static const info = Color(0xFF1D4ED8);
  static const infoSoft = Color(0xFFEFF6FF);

  static const neutralText = Color(0xFF475569);
  static const neutralSoft = Color(0xFFF1F5F9);

  // Money: what is owed to us is green, what we owe is red.
  static const moneyIn = successText;
  static const moneyOut = dangerText;
}

// ---------------------------------------------------------------- spacing, shape, size

/// Spacing scale. Gaps, paddings and margins use these and nothing else.
abstract final class AppSpace {
  /// A hairline gap between a label and its value.
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

abstract final class AppRadius {
  /// Small controls and tags.
  /// Checkboxes.
  static const double xs = 4;
  static const double sm = 6;
  /// Buttons, inputs, menus.
  static const double md = 8;
  /// Cards, dialogs, panels.
  static const double lg = 10;
  /// Pills and avatars' rounded containers.
  static const double pill = 20;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

abstract final class AppIconSize {
  static const double xs = 16;
  static const double sm = 18;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 36;
  /// The picture on an empty or error page.
  static const double hero = 56;
}

abstract final class AppSize {
  /// Height of buttons and segmented buttons.
  static const double control = 36;
  static const double sidebar = 232;
  /// The sidebar collapsed to icons.
  static const double sidebarRail = 72;
  /// A chart on a report.
  static const double chartHeight = 280;
  static const double drawer = 270;

  // Dialog content widths: a short form, a normal form, a table or map, a wide form. [dialogForm] is a maximum for the big
  // add/edit dialogs; the others are fixed widths for the content of a small dialog.
  static const double dialogSm = 360;
  static const double dialogMd = 460;
  static const double dialogLg = 560;
  static const double dialogXl = 640;
  static const double dialogForm = 900;
  static const double dialogMaxHeight = 720;
  /// A popover or preview.
  static const double popoverHeight = 520;

  // Field widths inside a wrapped form row, from a number to a name or address.
  static const double fieldXs = 120;
  static const double fieldSm = 180;
  static const double fieldMd = 240;
  static const double fieldLg = 300;

  /// The list beside the detail on master-detail screens (parties, items, banks, loans, expenses).
  static const double listPane = 320;
  /// The bill beside the items on the point-of-sale screen.
  static const double sidePanel = 400;

  /// Height of the area that holds a loading, empty or error state inside a card.
  static const double stateHeight = 260;
  static const double map = 320;
  static const double mapSm = 240;

  /// Where the layout switches from a drawer to a sidebar, and the narrowest widths for a compact top bar and a phone.
  static const double wide = 1000;
  static const double compactBar = 760;
  static const double phone = 600;
  /// Standard screen padding.
  static const double page = AppSpace.md;
}

abstract final class AppShadow {
  /// A card: 0 1px 3px rgba(0,0,0,.05).
  static const card = [BoxShadow(color: Color(0x0D000000), blurRadius: 3, offset: Offset(0, 1))];
  /// A menu or popup: 0 4px 16px rgba(0,0,0,.12).
  static const raised = [BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 4))];
}

// ---------------------------------------------------------------- type

/// The font sizes, in logical pixels.
abstract final class AppFont {
  static const double label = 10;
  static const double caption = 11;
  static const double small = 12;
  static const double body = 13;
  static const double bodyLarge = 14;
  static const double subtitle = 16;
  static const double title = 17;
  static const double headline = 22;
  static const double display = 28;
  /// Brand name on the sign-in hero.
  static const double hero = 40;
}

/// Text styles. Colour is left to the context (default text colour) unless a style is about colour.
abstract final class AppText {
  static const label = TextStyle(fontSize: AppFont.label, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.textMuted);
  static const caption = TextStyle(fontSize: AppFont.caption, color: AppColors.textMuted);
  static const small = TextStyle(fontSize: AppFont.small);
  static const body = TextStyle(fontSize: AppFont.body);
  static const bodyStrong = TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.w600);
  static const bodyLarge = TextStyle(fontSize: AppFont.bodyLarge);
  /// Helper text under fields, hints and notes.
  static const helper = TextStyle(fontSize: AppFont.small, color: AppColors.textMuted);
  static const error = TextStyle(fontSize: AppFont.small, color: AppColors.dangerText);
  /// A card or section heading.
  static const subtitle = TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.w600);
  /// A page heading.
  static const title = TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.w700, color: AppColors.text);
  /// A figure on a summary tile.
  static const headline = TextStyle(fontSize: AppFont.headline, fontWeight: FontWeight.w700);
  static const display = TextStyle(fontSize: AppFont.display, fontWeight: FontWeight.w700);
}

// ---------------------------------------------------------------- motion

/// How fast things move. Short, so the app feels responsive; and switched off for people who ask their device to reduce motion.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const curve = Curves.easeOutCubic;
  /// One shimmer sweep.
  static const shimmer = Duration(milliseconds: 1400);
  /// The delay between one list row's entrance and the next, and the most rows that are staggered.
  static const stagger = Duration(milliseconds: 30);
  static const staggerMax = 10;
}
