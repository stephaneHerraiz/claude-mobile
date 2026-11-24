# CLAUDE.md

Flutter SSH chat client for Claude Code sessions. The app opens `claude -p` with
stream-json over an SSH exec channel; it is not a terminal and not a claude.ai client.
Design and v1 plan: `docs/superpowers/specs/` and `docs/superpowers/plans/`.

## Branches: where to start

**The default branch `main` is behind and must not be a base.** Work is stacked: PRs
target the previous feature branch, and have been merged into each other, never into
`main`. The integration branch (version in progress) is **`feat/v1`**: branch from
`origin/feat/v1` and open the PR with `--base feat/v1`.

When this changes (`feat/v1` finally merged into `main`, or a `feat/v2` started), update
this section in the same PR.

Do not work inside an existing checkout: it may hold uncommitted work. Use
`git worktree add -b <type>/<subject> ../claude-mobile-<subject> origin/feat/v1`.

## Layout

- `lib/core/`: pure Dart (events, codec, chat state reducer, history, session listing).
- `lib/ssh/`: `SshService` (`DartSsh2Service`, `GuardedSsh` with timeouts), profiles, keys.
- `lib/state/`: `SessionController` (one Claude session over one channel), loaders,
  Riverpod providers.
- `lib/storage/`: profiles and secrets; SSH keys live only in the phone's secure storage.
- `lib/ui/`: screens and widgets (`ChatView` is the conversation, `terminal_widgets.dart`
  the terminal look).
- `test/support/fakes.dart`: `FakeSsh`/`FakeChannel`, used by almost every test.

## Commands

```bash
flutter pub get
flutter analyze
flutter test                 # unit and widget tests
flutter test test/live       # skipped unless LIVE_SSH_HOST is set
tool/live_rig/start.sh       # prints the variables for a local rig (fake_claude.py)
```

Run analyze and the tests concerned before committing. Flutter is **not installed in the
Claude pod**: from there these cannot run, so say "not run" in the PR.

## Rules

- No secret in git: no key, passphrase or host list. Keys go through the secure storage.
- Every wait on the network is bounded (`GuardedSsh`); keep it that way for new calls.
- Never answer a permission request on the user's behalf; a lost link voids what was
  pending (`turnAbandoned`).
