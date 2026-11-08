#!/bin/bash

# What the panel asks of rclone and systemd. `remotes` prints JSON and `mount`
# prints nothing unless it fails; the panel shows that text as the error.
# `login`, `client`, `mount-settings` and `config` talk to a person and run in
# a terminal the panel opens.

set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

GDRIVE_HELP='Google Drive needs an OAuth client of your own, rclone'"'"'s shared one is being
retired. Open the Google Cloud project you made it in, under APIs & Services >
Credentials, and copy the client ID and secret of its "Desktop app" client:

  https://console.cloud.google.com/apis/credentials

No project yet? https://rclone.org/drive/#making-your-own-client-id
'

usage() {
  echo "usage: ctl.sh remotes | mount <remote> on|off | login <remote> | client <remote> | mount-settings <remote> | config" >&2
  exit 2
}

# The name becomes a systemd instance and a folder under ~/Cloud.
require_name() {
  [[ ${1:-} =~ ^[A-Za-z0-9_.-]+$ ]] || {
    echo "Not a usable remote name: '${1:-}'. Use letters, digits, _, - and ."
    exit 2
  }
}

dump() {
  local config
  config=$(rclone config dump 2>/dev/null) && jq -e 'type == "object"' <<<"$config" >/dev/null 2>&1 || config='{}'
  printf '%s' "$config"
}

has_remote() {
  dump | jq -e --arg name "$1" 'has($name)' >/dev/null
}

# Only fields the panel shows leave this function; tokens and secrets stay in
# rclone.conf.
remotes() {
  local config name enabled active
  config=$(dump)
  jq -r 'keys[]' <<<"$config" | while IFS= read -r name; do
    enabled=$(systemctl --user is-enabled "rclone@$name.service" 2>/dev/null) || true
    active=$(systemctl --user is-active "rclone@$name.service" 2>/dev/null) || true
    jq -c --arg name "$name" --arg enabled "$enabled" --arg active "$active" '.[$name] | {
      name: $name,
      type: (.type // ""),
      clientId: (.client_id // ""),
      driveType: (.drive_type // ""),
      enabled: ($enabled == "enabled"),
      active: ($active == "active")
    }' <<<"$config"
  done | jq -cs .
}

mount_remote() {
  local name=$1 out
  require_name "$name"
  case ${2:-} in
  on) out=$(systemctl --user enable --now "rclone@$name.service" 2>&1) || echo "$out" ;;
  off) out=$(systemctl --user disable --now "rclone@$name.service" 2>&1) || echo "$out" ;;
  *) usage ;;
  esac
}

ask_client() {
  echo "$GDRIVE_HELP"
  client_id=$(gum input --width 80 --placeholder "Client ID, ends in .apps.googleusercontent.com")
  [[ -n $client_id ]] || exit 1
  client_secret=$(gum input --password --width 80 --placeholder "Client secret")
  [[ -n $client_secret ]] || exit 1
}

# config create and update print the whole remote, token included; only
# rclone's own messages on stderr, among them the login link, are worth seeing.
login() {
  local name=$1
  require_name "$name"
  if has_remote "$name"; then
    rclone config reconnect "$name:"
    return
  fi
  case $name in
  gdrive)
    ask_client
    rclone config create gdrive drive client_id="$client_id" client_secret="$client_secret" scope=drive >/dev/null
    ;;
  onedrive)
    echo "Log in with the Microsoft account whose OneDrive you want in ~/Cloud/onedrive."
    echo
    rclone config create onedrive onedrive >/dev/null
    echo "Connected the $(dump | jq -r '.onedrive.drive_type // "default"') drive of that account."
    ;;
  *)
    echo "No guided login for '$name'. Create it with: rclone config"
    exit 2
    ;;
  esac
  echo "Logged in. Switch on the mount in the panel to see it in ~/Cloud/$name."
}

client() {
  local name=$1
  require_name "$name"
  has_remote "$name" || {
    echo "There is no remote called '$name' yet."
    exit 2
  }
  ask_client
  rclone config update "$name" client_id="$client_id" client_secret="$client_secret" >/dev/null
  echo "Log in again, so the new client gets a token of its own."
  rclone config reconnect "$name:"
}

mount_settings() {
  local name=$1 file
  require_name "$name"
  file="$UNIT_DIR/rclone@$name.service.d/override.conf"
  if [[ ! -f $file ]]; then
    mkdir -p "${file%/*}"
    cp "$TEMPLATE_DIR/mount-override.conf" "$file"
  fi
  omarchy-launch-editor --inline "$file"
  systemctl --user daemon-reload
  if systemctl --user -q is-active "rclone@$name.service" &&
    gum confirm "Restart the $name mount so the settings apply? Uploads in progress start over."; then
    systemctl --user restart "rclone@$name.service"
  fi
}

case ${1:-} in
remotes) remotes ;;
mount) mount_remote "${2:-}" "${3:-}" ;;
login) login "${2:-}" ;;
client) client "${2:-}" ;;
mount-settings) mount_settings "${2:-}" ;;
config) rclone config ;;
*) usage ;;
esac
