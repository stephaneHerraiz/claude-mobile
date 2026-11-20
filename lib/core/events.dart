/// Events read from `claude -p --output-format stream-json`.
sealed class ClaudeEvent {
  const ClaudeEvent();
}

class SystemInit extends ClaudeEvent {
  const SystemInit(this.sessionId, this.cwd, this.model);
  final String sessionId;
  final String cwd;
  final String model;
}

sealed class ContentBlock {
  const ContentBlock();
}

class TextBlock extends ContentBlock {
  const TextBlock(this.text);
  final String text;
}

class ToolUseBlock extends ContentBlock {
  const ToolUseBlock(this.id, this.name, this.input);
  final String id;
  final String name;
  final Map<String, dynamic> input;
}

class AssistantMessage extends ClaudeEvent {
  const AssistantMessage(this.id, this.blocks);
  final String id;
  final List<ContentBlock> blocks;
}

/// A partial text chunk of the assistant message being generated.
class StreamDelta extends ClaudeEvent {
  const StreamDelta(this.text);
  final String text;
}

class ToolResult extends ClaudeEvent {
  const ToolResult(this.toolUseId, this.content, this.isError);
  final String toolUseId;
  final String content;
  final bool isError;
}

/// Claude asks the host whether it may run a tool.
class PermissionRequest extends ClaudeEvent {
  const PermissionRequest(
    this.requestId,
    this.toolUseId,
    this.toolName,
    this.input,
    this.description,
  );
  final String requestId;
  final String toolUseId;
  final String toolName;
  final Map<String, dynamic> input;
  final String description;
}

/// End of a turn.
class ResultEvent extends ClaudeEvent {
  const ResultEvent(this.isError, this.text, this.costUsd);
  final bool isError;
  final String text;
  final double costUsd;
}

class UnknownEvent extends ClaudeEvent {
  const UnknownEvent(this.raw);
  final Map<String, dynamic> raw;
}
