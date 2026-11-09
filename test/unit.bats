setup() {
  UNIT="$BATS_TEST_DIRNAME/../systemd/rclone@.service"
}

# rclone lets a command-line flag win over its RCLONE_* variable, so a default
# written as a flag could never be changed from a drop-in.
@test "leaves the cache defaults to variables a drop-in can override" {
  run grep -E -- '--vfs-cache-(mode|max-size)' "$UNIT"
  [ "$status" -eq 1 ]
  grep -qx 'Environment=RCLONE_VFS_CACHE_MODE=full' "$UNIT"
  grep -qx 'Environment=RCLONE_VFS_CACHE_MAX_SIZE=20G' "$UNIT"
}
