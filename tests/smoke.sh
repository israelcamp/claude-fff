#!/bin/bash
# Isolated checks: no network, profile changes, or dependency installs outside /tmp.
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-fff-test.XXXXXX")
trap 'rm -rf -- "$test_dir"' EXIT
export CLAUDE_FFF_INSTALL_DIR="$test_dir/app with spaces"
export CLAUDE_FFF_BIN_DIR="$test_dir/bin with spaces"
export TEST_ARGS="$test_dir/args"
export TEST_SERVER_PID="$test_dir/server.pid"
export REAL_NODE=$(command -v node)
mkdir -p "$test_dir/mocks"
cat > "$test_dir/mocks/node" <<'EOF'
#!/bin/bash
case "$1" in
  --input-type=module) exit 0 ;; # Native import is tested separately with real npm.
  */server.mjs)
    echo "$$" > "$TEST_SERVER_PID"
    if [[ "${TEST_SERVER_FAIL:-}" = 1 ]]; then
      echo 'EADDRINUSE' >&2
      exit 1
    fi
    echo 'FFF search ready on http://127.0.0.1:43871'
    trap 'exit 0' TERM INT
    while :; do sleep 0.1; done ;;
  *) exec "$REAL_NODE" "$@" ;;
esac
EOF
cat > "$test_dir/mocks/npm" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$test_dir/mocks/claude" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" > "$TEST_ARGS"
exit "${TEST_CLAUDE_EXIT:-0}"
EOF
chmod +x "$test_dir/mocks/"*
export PATH="$test_dir/mocks:$PATH"

bash "$repo/install.sh" --no-shell > "$test_dir/install.log"
bash "$repo/install.sh" --no-shell >> "$test_dir/install.log"
[[ -x "$CLAUDE_FFF_BIN_DIR/claude-fff" ]]
[[ -f "$CLAUDE_FFF_INSTALL_DIR/server.mjs" ]]
"$CLAUDE_FFF_BIN_DIR/claude-fff" --resume 'argument with spaces'
"$REAL_NODE" --input-type=module -e '
  import fs from "node:fs";
  import assert from "node:assert/strict";
  const args = fs.readFileSync(process.env.TEST_ARGS, "utf8").split("\0").slice(0, -1);
  assert.equal(args[0], "--settings");
  assert.equal(JSON.parse(args[1]).fileSuggestion.type, "command");
  assert.match(JSON.parse(args[1]).fileSuggestion.command, /127\.0\.0\.1:43871\/search/);
  assert.deepEqual(args.slice(2), ["--resume", "argument with spaces"]);
'
! kill -0 "$(cat "$TEST_SERVER_PID")" 2>/dev/null

status=0
TEST_CLAUDE_EXIT=7 "$CLAUDE_FFF_BIN_DIR/claude-fff" || status=$?
[[ "$status" = 7 ]]
! kill -0 "$(cat "$TEST_SERVER_PID")" 2>/dev/null

rm "$TEST_ARGS"
if TEST_SERVER_FAIL=1 "$CLAUDE_FFF_BIN_DIR/claude-fff" > "$test_dir/failure.log" 2>&1; then
  echo 'Expected server startup failure' >&2; exit 1
fi
[[ ! -e "$TEST_ARGS" ]]
grep -q EADDRINUSE "$test_dir/failure.log"

printf '#!/bin/bash\n# unrelated command\n' > "$CLAUDE_FFF_BIN_DIR/claude-fff"
if bash "$repo/install.sh" --no-shell > "$test_dir/collision.log" 2>&1; then
  echo 'Expected refusal to overwrite unrelated command' >&2; exit 1
fi
grep -q 'unrelated command' "$CLAUDE_FFF_BIN_DIR/claude-fff"
echo 'Installer and launcher smoke checks passed.'
