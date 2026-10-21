#!/bin/bash

# Prints one JSON array with an entry per rclone mount whose remote control
# socket sits in $XDG_RUNTIME_DIR/rclone/, where rclone@.service puts it.

set -euo pipefail

describe() {
  local socket=$1 remote stats
  remote=$(basename "$socket" .sock)
  if stats=$(timeout 4 rclone rc --unix-socket "$socket" vfs/stats 2>/dev/null) &&
    jq -cn --arg remote "$remote" --argjson stats "$stats" '{remote: $remote, ok: true, stats: $stats}' 2>/dev/null; then
    return
  fi
  jq -cn --arg remote "$remote" '{remote: $remote, ok: false}'
}

shopt -s nullglob
for socket in "${XDG_RUNTIME_DIR:?}"/rclone/*.sock; do
  describe "$socket"
done | jq -cs .
