# rclone — Omarchy plugin

Your rclone mounts in the Omarchy bar.

| Icon | Meaning |
|---|---|
| Cloud | Every mount is up to date |
| Cloud with arrow and a number | That many files are still uploading |
| Crossed-out cloud, urgent colour | A mount stopped answering |
| Dimmed cloud | Nothing is mounted |

Hover to see each mount. Click for the panel, middle-click to open `~/Cloud` in Nautilus, right-click to refresh.

The plugin only watches and guides; rclone does the work. Each mount is a `rclone mount` run by the systemd user unit [`systemd/rclone@.service`](systemd/rclone@.service), which also opens rclone's remote control on `$XDG_RUNTIME_DIR/rclone/<remote>.sock`. The plugin finds mounts there and asks each one for `vfs/stats`, which rclone answers without credentials.

## Install

```bash
bin/install
```

This installs rclone, copies the mount unit to `~/.config/systemd/user/`, copies the plugin to `~/.config/omarchy/plugins/renuo.rclone/` and puts it in the bar.

## Set up a remote

The panel has a card for every rclone remote, and a guide for `gdrive` (Google Drive) and `onedrive` (OneDrive) while they are missing. Whatever needs typing runs in Omarchy's floating terminal through [`ctl.sh`](ctl.sh):

- **Google Drive** needs an OAuth client of your own, since rclone's shared one is being retired during 2026. The guide opens the Google Cloud console's credentials page; copy the ID and secret of a "Desktop app" client. Once `gdrive` exists, its card names the Google Cloud project the client belongs to and links its credentials and its publishing status. Keep that status "In production": while it is "Testing", Google ends the login after 7 days. A new Drive remote is pointed at the same project.
- **OneDrive** works with rclone's own client. Log in with the Microsoft account, and rclone connects that account's own drive. A work account may need an admin to approve rclone first. For a SharePoint library, use *rclone config* at the bottom of the panel.

Then switch on the card's mount. That enables `rclone@<remote>`, so it mounts again after every login. *Log in again* renews an expired login.

Any other backend works too: create it with *rclone config* and it gets a card. Keep remote names to letters, digits, `_`, `-` and `.`, since the name is also the systemd instance.

### Mount settings

A remote is mounted at `~/Cloud/<remote>` with a full VFS cache capped at 20G. *Mount settings* opens `~/.config/systemd/user/rclone@<remote>.service.d/override.conf` in your editor, started from [a commented template](templates/mount-override.conf). Every rclone flag can be set there as an `RCLONE_*` variable:

```ini
[Service]
Environment=RCLONE_VFS_CACHE_MAX_SIZE=50G
```

After the editor closes, systemd reloads, and a running mount restarts if you agree; uploads in progress then start over.

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
