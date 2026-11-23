#!/usr/bin/env bash
# Starts a throwaway sshd on 127.0.0.1 with a fake `claude` on its PATH and
# prints the variables test/live/ssh_live_test.dart reads.
#
#   eval "$(tool/live_rig/start.sh /some/empty/dir)"
#   flutter test test/live
#   kill "$(cat /some/empty/dir/sshd.pid)"
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dir="${1:?usage: start.sh <empty work dir> [port]}"
port="${2:-2222}"
mkdir -p "$dir/home/bin" "$dir/home/work dir" \
  "$dir/home/.claude/projects/-tmp-demo"
ssh-keygen -q -t ed25519 -N '' -f "$dir/host_key"
ssh-keygen -q -t ed25519 -N '' -f "$dir/client_key"
install -m 755 "$here/fake_claude.py" "$dir/home/bin/claude"
# Only a login shell finds `claude`: that is the case the app must handle.
echo 'export PATH="$HOME/bin:$PATH"' > "$dir/home/.profile"
printf '%s\n' \
  '{"type":"user","cwd":"/tmp/demo","sessionId":"11111111-1111-4111-8111-111111111111","message":{"role":"user","content":"Fix the login bug"}}' \
  '{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"On it."}]}}' \
  > "$dir/home/.claude/projects/-tmp-demo/11111111-1111-4111-8111-111111111111.jsonl"
cat > "$dir/sshd_config" <<CONF
Port $port
ListenAddress 127.0.0.1
HostKey $dir/host_key
PidFile $dir/sshd.pid
AuthorizedKeysFile $dir/client_key.pub
PasswordAuthentication no
UsePAM no
StrictModes no
SetEnv HOME=$dir/home
CONF
"$(command -v sshd || echo /usr/sbin/sshd)" -f "$dir/sshd_config" -E "$dir/sshd.log"
echo "export LIVE_SSH_HOST=127.0.0.1 LIVE_SSH_PORT=$port LIVE_SSH_USER=$(id -un)"
echo "export LIVE_SSH_KEY='$dir/client_key' LIVE_SSH_CWD='$dir/home/work dir'"
