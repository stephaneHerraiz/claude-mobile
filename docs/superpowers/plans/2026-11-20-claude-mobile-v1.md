# claude-mobile v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter Android app that SSHes into Stéphane's machines (profiles "pro", "perso"), lists their Claude Code sessions, and lets him chat in them with approve/deny buttons for permission requests.

**Architecture:** Pure-Dart core (stream-json codec, event reducer, session-list parser) with no Flutter or network dependency, unit-tested first. A thin SSH layer (`dartssh2`) turns an exec channel into a `Stream<String>` of lines and a `Sink<String>`. Riverpod controllers wire SSH + codec + reducer; Flutter widgets only render state.

**Tech Stack:** Flutter (stable), Dart, `dartssh2`, `flutter_riverpod`, `flutter_secure_storage`, `local_auth`, `flutter_markdown`. Pin the latest stable version of each at implementation time and record it in `pubspec.yaml`.

**Spec:** `docs/superpowers/specs/2026-11-20-claude-mobile-design.md` (read its "Spike result 2" section: it fixes the wire format). Reference script: `docs/superpowers/specs/spike2-permission-roundtrip.js`.

## Global Constraints

- Flutter, SSH via `dartssh2`, no native SSH code.
- Public repo: zero secrets in git; keys only in `flutter_secure_storage`; biometric unlock via `local_auth`.
- Key-based SSH auth only (no password).
- Server side needs only `claude` on PATH and an SSH login; nothing to install.
- Transport command (exact): `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --permission-prompt-tool stdio --resume <session-id>`; new session uses `--session-id <uuid>` instead of `--resume`, run in the chosen cwd.
- Permission request: stdout line `{"type":"control_request","request_id":ID,"request":{"subtype":"can_use_tool","tool_name","display_name","input","description","permission_suggestions","blocked_path","tool_use_id"}}`. Allow reply on stdin: `{"type":"control_response","response":{"subtype":"success","request_id":ID,"response":{"behavior":"allow","updatedInput":<input>}}}`. Deny format (`behavior:"deny"` + `message`) is UNVERIFIED: Task 7 isolates it.
- User message on stdin: `{"type":"user","message":{"role":"user","content":"<text>"}}`.
- Sessions live in `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` on the server.
- v1 non-goals: attaching to a running TUI session, push notifications, file browser, diff viewer, terminal view, "always allow" buttons.
- Android first; iOS later from the same code.
- Dart code, identifiers, commits in English. UI strings in English for v1 (no i18n).
- Verification commands run on Stéphane's machine: the pod has no Flutter SDK and only 2 Gi RAM. Mark any step not run as "non lancé" with the reason.

## Review Focus

1. Stream chunks that split a JSON line, or contain several lines, or an unparseable line: the codec must buffer and skip bad lines without killing the session (Task 2).
2. Connection drops while a permission request is pending: the pending request must be cleared, shown as "interrupted", and the session resumable; never auto-approve on reconnect (Tasks 3, 7).
3. Partial-message streaming (`stream_event`): the final `assistant` message must replace the streamed draft, not duplicate it (Task 3).
4. The directory name in `~/.claude/projects` is a lossy encoding of the cwd (`/` and `.` become `-`): take the real cwd from the `.jsonl` content, never decode the folder name (Task 4).
5. Same session opened on the phone while a TUI writes to it: show a warning when the `.jsonl` mtime is under 60 s old, never block (Task 4).

---

## File Structure

```
pubspec.yaml
lib/main.dart
lib/core/events.dart            # sealed ClaudeEvent hierarchy
lib/core/codec.dart             # LineBuffer, parseEvent, encode* functions
lib/core/chat_state.dart        # ChatState + reduce()
lib/core/session_listing.dart   # listing command + parser
lib/ssh/profile.dart            # Profile model
lib/ssh/ssh_service.dart        # connect, exec -> LineChannel, reconnect
lib/storage/profile_store.dart  # secure storage of profiles and keys
lib/state/session_controller.dart  # Riverpod: wires ssh + codec + reducer
lib/state/providers.dart
lib/ui/profiles_screen.dart
lib/ui/sessions_screen.dart
lib/ui/chat_screen.dart
lib/ui/permission_card.dart
test/core/*_test.dart
test/state/session_controller_test.dart
```

---

### Task 1: Project scaffold

**Files:**
- Create: Flutter project at repo root (`flutter create --org dev.herraiz --platforms android .`), `analysis_options.yaml`, `.gitignore` additions, `README.md` (2 lines: what it is, "no secrets in git").
- Test: `test/smoke_test.dart`

**Interfaces:**
- Produces: a buildable app with `lib/main.dart` exposing `class ClaudeMobileApp extends StatelessWidget`.

- [ ] **Step 1: Write failing test** `test/smoke_test.dart`: `testWidgets('app shows profiles title')` pumping `ClaudeMobileApp` inside a `ProviderScope` and expecting `find.text('Profiles')`.
- [ ] **Step 2: Run** `flutter test test/smoke_test.dart`. Expected: FAIL (no such class).
- [ ] **Step 3: Implement** `ClaudeMobileApp` in `lib/main.dart` with a `MaterialApp` whose home is a placeholder `Scaffold` titled "Profiles". Add the dependencies from Tech Stack with `flutter pub add`.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: PASS, no issues.
- [ ] **Step 5: Commit** `feat: scaffold flutter project`.

### Task 2: stream-json codec

**Files:**
- Create: `lib/core/events.dart`, `lib/core/codec.dart`
- Test: `test/core/codec_test.dart`

**Interfaces:**
- Produces (`events.dart`):
  - `sealed class ClaudeEvent`
  - `SystemInit(String sessionId, String cwd, String model)`
  - `AssistantMessage(String id, List<ContentBlock> blocks)`
  - `sealed class ContentBlock`: `TextBlock(String text)`, `ToolUseBlock(String id, String name, Map<String, dynamic> input)`
  - `StreamDelta(String text)` (from `stream_event` text deltas)
  - `ToolResult(String toolUseId, String content, bool isError)`
  - `PermissionRequest(String requestId, String toolUseId, String toolName, Map<String, dynamic> input, String description)`
  - `ResultEvent(bool isError, String text, double costUsd)`
  - `UnknownEvent(Map<String, dynamic> raw)`
- Produces (`codec.dart`):
  - `class LineBuffer { List<String> add(String chunk); }` returns complete lines, keeps the remainder.
  - `ClaudeEvent? parseEvent(String line)` returns `null` for a non-JSON line.
  - `String encodeUserMessage(String text)`, `String encodeAllow(PermissionRequest r)`, `String encodeDeny(String requestId, String message)`. Each returns one JSON line ending with `\n`.

- [ ] **Step 1: Write failing tests** in `codec_test.dart`, using real lines copied from the spike output:
  - `parses system init` → `SystemInit` with `sessionId` and `cwd`.
  - `parses assistant tool_use` → `AssistantMessage` with one `ToolUseBlock('Bash', {'command':'touch hello.txt',...})`.
  - `parses can_use_tool` → `PermissionRequest` with `requestId`, `toolName == 'Bash'`.
  - `parses result` → `ResultEvent(isError:false, text:'Done.')`.
  - `unknown type yields UnknownEvent`; `garbage line yields null`.
  - `LineBuffer joins a line split across two chunks` and `splits two lines in one chunk`.
  - `encodeAllow` equals the exact JSON in Global Constraints (compare decoded maps); `encodeUserMessage('hi')` ends with `\n`.
- [ ] **Step 2: Run** `flutter test test/core/codec_test.dart`. Expected: FAIL (undefined symbols).
- [ ] **Step 3: Implement** the types and functions above. `parseEvent` switches on `type`/`subtype`; hook and rate-limit `system` events map to `UnknownEvent`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): stream-json codec`.

### Task 3: Chat state reducer

**Files:**
- Create: `lib/core/chat_state.dart`
- Test: `test/core/chat_state_test.dart`

**Interfaces:**
- Consumes: Task 2 events.
- Produces:
  - `class ChatItem` variants: `UserItem(String text)`, `AssistantTextItem(String text, {bool streaming})`, `ToolItem(String toolUseId, String name, Map<String,dynamic> input, {ToolStatus status, String? output})`, `NoticeItem(String text)`.
  - `enum ToolStatus { running, done, error }`
  - `class ChatState { final List<ChatItem> items; final PermissionRequest? pending; final bool busy; final String? sessionId; final double costUsd; }` with `ChatState.empty()`.
  - `ChatState reduce(ChatState s, ClaudeEvent e)`; `ChatState addUserMessage(ChatState s, String text)`; `ChatState connectionLost(ChatState s)`.

- [ ] **Step 1: Write failing tests:**
  - `StreamDelta appends to a streaming AssistantTextItem`.
  - `final AssistantMessage replaces the streaming draft instead of duplicating it` (Review Focus 3).
  - `ToolUseBlock adds a running ToolItem; ToolResult marks it done or error`.
  - `PermissionRequest sets pending; ResultEvent clears busy`.
  - `connectionLost clears pending and appends NoticeItem('Connection lost')` and never leaves `busy` true (Review Focus 2).
- [ ] **Step 2: Run** `flutter test test/core/chat_state_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** immutable classes and `reduce` as a pure function (no mutation of `s`).
- [ ] **Step 4: Run** same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): chat state reducer`.

### Task 4: Session listing

**Files:**
- Create: `lib/core/session_listing.dart`
- Test: `test/core/session_listing_test.dart`

**Interfaces:**
- Produces:
  - `class SessionInfo { String id; String cwd; DateTime modified; String? title; bool recentlyActive; }`
  - `const listSessionsCommand` (a single shell string run over SSH): for each `~/.claude/projects/*/*.jsonl` print `<epoch-seconds> <path>` via `find ... -printf '%T@ %p\n'` sorted newest first.
  - `List<SessionInfo> parseListing(String stdout, DateTime now)`: id from file name, `recentlyActive = now - modified < 60s`, `cwd` left empty until filled.
  - `String headCommand(String path)` returning `head -n 20 '<path>'` with single-quote escaping.
  - `SessionInfo withHead(SessionInfo s, String headOutput)`: fills `cwd` from the first line that has a `cwd` field and `title` from the first user message (trimmed to 80 chars).

- [ ] **Step 1: Write failing tests:** `parses two entries sorted newest first`; `marks recentlyActive under 60s`; `ignores blank and malformed lines`; `withHead takes cwd from content, not from folder name` using folder `-home-herraiz-dev-my-app` but cwd `/home/herraiz/dev/my.app` (Review Focus 4); `headCommand escapes a quote in the path`.
- [ ] **Step 2: Run** `flutter test test/core/session_listing_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the functions above.
- [ ] **Step 4: Run** same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): session listing parser`.

### Task 5: Profiles and secure storage

**Files:**
- Create: `lib/ssh/profile.dart`, `lib/storage/profile_store.dart`
- Test: `test/storage/profile_store_test.dart`

**Interfaces:**
- Produces:
  - `class Profile { String id; String name; String host; int port; String user; }` with `toJson`/`fromJson`. The private key is NOT a field of `Profile`.
  - `abstract class KeyValueStore { Future<String?> read(String k); Future<void> write(String k, String v); Future<void> delete(String k); }` (production impl wraps `FlutterSecureStorage`; tests use an in-memory fake).
  - `class ProfileStore { ProfileStore(KeyValueStore kv); Future<List<Profile>> list(); Future<void> save(Profile p, {required String privateKeyPem}); Future<String?> privateKey(String profileId); Future<void> remove(String profileId); }`

- [ ] **Step 1: Write failing tests** with a fake store: `save then list returns the profile`; `private key is stored under its own key and never appears in the profiles JSON` (assert the profiles entry does not contain the PEM); `remove deletes profile and key`.
- [ ] **Step 2: Run** `flutter test test/storage/profile_store_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** `ProfileStore`: profiles as one JSON list under `profiles`, keys under `key:<id>`. Add the `FlutterSecureStorage`-backed `KeyValueStore`.
- [ ] **Step 4: Run** same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(storage): profiles with secure private keys`.

### Task 6: SSH service

**Files:**
- Create: `lib/ssh/ssh_service.dart`
- Test: `test/ssh/ssh_service_test.dart` (unit: backoff only), manual check against a real host (Step 5).

**Interfaces:**
- Consumes: `Profile`, private key PEM (String).
- Produces:
  - `abstract class LineChannel { Stream<String> get lines; void writeLine(String jsonLine); Future<void> close(); Future<void> get done; }`
  - `abstract class SshService { Future<void> connect(Profile p, String privateKeyPem); Future<String> run(String command); Future<LineChannel> open(String command); Future<void> disconnect(); }`
  - `class DartSsh2Service implements SshService` (uses `dartssh2` `SSHClient`, `execute`).
  - `Duration backoff(int attempt)`: 1 s, 2 s, 4 s, … capped at 30 s.
  - Host key handling: trust-on-first-use. Store the fingerprint in `KeyValueStore` under `hostkey:<profileId>`; refuse to connect if it changes. Expose `onHostKeyChanged` as a thrown `HostKeyMismatch` exception.

- [ ] **Step 1: Write failing tests:** `backoff doubles then caps at 30s`; `LineChannel built from a byte stream emits complete lines (uses LineBuffer)`, tested through a fake byte stream.
- [ ] **Step 2: Run** `flutter test test/ssh/ssh_service_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** `DartSsh2Service`; `open` merges stdout bytes through `utf8.decoder` and `LineBuffer`; stderr is collected separately and exposed on error.
- [ ] **Step 4: Run** same command. Expected: PASS.
- [ ] **Step 5: Manual check (Stéphane, real host):** a throwaway `integration_test` or a debug button that runs `run('claude --version')`. Expected: prints the version. Mark "non lancé" if skipped.
- [ ] **Step 6: Commit** `feat(ssh): dartssh2 service with TOFU host keys`.

### Task 7: Session controller

**Files:**
- Create: `lib/state/session_controller.dart`, `lib/state/providers.dart`
- Test: `test/state/session_controller_test.dart` (fake `SshService`/`LineChannel` fed with spike-output lines)

**Interfaces:**
- Consumes: `SshService`, codec, `reduce`.
- Produces:
  - `class SessionController extends StateNotifier<ChatState>` (Riverpod) with constructor `(SshService ssh, {required String? sessionId, required String cwd})`.
  - `Future<void> start()`: opens the transport command from Global Constraints (`--resume` if `sessionId != null`, else `--session-id <new uuid>`), after `cd <cwd>`.
  - `void send(String text)`, `void approve()`, `void deny([String message = 'Denied from phone'])`.
  - `Future<void> reconnect()`: re-opens with `--resume`, never answers a pending request (Review Focus 2).
  - `static String buildCommand({String? resumeId, String? newId})`.
  - Providers: `sshServiceProvider`, `profileStoreProvider`, `sessionListProvider(Profile)`, `sessionControllerProvider(args)`.

- [ ] **Step 1: Write failing tests:** `buildCommand includes every flag from Global Constraints`; `send writes encodeUserMessage and marks busy`; `a can_use_tool line sets pending and approve writes the allow reply with the same request_id`; `deny writes behavior deny`; `channel closing mid-request calls connectionLost and clears pending`; `reconnect uses --resume with the session id from SystemInit`.
- [ ] **Step 2: Run** `flutter test test/state/session_controller_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the controller. Confirm the deny format on a real host (see Step 5); until confirmed, keep `encodeDeny` as specified and flag it in the PR.
- [ ] **Step 4: Run** same command. Expected: PASS.
- [ ] **Step 5: Manual check (Stéphane):** adapt `spike2-permission-roundtrip.js` to send `behavior:"deny"` and record the outcome in the spec's "Spike result" section; fix `encodeDeny` and its test if it differs.
- [ ] **Step 6: Commit** `feat(state): session controller with permission relay`.

### Task 8: UI — profiles, sessions, chat

**Files:**
- Create: `lib/ui/profiles_screen.dart`, `lib/ui/sessions_screen.dart`, `lib/ui/chat_screen.dart`, `lib/ui/permission_card.dart`
- Modify: `lib/main.dart` (routes; biometric gate with `local_auth` at app start, falling back to no gate if unavailable)
- Test: `test/ui/chat_screen_test.dart`, `test/ui/permission_card_test.dart`

**Interfaces:**
- Consumes: providers from Task 7, `SessionInfo`, `ChatState`.
- Produces: `PermissionCard({required PermissionRequest request, required VoidCallback onApprove, required VoidCallback onDeny})`, `ChatScreen({required Profile profile, SessionInfo? session, required String cwd})`.

- [ ] **Step 1: Write failing widget tests:** `PermissionCard shows tool name and command, and both buttons call their callbacks`; `ChatScreen renders user and assistant items, shows PermissionCard when pending, tool items collapsed by default`; `a recentlyActive session shows the "also open elsewhere" banner` (Review Focus 5).
- [ ] **Step 2: Run** `flutter test test/ui`. Expected: FAIL.
- [ ] **Step 3: Implement** screens: profile list + add form (name, host, port, user, paste private key); sessions list grouped by `cwd`, newest first, "New session" with a cwd text field; chat with markdown rendering, collapsed tool cards, input bar, busy indicator.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ui): profiles, sessions and chat screens`.

### Task 9: History view and end-to-end check

**Files:**
- Create: `lib/core/history.dart`
- Modify: `lib/ui/chat_screen.dart` (load history before `start()`)
- Test: `test/core/history_test.dart`

**Interfaces:**
- Produces: `List<ChatItem> parseHistory(String jsonl)` building items from a session `.jsonl` (user, assistant text, tool_use/tool_result), skipping malformed lines. The history fetch command is `cat '<path>'` through `SshService.run`, escaped with the helper from Task 4.

- [ ] **Step 1: Write failing tests:** `parses a user and assistant turn`; `skips a malformed line`; `pairs tool_use with its tool_result`. Use a few lines copied from a real `.jsonl` on the server.
- [ ] **Step 2: Run** `flutter test test/core/history_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** `parseHistory`; show a "Loading history" state while fetching and a "History unavailable" notice on error (chat still works).
- [ ] **Step 4: Run** `flutter test`. Expected: all PASS.
- [ ] **Step 5: End-to-end (Stéphane, phone + real host):** add a profile, list sessions, open one, send a message, trigger a permission (ask for `touch`), approve, kill Wi-Fi mid-turn, reconnect. Record results in the PR; mark "non lancé" for any skipped item.
- [ ] **Step 6: Commit** `feat: session history and e2e notes`.

---

## Self-review notes

- Spec coverage: profiles (T5), session list (T4), chat + streaming + tool calls + permissions (T2, T3, T7, T8), new session (T7, T8), reconnect (T6, T7), history (T9), no secrets in git (T5). Non-goals are absent by design.
- Open risks left to the builder: markdown/code-highlight package choice, exact theming, `.jsonl` format drift between Claude versions (parser must treat unknown lines as skippable), `find -printf` availability on non-GNU hosts (macOS servers would need a different listing command).
