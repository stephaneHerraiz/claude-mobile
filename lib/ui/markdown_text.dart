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

  static final Map<(Brightness, Color), fm.ThemeData> _themes = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = (theme.brightness, theme.colorScheme.primary);
    return fm.Theme(
      data: _themes[key] ??= fm.ThemeData(
        brightness: key.$1,
        colorSchemeSeed: key.$2,
      ),
      child: MarkdownBody(data: data, selectable: true),
    );
  }
}
