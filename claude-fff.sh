#!/bin/bash

if ! command -v node >/dev/null || ! command -v claude >/dev/null || ! command -v curl >/dev/null; then
  echo "Node.js, Claude Code, and curl are required. Run bash install.sh first." >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd) || exit 1
log=$(mktemp "${TMPDIR:-/tmp}/claude-fff.XXXXXX") || exit 1

node "$script_dir/server.mjs" "$PWD" >"$log" 2>&1 &
fff_pid=$!

cleanup() {
  kill "$fff_pid" 2>/dev/null || true
  wait "$fff_pid" 2>/dev/null || true
  rm -f "$log"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

echo "Starting FFF search for $PWD..." >&2
deadline=$((SECONDS + 40))

while ! grep -q '^FFF search ready on ' "$log"
do
  if ! kill -0 "$fff_pid" 2>/dev/null; then
    cat "$log" >&2
    exit 1
  fi

  if (( SECONDS >= deadline )); then
    echo "FFF server did not become ready." >&2
    cat "$log" >&2
    exit 1
  fi

  sleep 0.1
done

command claude --settings '{"fileSuggestion":{"type":"command","command":"curl --silent --show-error --fail --max-time 4 --header '\''Content-Type: application/json'\'' --data-binary @- http://127.0.0.1:43871/search"}}' "$@"
