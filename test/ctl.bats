setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../ctl.sh"
  PATH="$BATS_TEST_DIRNAME/fakebin:$PATH"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export FAKE_RCLONE_ARGS="$BATS_TEST_TMPDIR/rclone-args"
  export FAKE_SYSTEMCTL_ARGS="$BATS_TEST_TMPDIR/systemctl-args"
  export FAKE_GUM_ARGS="$BATS_TEST_TMPDIR/gum-args"
  export FAKE_GUM_INPUTS="$BATS_TEST_TMPDIR/gum-inputs"
  export FAKE_EDITOR_ARGS="$BATS_TEST_TMPDIR/editor-args"
  export FAKE_SYSTEMD="$BATS_TEST_TMPDIR/systemd"
  export FAKE_RCLONE_DUMP='{}'
  export FAKE_RCLONE_DUMP_FILE="$BATS_TEST_TMPDIR/dump.json"
  mkdir -p "$FAKE_SYSTEMD"
  : >"$FAKE_RCLONE_ARGS"
  : >"$FAKE_SYSTEMCTL_ARGS"
  : >"$FAKE_GUM_ARGS"
  : >"$FAKE_EDITOR_ARGS"
}

GDRIVE='{"gdrive":{"type":"drive","client_id":"886583002273-abc.apps.googleusercontent.com","client_secret":"SECRET","scope":"drive","token":"{\"access_token\":\"SECRET\"}"}}'
ONEDRIVE='{"onedrive":{"type":"onedrive","drive_type":"business","drive_id":"b!x","token":"SECRET"}}'

unit_state() {
  echo "$3" >"$FAKE_SYSTEMD/rclone@$1.service.$2"
}

@test "remotes lists every configured remote with its mount unit" {
  export FAKE_RCLONE_DUMP=$(jq -cn --argjson a "$GDRIVE" --argjson b "$ONEDRIVE" '$a + $b')
  unit_state gdrive enabled enabled
  unit_state gdrive active active
  run bash "$SCRIPT" remotes
  [ "$status" -eq 0 ]
  [ "$output" = '[{"name":"gdrive","type":"drive","clientId":"886583002273-abc.apps.googleusercontent.com","driveType":"","enabled":true,"active":true},{"name":"onedrive","type":"onedrive","clientId":"","driveType":"business","enabled":false,"active":false}]' ]
}

@test "remotes never passes on a secret or token" {
  export FAKE_RCLONE_DUMP=$(jq -cn --argjson a "$GDRIVE" --argjson b "$ONEDRIVE" '$a + $b')
  run bash "$SCRIPT" remotes
  [[ $output != *SECRET* ]]
}

@test "remotes prints an empty list without any remote" {
  run bash "$SCRIPT" remotes
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "remotes prints an empty list when rclone cannot read its config" {
  export FAKE_RCLONE_DUMP=""
  run bash "$SCRIPT" remotes
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "mount on enables and starts the remote's unit quietly" {
  run bash "$SCRIPT" mount gdrive on
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  grep -qx -- '--user enable --now rclone@gdrive.service' "$FAKE_SYSTEMCTL_ARGS"
}

@test "mount off disables and stops the remote's unit" {
  run bash "$SCRIPT" mount gdrive off
  [ "$status" -eq 0 ]
  grep -qx -- '--user disable --now rclone@gdrive.service' "$FAKE_SYSTEMCTL_ARGS"
}

@test "mount prints systemd's complaint when it fails" {
  export FAKE_SYSTEMCTL_FAIL="Failed to enable unit: Unit file rclone@.service does not exist."
  run bash "$SCRIPT" mount gdrive on
  [ "$output" = "$FAKE_SYSTEMCTL_FAIL" ]
}

@test "mount refuses a name that cannot be a systemd instance" {
  run bash "$SCRIPT" mount "my drive" on
  [ "$status" -eq 2 ]
  [[ $output == "Not a usable remote name"* ]]
  [ ! -s "$FAKE_SYSTEMCTL_ARGS" ]
}

@test "login creates gdrive with the OAuth client it asks for" {
  printf '%s\n' 886583002273-abc.apps.googleusercontent.com s3cret >"$FAKE_GUM_INPUTS"
  run bash "$SCRIPT" login gdrive
  [ "$status" -eq 0 ]
  grep -qx 'config create gdrive drive client_id=886583002273-abc.apps.googleusercontent.com client_secret=s3cret scope=drive' "$FAKE_RCLONE_ARGS"
  grep -q -- '--password' <(sed -n 2p "$FAKE_GUM_ARGS")
}

@test "login hides the token rclone prints after creating a remote" {
  printf '%s\n' id secret >"$FAKE_GUM_INPUTS"
  run bash "$SCRIPT" login gdrive
  [[ $output != *SECRET-TOKEN* ]]
}

@test "login gives up when no client ID is entered" {
  : >"$FAKE_GUM_INPUTS"
  run bash "$SCRIPT" login gdrive
  [ "$status" -eq 1 ]
  ! grep -q 'config create' "$FAKE_RCLONE_ARGS"
}

@test "login creates onedrive with rclone's defaults and names the drive it picked" {
  export FAKE_RCLONE_CREATED="$ONEDRIVE"
  run bash "$SCRIPT" login onedrive
  [ "$status" -eq 0 ]
  grep -qx 'config create onedrive onedrive' "$FAKE_RCLONE_ARGS"
  [[ $output == *"Connected the business drive"* ]]
}

@test "login reconnects a remote that exists already" {
  export FAKE_RCLONE_DUMP="$GDRIVE"
  run bash "$SCRIPT" login gdrive
  [ "$status" -eq 0 ]
  grep -qx 'config reconnect gdrive:' "$FAKE_RCLONE_ARGS"
  ! grep -q 'config create' "$FAKE_RCLONE_ARGS"
}

@test "login sends unknown new remotes to rclone config" {
  run bash "$SCRIPT" login dropbox
  [ "$status" -eq 2 ]
  [[ $output == *"rclone config"* ]]
}

@test "client swaps the OAuth client and logs in again" {
  export FAKE_RCLONE_DUMP="$GDRIVE"
  printf '%s\n' new-id new-secret >"$FAKE_GUM_INPUTS"
  run bash "$SCRIPT" client gdrive
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_RCLONE_ARGS")" = "config dump
config update gdrive client_id=new-id client_secret=new-secret
config reconnect gdrive:" ]
}

@test "client refuses a remote that does not exist" {
  run bash "$SCRIPT" client gdrive
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_GUM_ARGS" ]
}

@test "mount-settings starts the drop-in from the commented template" {
  run bash "$SCRIPT" mount-settings gdrive
  [ "$status" -eq 0 ]
  local file="$XDG_CONFIG_HOME/systemd/user/rclone@gdrive.service.d/override.conf"
  cmp "$file" "$BATS_TEST_DIRNAME/../templates/mount-override.conf"
  [ "$(cat "$FAKE_EDITOR_ARGS")" = "--inline $file" ]
  grep -qx -- '--user daemon-reload' "$FAKE_SYSTEMCTL_ARGS"
}

@test "mount-settings keeps a drop-in that exists" {
  local file="$XDG_CONFIG_HOME/systemd/user/rclone@gdrive.service.d/override.conf"
  mkdir -p "${file%/*}"
  echo "[Service]" >"$file"
  run bash "$SCRIPT" mount-settings gdrive
  [ "$(cat "$file")" = "[Service]" ]
}

@test "mount-settings restarts a running mount once confirmed" {
  unit_state gdrive active active
  run bash "$SCRIPT" mount-settings gdrive
  grep -qx -- '--user restart rclone@gdrive.service' "$FAKE_SYSTEMCTL_ARGS"
}

@test "mount-settings leaves a running mount alone when declined" {
  unit_state gdrive active active
  FAKE_GUM_CONFIRM=no run bash "$SCRIPT" mount-settings gdrive
  [ "$status" -eq 0 ]
  ! grep -q restart "$FAKE_SYSTEMCTL_ARGS"
}

@test "mount-settings does not offer a restart for a stopped mount" {
  run bash "$SCRIPT" mount-settings gdrive
  [ ! -s "$FAKE_GUM_ARGS" ]
}

@test "an unknown command prints usage" {
  run bash "$SCRIPT" frobnicate
  [ "$status" -eq 2 ]
  [[ $output == usage:* ]]
}
