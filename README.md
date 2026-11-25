# claude-mobile

Flutter SSH chat client for Claude Code sessions (see `docs/superpowers/specs`).

No secrets in git: SSH keys live only in the phone's secure storage.

## Install on a phone

Signed APKs are published as [GitHub releases](https://github.com/stephaneHerraiz/claude-mobile/releases),
one per version merged into `main`. To get updates automatically, add this repository in
[Obtainium](https://github.com/ImranR98/Obtainium) (source: GitHub,
`https://github.com/stephaneHerraiz/claude-mobile`). Each release notes the SHA-256 of
the signing certificate.

A build signed by another key (a debug build from a PC or the Claude pod) cannot update
the released app: Android asks to uninstall first, which wipes the SSH keys and profiles.
