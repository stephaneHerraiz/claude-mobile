import 'package:material_ui/material_ui.dart';

/// The app's colours: a phosphor-green terminal on black.
abstract final class TerminalColors {
  static const background = Color(0xFF050805);
  static const surface = Color(0xFF0B120C);
  static const raised = Color(0xFF122016);
  static const line = Color(0xFF2A5235);
  static const green = Color(0xFF3DFF7A);
  static const dimGreen = Color(0xFF1C7A3D);
  static const text = Color(0xFFC9F7D2);
  static const mutedText = Color(0xFF6FA57C);
  static const amber = Color(0xFFFFC857);
  static const red = Color(0xFFFF5C6C);
}

const _square = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(2)),
);

const _buttonText = TextStyle(
  fontFamily: 'monospace',
  fontWeight: FontWeight.bold,
  letterSpacing: 1.5,
);

/// One look, light or dark phone alike: monospace, square, green on black.
final ThemeData terminalTheme = _build();

ThemeData _build() {
  const scheme = ColorScheme.dark(
    primary: TerminalColors.green,
    onPrimary: TerminalColors.background,
    primaryContainer: TerminalColors.raised,
    onPrimaryContainer: TerminalColors.text,
    secondary: TerminalColors.amber,
    onSecondary: TerminalColors.background,
    secondaryContainer: TerminalColors.raised,
    onSecondaryContainer: TerminalColors.text,
    tertiary: TerminalColors.amber,
    surface: TerminalColors.background,
    onSurface: TerminalColors.text,
    onSurfaceVariant: TerminalColors.mutedText,
    surfaceContainerLowest: TerminalColors.background,
    surfaceContainerLow: TerminalColors.surface,
    surfaceContainer: TerminalColors.surface,
    surfaceContainerHigh: TerminalColors.raised,
    surfaceContainerHighest: TerminalColors.raised,
    outline: TerminalColors.dimGreen,
    outlineVariant: TerminalColors.line,
    error: TerminalColors.red,
    onError: TerminalColors.background,
  );
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'monospace',
    scaffoldBackgroundColor: TerminalColors.background,
  );
  const fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(2)),
    borderSide: BorderSide(color: TerminalColors.line),
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: TerminalColors.background,
      foregroundColor: TerminalColors.green,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        color: TerminalColors.green,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
      shape: const Border(bottom: BorderSide(color: TerminalColors.line)),
    ),
    dividerTheme: const DividerThemeData(
      color: TerminalColors.line,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: TerminalColors.green,
      textColor: TerminalColors.text,
      subtitleTextStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: TerminalColors.mutedText,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: const BorderSide(color: TerminalColors.green),
      ),
      labelStyle: const TextStyle(color: TerminalColors.mutedText),
      helperStyle: const TextStyle(color: TerminalColors.mutedText),
      helperMaxLines: 3,
      errorMaxLines: 3,
      prefixIconColor: TerminalColors.green,
      prefixStyle: const TextStyle(
        color: TerminalColors.green,
        fontWeight: FontWeight.bold,
      ),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: _square, textStyle: _buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _square,
        textStyle: _buttonText,
        side: const BorderSide(color: TerminalColors.dimGreen),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: _square, textStyle: _buttonText),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: TerminalColors.green,
      foregroundColor: TerminalColors.background,
      shape: _square,
    ),
    cardTheme: const CardThemeData(
      color: TerminalColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
        side: BorderSide(color: TerminalColors.line),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: TerminalColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
        side: BorderSide(color: TerminalColors.dimGreen),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: TerminalColors.raised,
      contentTextStyle: TextStyle(
        fontFamily: 'monospace',
        color: TerminalColors.text,
      ),
      shape: _square,
    ),
    bannerTheme: const MaterialBannerThemeData(
      backgroundColor: TerminalColors.raised,
      contentTextStyle: TextStyle(
        fontFamily: 'monospace',
        color: TerminalColors.amber,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: TerminalColors.green,
      linearTrackColor: TerminalColors.line,
    ),
  );
}
