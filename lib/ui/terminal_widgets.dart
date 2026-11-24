import 'package:material_ui/material_ui.dart';

/// A screen title, written as a comment line: `// Profiles`.
class TermTitle extends StatelessWidget {
  const TermTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('//', style: TextStyle(color: scheme.outline)),
        const SizedBox(width: 8),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// A line the app says, marked like terminal output: `> text` for
/// information, `! text` for a fault.
class TermLine extends StatelessWidget {
  const TermLine(this.text, {super.key, this.fault = false});
  final String text;
  final bool fault;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = fault ? scheme.error : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fault ? '! ' : '> ',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        Flexible(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
