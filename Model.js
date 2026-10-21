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
