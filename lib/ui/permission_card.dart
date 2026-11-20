import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../core/events.dart';

/// Asks the user whether Claude may run a tool.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onDeny,
  });

  final PermissionRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  /// What the tool is about to do, in its most readable form.
  static String detail(Map<String, dynamic> input) {
    final command = input['command'];
    if (command is String) return command;
    return const JsonEncoder.withIndent('  ').convert(input);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Claude wants to use ${request.toolName}',
              style: theme.textTheme.titleSmall,
            ),
            if (request.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(request.description),
              ),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  detail(request.input),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(onPressed: onDeny, child: const Text('Deny')),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
