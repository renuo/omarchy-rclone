setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../status.sh"
  PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
  export FAKE_RCLONE_ARGS="$BATS_TEST_TMPDIR/rclone-args"
  export FAKE_RCLONE_ANSWERS="$BATS_TEST_TMPDIR/answers"
  mkdir -p "$XDG_RUNTIME_DIR/rclone" "$FAKE_RCLONE_ANSWERS"
  : >"$FAKE_RCLONE_ARGS"
}

# A mount whose socket answers vfs/stats with the given JSON.
mount_answering() {
  touch "$XDG_RUNTIME_DIR/rclone/$1.sock"
  printf '%s' "$2" >"$FAKE_RCLONE_ANSWERS/$1.json"
}

@test "prints an empty array when nothing is mounted" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "prints an empty array when the socket directory does not exist" {
  rmdir "$XDG_RUNTIME_DIR/rclone"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "reports each mount under the name of its socket" {
  mount_answering gdrive '{"diskCache":{"uploadsInProgress":1,"uploadsQueued":2}}'
  mount_answering onedrive '{"diskCache":{"uploadsInProgress":0,"uploadsQueued":0}}'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | {remote, ok, queued: .stats.diskCache.uploadsQueued}]' <<<"$output")" = \
    '[{"remote":"gdrive","ok":true,"queued":2},{"remote":"onedrive","ok":true,"queued":0}]' ]
}

@test "asks each socket for vfs/stats" {
  mount_answering gdrive '{}'
  run bash "$SCRIPT"
  [ "$(cat "$FAKE_RCLONE_ARGS")" = "rc --unix-socket $XDG_RUNTIME_DIR/rclone/gdrive.sock vfs/stats" ]
}

@test "marks a socket nobody answers on as not ok and keeps the others" {
  touch "$XDG_RUNTIME_DIR/rclone/stale.sock"
  mount_answering gdrive '{}'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'map({remote, ok})' <<<"$output")" = '[{"remote":"gdrive","ok":true},{"remote":"stale","ok":false}]' ]
}

@test "marks an answer that is not JSON as not ok" {
  mount_answering gdrive 'Failed to rc: oops'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = '[{"remote":"gdrive","ok":false}]' ]
}

@test "marks every mount as not ok when rclone is not installed" {
  touch "$XDG_RUNTIME_DIR/rclone/gdrive.sock"
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  for tool in bash jq timeout basename; do ln -s "$(command -v "$tool")" "$bin/$tool"; done
  run env PATH="$bin" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = '[{"remote":"gdrive","ok":false}]' ]
}

@test "ignores files in the socket directory that are not sockets by name" {
  touch "$XDG_RUNTIME_DIR/rclone/notes.txt"
  run bash "$SCRIPT"
  [ "$output" = "[]" ]
}
