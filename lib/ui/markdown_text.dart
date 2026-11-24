// ignore: deprecated_member_use, the Markdown package still builds on the framework's Material.
import 'package:flutter/material.dart' as fm;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

/// Markdown drawn in the app's colours.
///
/// The Markdown package reads the framework's own Material theme, not the one
/// `material_ui` provides. Without a theme of that kind above it, it falls
/// back to a light one: dark text, unreadable in dark mode.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key});
  final String data;

  static final Map<Object, fm.ThemeData> _themes = {};

  static fm.ThemeData _frameworkTheme(ThemeData app) {
    final base = fm.ThemeData(
      brightness: app.brightness,
      colorSchemeSeed: app.colorScheme.primary,
      fontFamily: app.textTheme.bodyMedium?.fontFamily,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: app.colorScheme.onSurface,
        displayColor: app.colorScheme.onSurface,
      ),
    );
  }

  /// Headings and links in the accent colour, code in a ruled box: the
  /// package's own defaults are blue links on grey.
  static MarkdownStyleSheet _sheet(fm.ThemeData base, ColorScheme scheme) {
    final heading = TextStyle(
      color: scheme.primary,
      fontWeight: FontWeight.bold,
    );
    final box = BoxDecoration(
      color: scheme.surfaceContainerLow,
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(2),
    );
    final sheet = MarkdownStyleSheet.fromTheme(base);
    return sheet.copyWith(
      a: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary,
      ),
      h1: sheet.h1?.merge(heading),
      h2: sheet.h2?.merge(heading),
      h3: sheet.h3?.merge(heading),
      h4: sheet.h4?.merge(heading),
      code: sheet.code?.copyWith(
        color: scheme.secondary,
        backgroundColor: scheme.surfaceContainerLow,
      ),
      codeblockDecoration: box,
      blockquoteDecoration: box,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      tableBorder: TableBorder.all(color: scheme.outlineVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = (
      theme.brightness,
      theme.colorScheme.primary,
      theme.colorScheme.onSurface,
      theme.textTheme.bodyMedium?.fontFamily,
    );
    return fm.Theme(
      data: _themes[key] ??= _frameworkTheme(theme),
      child: Builder(
        builder: (context) => MarkdownBody(
          data: data,
          selectable: true,
          styleSheet: _sheet(fm.Theme.of(context), theme.colorScheme),
        ),
      ),
    );
  }
}
