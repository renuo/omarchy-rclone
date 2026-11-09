.pragma library

// Nerd Font Material Design glyphs, as UTF-16 surrogate pairs like the shell's own.
var GLYPHS = {
  none: "󰅣", // cloud-outline
  idle: "󰅟", // cloud
  uploading: "󰅧", // cloud-upload
  unreachable: "󰅤" // cloud-off-outline
}

function pathFromUrl(url) {
  var s = String(url || "")
  if (s.indexOf("file://") === 0) s = s.substring(7)
  try {
    return decodeURIComponent(s)
  } catch (e) {
    return s
  }
}

function parseMounts(raw) {
  var entries
  try {
    entries = JSON.parse(String(raw || ""))
  } catch (e) {
    return []
  }
  return Array.isArray(entries) ? entries.map(toMount) : []
}

function toMount(entry) {
  var remote = String((entry && entry.remote) || "")
  if (!entry || entry.ok !== true) return { remote: remote, state: "unreachable", pending: 0 }
  var pending = pendingUploads(entry.stats)
  return { remote: remote, state: pending > 0 ? "uploading" : "idle", pending: pending }
}

function pendingUploads(stats) {
  var cache = stats && stats.diskCache
  if (!cache) return 0
  return (Number(cache.uploadsInProgress) || 0) + (Number(cache.uploadsQueued) || 0)
}

function summary(mounts) {
  var pending = 0
  var unreachable = false
  for (var i = 0; i < mounts.length; i++) {
    pending += mounts[i].pending
    if (mounts[i].state === "unreachable") unreachable = true
  }
  var state = "idle"
  if (mounts.length === 0) state = "none"
  else if (unreachable) state = "unreachable"
  else if (pending > 0) state = "uploading"
  return { state: state, pending: pending }
}

function glyph(state) {
  return GLYPHS[state] || GLYPHS.none
}

// Single pass, so a "%2" or "$&" inside a remote name stays literal text.
function format(template, values) {
  return String(template).replace(/%(\d)/g, function (match, n) {
    var value = values[Number(n) - 1]
    return value === undefined ? match : String(value)
  })
}

function statusText(mount, strings, formatNumber) {
  if (mount.state === "unreachable") return strings.t("status.unreachable")
  if (mount.state === "uploading")
    return format(strings.tn("status.uploading", mount.pending), [formatNumber(mount.pending)])
  return strings.t("status.idle")
}

function tooltip(mounts, strings, formatNumber) {
  if (mounts.length === 0) return strings.t("tooltip.none")
  return mounts.map(function (mount) {
    return format(strings.t("tooltip.line"), [mount.remote, statusText(mount, strings, formatNumber)])
  }).join("\n")
}

// Remotes the panel walks you through when they are missing. The names are
// the ones the README uses; any other remote still shows up once it exists.
var GUIDES = [
  { name: "gdrive", type: "drive" },
  { name: "onedrive", type: "onedrive" }
]

var NAME_PATTERN = /^[A-Za-z0-9_.-]+$/

function parseRemotes(raw) {
  var entries
  try {
    entries = JSON.parse(String(raw || ""))
  } catch (e) {
    return []
  }
  if (!Array.isArray(entries)) return []
  return entries.filter(function (entry) {
    return entry && typeof entry.name === "string" && entry.name !== ""
  }).map(function (entry) {
    return {
      name: entry.name,
      type: String(entry.type || ""),
      clientId: String(entry.clientId || ""),
      driveType: String(entry.driveType || ""),
      enabled: entry.enabled === true,
      active: entry.active === true
    }
  })
}

// One card per configured remote, then one per guided remote still missing.
// A mount's state comes from its rc socket when it answers, else from systemd.
function cards(remotes, mounts) {
  var byName = {}
  for (var i = 0; i < mounts.length; i++) byName[mounts[i].remote] = mounts[i]
  var list = remotes.map(function (remote) {
    var mount = byName[remote.name]
    var state = mount ? mount.state : remote.active ? "starting" : "off"
    return {
      name: remote.name,
      type: remote.type,
      configured: true,
      mountable: NAME_PATTERN.test(remote.name),
      enabled: remote.enabled,
      state: state,
      pending: mount ? mount.pending : 0,
      project: projectNumber(remote.clientId),
      sharedClient: remote.type === "drive" && remote.clientId === "",
      driveType: remote.driveType
    }
  })
  GUIDES.forEach(function (guide) {
    var present = remotes.some(function (remote) { return remote.name === guide.name })
    // A second Drive remote can reuse the OAuth client of the first.
    var sibling = list.filter(function (card) { return card.type === guide.type && card.project !== "" })[0]
    if (!present) list.push({
      name: guide.name,
      type: guide.type,
      configured: false,
      mountable: true,
      enabled: false,
      state: "off",
      pending: 0,
      project: sibling ? sibling.project : "",
      sharedClient: false,
      driveType: ""
    })
  })
  return list
}

// A Google OAuth client ID starts with the number of the project it lives in.
function projectNumber(clientId) {
  var match = /^(\d+)-/.exec(String(clientId || ""))
  return match ? match[1] : ""
}

var CONSOLE_PAGES = {
  credentials: "apis/credentials",
  audience: "auth/audience",
  driveApi: "apis/library/drive.googleapis.com"
}

function consoleUrl(page, project) {
  return "https://console.cloud.google.com/" + CONSOLE_PAGES[page] + (project ? "?project=" + project : "")
}

function cardStatus(card, strings, formatNumber) {
  if (!card.configured) return strings.t("status.notSetUp")
  if (card.state === "off") return strings.t("status.off")
  if (card.state === "starting") return strings.t("status.starting")
  return statusText({ state: card.state, pending: card.pending }, strings, formatNumber)
}

function typeName(type, strings) {
  var key = "type." + type
  var name = strings.t(key)
  return name === key || name === "" ? type : name
}

function heroMeta(mounts, strings, formatNumber) {
  var s = summary(mounts)
  if (s.state === "none") return strings.t("tooltip.none")
  if (s.state === "unreachable") return strings.t("hero.unreachable")
  if (s.state === "uploading") return format(strings.tn("status.uploading", s.pending), [formatNumber(s.pending)])
  return strings.t("status.idle")
}

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

// Interactive steps run in Omarchy's floating terminal, which ends with a
// Done/Failed prompt so the outcome stays readable.
function terminalCommand(scriptPath, args) {
  var words = ["bash", scriptPath].concat(args).map(shellQuote)
  return ["omarchy-launch-floating-terminal-with-presentation", words.join(" ")]
}

// The first non-empty line of what ctl.sh printed is the error worth showing.
function replyError(text) {
  var lines = String(text || "").split("\n").map(function (line) { return line.trim() })
  for (var i = 0; i < lines.length; i++) if (lines[i] !== "") return lines[i]
  return ""
}

var TYPE_GLYPHS = {
  drive: "󰊶", // google-drive
  onedrive: "󰏊" // microsoft-onedrive
}

function typeGlyph(type) {
  return TYPE_GLYPHS[type] || GLYPHS.idle
}

var HELP = {
  drive: "https://rclone.org/drive/#making-your-own-client-id",
  onedrive: "https://rclone.org/onedrive/"
}

function helpUrl(type) {
  return HELP[type] || "https://rclone.org/docs/"
}

function driveTypeName(driveType, strings) {
  var key = "driveType." + driveType
  var name = strings.t(key)
  return name === key || name === "" ? driveType : name
}
