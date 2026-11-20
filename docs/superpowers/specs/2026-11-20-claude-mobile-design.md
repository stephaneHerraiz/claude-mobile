# claude-mobile — design

Status: DRAFT, awaiting approval from Stéphane. Nothing is built yet.

## Intent
A Flutter phone app that is an SSH client dedicated to Claude Code. Stéphane
connects to his "pro" and "perso" machines, sees the Claude sessions living
there, and chats in them from his phone with a real chat UI (not a terminal).

## Goals
- Two (or more) connection profiles (pro, perso): host, port, user, SSH key.
- List sessions per profile, grouped by project directory, newest first.
- Open a session, read its history, send messages, see streamed replies,
  tool calls (collapsed by default) and approve/deny permission requests.
- Start a new session in a chosen directory.
- Survive phone sleep / network change: reconnect and resume transparently.
- Public repo: zero secrets in git.

## Non-goals (v1)
- Attaching to a TUI session already running in tmux/herdr (see Approaches).
- Push notifications, voice, file browser/editor, diff viewer.
- Any claude.ai API / account integration. Access is SSH only.
- Port forwarding or general-purpose SSH terminal.

## Anti-goals
- Leaking or storing a private key outside the phone's secure storage.
- Becoming a generic SSH client; every feature must serve Claude sessions.

## Constraints
- Flutter (Stéphane's choice). SSH via `dartssh2`; no native SSH code.
- iOS kills background sockets: all state lives server-side, the app only
  holds a transient connection.
- Server side needs only the `claude` CLI on PATH and an SSH login; no agent
  or daemon to install.

## Approaches considered
- A. Raw terminal (dartssh2 + xterm) with a mobile key bar. Fast, faithful,
  poor reading experience on a phone.
- B. Structured chat over `claude -p` stream-json. **Chosen by Stéphane.**
- C. A first then B. Recommended by me; Stéphane preferred B directly.

## Design (B)
Transport: one SSH connection per profile; each open session is an SSH exec
channel running
`claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --resume <session-id>`
(new session: `--session-id <uuid>`, in the chosen `cwd`). The app writes
user messages as JSON lines to stdin and parses JSON lines from stdout.
(Flags confirmed present in `claude --help`, v2.1.329.)

Session discovery: over SSH exec, list `~/.claude/projects/*/*.jsonl`
(directory name encodes the cwd; file name is the session id; mtime for
ordering; first user message as title). History view is rendered by
reading the .jsonl through SSH.

Permissions: `claude --help` (v2.1.329) shows `--permission-prompts host`
(default with --print): permission prompts are answered by "the SDK host or
--permission-prompt-tool". Preferred path: the app itself is the host. In
stream-json mode Claude sends a permission request on stdout and waits for
the app's allow/deny reply on stdin, so no MCP server is needed. Fallback:
`--permission-prompt-tool` with a small MCP server. Last resort: a
per-session `--permission-mode` picker. Existing allow/deny rules and the
mode are evaluated first; only undecided requests reach the phone.
The exact message format is UNVERIFIED and is the first thing the spike checks.

Layers (Dart): `ssh/` (connection, reconnect, exec channel),
`claude/` (stream-json codec, session listing), `state/` (per-session
event reducer), `ui/` (profiles, sessions list, chat). Keys in
`flutter_secure_storage`, biometric unlock via `local_auth`.

Known limit of B: a session currently open in an interactive TUI is not
live-shared; the phone resumes the same session id from its .jsonl, so
two writers at once can fork the history. The app warns, it doesn't lock.

## Decisions made by me (to check)
- Repo `stephaneHerraiz/claude-mobile`, public.
- Android first, iOS built later from the same code (no Mac verified).
- State management: Riverpod.
- Pro/perso = just profile names; no behavioural difference.
- Password auth not supported; key-based only.

## Left to the builder
Chat rendering details, markdown/code highlighting library, theming,
reconnect backoff, exact .jsonl title extraction, MCP permission relay
implementation, test strategy (codec and reducer are pure Dart, unit-test them first).

## First step after approval
A throwaway spike: Dart CLI that SSHes to a host, runs the stream-json
command and prints parsed events, including one permission round-trip.
Its outcome decides the permissions design above.
