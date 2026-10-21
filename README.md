# rclone — Omarchy plugin

Your rclone mounts in the Omarchy bar.

| Icon | Meaning |
|---|---|
| Cloud | Every mount is up to date |
| Cloud with arrow and a number | That many files are still uploading |
| Crossed-out cloud, urgent colour | A mount stopped answering |
| Dimmed cloud | Nothing is mounted |

Hover to see each mount. Click to open `~/Cloud` in Nautilus. Right-click to refresh.

The plugin only watches; rclone does the work. Each mount is a `rclone mount` run by the systemd user unit [`systemd/rclone@.service`](systemd/rclone@.service), which also opens rclone's remote control on `$XDG_RUNTIME_DIR/rclone/<remote>.sock`. The plugin finds mounts there and asks each one for `vfs/stats`, which rclone answers without credentials.

## Install

```bash
bin/install
```

This installs rclone, copies the mount unit to `~/.config/systemd/user/`, copies the plugin to `~/.config/omarchy/plugins/renuo.rclone/` and puts it in the bar.

## Mount a remote

Any rclone backend works. Create the remote with rclone and start its mount under the same name, for example Google Drive and OneDrive:

```bash
rclone config create gdrive drive
rclone config create onedrive onedrive
systemctl --user enable --now rclone@gdrive rclone@onedrive
```

Each `config create` opens the browser to log in. Use plain `rclone config` for backends with more questions, for instance a OneDrive account with several drives. Keep remote names to letters, digits, `_`, `-` and `.`, since the name is also the systemd instance.

The remote is mounted at `~/Cloud/<remote>` with a full VFS cache capped at 20G. Every rclone flag can also be set as an `RCLONE_*` environment variable, so you can change one remote with `systemctl --user edit rclone@gdrive`:

```ini
[Service]
Environment=RCLONE_VFS_CACHE_MAX_SIZE=50G
```

## Using the mount in Nautilus

Nautilus treats an rclone mount as a local folder, so:

- **Trash lands on the remote.** Nautilus creates `.Trash-1000` at the mount root, where trashed files keep using quota. Delete with Shift+Delete.
- **Browsing downloads.** Thumbnails, folder item counts and search read the files. The cache means each file is fetched once.
- **Copies finish before the upload does.** Nautilus is done once a file is in rclone's cache. The widget shows what is still uploading. Shutting down then cancels uploads in progress, and rclone restarts them on the next start.
- **Changes made elsewhere** need F5.
- **Unmounting from the sidebar** stops the mount until `systemctl --user start rclone@<remote>`.

## Remove

```bash
systemctl --user disable --now rclone@gdrive rclone@onedrive
omarchy plugin remove renuo.rclone
rm ~/.config/systemd/user/rclone@.service
```

## Development

```bash
bin/setup   # checks the tools bin/check needs
bin/check   # validates the manifest and the unit, runs the tests
bin/install # installs into the shell, which hot-reloads it
```
