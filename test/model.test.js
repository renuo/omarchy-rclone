const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const path = require("node:path")
const { loadModel } = require("./load-model")

const Model = loadModel()

// Values built inside the vm context carry that context's prototypes, which
// deepStrictEqual would reject; compare their JSON shape instead.
const plain = (value) => JSON.parse(JSON.stringify(value))

// Stands in for Commons.Translations, reading the shipped English catalog so a
// renamed or missing key fails here rather than showing up as a raw key.
const catalog = require(path.join(__dirname, "..", "i18n", "en.json"))
const strings = {
  t: (key) => (key in catalog ? catalog[key] : key),
  tn: (key, count) => catalog[key][count === 1 ? "one" : "other"],
}
const formatNumber = (n) => String(n)

function stats(inProgress, queued) {
  return { diskCache: { uploadsInProgress: inProgress, uploadsQueued: queued } }
}

describe("pathFromUrl", () => {
  it("strips file:// and decodes", () => {
    assert.equal(Model.pathFromUrl("file:///home/me/my%20plugin/status.sh"), "/home/me/my plugin/status.sh")
  })

  it("passes plain paths through", () => {
    assert.equal(Model.pathFromUrl("/a/status.sh"), "/a/status.sh")
    assert.equal(Model.pathFromUrl(undefined), "")
  })

  it("keeps an undecodable path as is", () => {
    assert.equal(Model.pathFromUrl("file:///a/%E0%A4%A"), "/a/%E0%A4%A")
  })
})

describe("parseMounts", () => {
  it("reads one mount per entry", () => {
    const raw = JSON.stringify([
      { remote: "gdrive", ok: true, stats: stats(0, 0) },
      { remote: "onedrive", ok: true, stats: stats(1, 2) },
    ])
    assert.deepEqual(plain(Model.parseMounts(raw)), [
      { remote: "gdrive", state: "idle", pending: 0 },
      { remote: "onedrive", state: "uploading", pending: 3 },
    ])
  })

  it("treats a mount that did not answer as unreachable", () => {
    assert.deepEqual(plain(Model.parseMounts('[{"remote":"gdrive","ok":false}]')), [
      { remote: "gdrive", state: "unreachable", pending: 0 },
    ])
  })

  it("treats malformed entries as unreachable rather than dropping them", () => {
    assert.deepEqual(plain(Model.parseMounts("[null]")), [{ remote: "", state: "unreachable", pending: 0 }])
  })

  it("returns no mounts for output that is not a JSON array", () => {
    assert.deepEqual(plain(Model.parseMounts("")), [])
    assert.deepEqual(plain(Model.parseMounts("{}")), [])
    assert.deepEqual(plain(Model.parseMounts("not json")), [])
    assert.deepEqual(plain(Model.parseMounts(undefined)), [])
  })
})

describe("pendingUploads", () => {
  it("adds uploads in progress and queued", () => {
    assert.equal(Model.pendingUploads(stats(2, 5)), 7)
  })

  it("counts nothing when the mount runs without a disk cache", () => {
    assert.equal(Model.pendingUploads({}), 0)
    assert.equal(Model.pendingUploads(undefined), 0)
  })

  it("ignores counters that are not numbers", () => {
    assert.equal(Model.pendingUploads(stats("x", undefined)), 0)
  })
})

describe("summary", () => {
  it("is none without mounts", () => {
    assert.deepEqual(plain(Model.summary([])), { state: "none", pending: 0 })
  })

  it("is idle when every mount is up to date", () => {
    assert.deepEqual(plain(Model.summary([{ state: "idle", pending: 0 }])), { state: "idle", pending: 0 })
  })

  it("adds pending uploads across mounts", () => {
    const mounts = [
      { state: "uploading", pending: 2 },
      { state: "idle", pending: 0 },
      { state: "uploading", pending: 1 },
    ]
    assert.deepEqual(plain(Model.summary(mounts)), { state: "uploading", pending: 3 })
  })

  it("lets one unreachable mount win over uploads elsewhere", () => {
    const mounts = [
      { state: "uploading", pending: 2 },
      { state: "unreachable", pending: 0 },
    ]
    assert.deepEqual(plain(Model.summary(mounts)), { state: "unreachable", pending: 2 })
  })
})

describe("glyph", () => {
  it("has a distinct glyph per state", () => {
    const glyphs = ["none", "idle", "uploading", "unreachable"].map(Model.glyph)
    assert.equal(new Set(glyphs).size, 4)
  })

  it("encodes the Material Design cloud code points", () => {
    assert.equal(Model.glyph("idle").codePointAt(0), 0xf015f)
    assert.equal(Model.glyph("uploading").codePointAt(0), 0xf0167)
  })

  it("falls back to the empty cloud for an unknown state", () => {
    assert.equal(Model.glyph("bogus"), Model.glyph("none"))
  })
})

describe("format", () => {
  it("fills numbered placeholders", () => {
    assert.equal(Model.format("%1: %2", ["a", "b"]), "a: b")
  })

  it("keeps placeholders it has no value for", () => {
    assert.equal(Model.format("%1 %3", ["a"]), "a %3")
  })

  it("does not expand placeholders or replacement patterns inside values", () => {
    assert.equal(Model.format("%1: %2", ["%2 $& $1", "b"]), "%2 $& $1: b")
  })
})

describe("tooltip", () => {
  it("says when nothing is mounted", () => {
    assert.equal(Model.tooltip([], strings, formatNumber), "No rclone mounts running")
  })

  it("lists every mount with its state", () => {
    const mounts = [
      { remote: "gdrive", state: "idle", pending: 0 },
      { remote: "onedrive", state: "uploading", pending: 1 },
      { remote: "s3", state: "uploading", pending: 4 },
      { remote: "nas", state: "unreachable", pending: 0 },
    ]
    assert.equal(
      Model.tooltip(mounts, strings, formatNumber),
      ["gdrive: Up to date", "onedrive: Uploading 1 file", "s3: Uploading 4 files", "nas: Not responding"].join("\n"),
    )
  })

  it("formats counts with the given number formatter", () => {
    const mounts = [{ remote: "gdrive", state: "uploading", pending: 1200 }]
    assert.equal(Model.tooltip(mounts, strings, (n) => `#${n}`), "gdrive: Uploading #1200 files")
  })

  it("keeps markup-shaped remote names as literal text", () => {
    const mounts = [{ remote: '<img src="https://example.invalid/x">', state: "idle", pending: 0 }]
    assert.equal(Model.tooltip(mounts, strings, formatNumber), '<img src="https://example.invalid/x">: Up to date')
  })
})

function remote(name, fields) {
  return Object.assign({ name: name, type: "drive", clientId: "", driveType: "", enabled: false, active: false }, fields)
}

describe("parseRemotes", () => {
  it("reads every remote ctl.sh lists", () => {
    const raw = JSON.stringify([
      { name: "gdrive", type: "drive", clientId: "1-a.apps", driveType: "", enabled: true, active: true },
    ])
    assert.deepEqual(plain(Model.parseRemotes(raw)), [
      { name: "gdrive", type: "drive", clientId: "1-a.apps", driveType: "", enabled: true, active: true },
    ])
  })

  it("fills missing fields and only takes true for true", () => {
    assert.deepEqual(plain(Model.parseRemotes('[{"name":"x","enabled":"yes"}]')), [
      { name: "x", type: "", clientId: "", driveType: "", enabled: false, active: false },
    ])
  })

  it("drops entries without a name", () => {
    assert.deepEqual(plain(Model.parseRemotes('[null, {"name":""}, {"type":"drive"}]')), [])
  })

  it("reads anything else as no remotes", () => {
    assert.deepEqual(plain(Model.parseRemotes("oops")), [])
    assert.deepEqual(plain(Model.parseRemotes('{"name":"x"}')), [])
    assert.deepEqual(plain(Model.parseRemotes(undefined)), [])
  })
})

describe("cards", () => {
  it("offers a guide for each missing guided remote", () => {
    const cards = plain(Model.cards([], []))
    assert.deepEqual(cards.map((c) => [c.name, c.type, c.configured]), [
      ["gdrive", "drive", false],
      ["onedrive", "onedrive", false],
    ])
  })

  it("lists configured remotes first, guided or not, without a guide twice", () => {
    const cards = plain(Model.cards([remote("onedrive", { type: "onedrive" }), remote("s3", { type: "s3" })], []))
    assert.deepEqual(cards.map((c) => [c.name, c.configured]), [
      ["onedrive", true],
      ["s3", true],
      ["gdrive", false],
    ])
  })

  it("takes the mount state from the rc socket when it answers", () => {
    const [card] = plain(Model.cards([remote("gdrive", { enabled: true, active: true })], [{ remote: "gdrive", state: "uploading", pending: 4 }]))
    assert.equal(card.state, "uploading")
    assert.equal(card.pending, 4)
    assert.equal(card.enabled, true)
  })

  it("calls a running unit without an answering socket starting", () => {
    assert.equal(plain(Model.cards([remote("gdrive", { active: true })], []))[0].state, "starting")
  })

  it("calls a stopped unit off", () => {
    assert.equal(plain(Model.cards([remote("gdrive")], []))[0].state, "off")
  })

  it("knows the Google Cloud project of a Drive remote's own client", () => {
    const [card] = plain(Model.cards([remote("gdrive", { clientId: "886583002273-abc.apps.googleusercontent.com" })], []))
    assert.equal(card.project, "886583002273")
    assert.equal(card.sharedClient, false)
  })

  it("flags a Drive remote on rclone's shared client", () => {
    assert.equal(plain(Model.cards([remote("gdrive")], []))[0].sharedClient, true)
    assert.equal(plain(Model.cards([remote("od", { type: "onedrive" })], []))[0].sharedClient, false)
  })

  it("points a missing gdrive at the project another Drive remote uses", () => {
    const cards = plain(Model.cards([remote("work", { clientId: "42-x.apps" })], []))
    assert.equal(cards.find((c) => c.name === "gdrive").project, "42")
  })

  it("marks names systemd cannot take as not mountable", () => {
    assert.equal(plain(Model.cards([remote("my drive")], []))[0].mountable, false)
    assert.equal(plain(Model.cards([remote("my-drive_2.0")], []))[0].mountable, true)
  })

  it("keeps the drive type for OneDrive", () => {
    assert.equal(plain(Model.cards([remote("onedrive", { type: "onedrive", driveType: "business" })], []))[0].driveType, "business")
  })
})

describe("projectNumber", () => {
  it("reads the digits before the first dash", () => {
    assert.equal(Model.projectNumber("886583002273-abc.apps.googleusercontent.com"), "886583002273")
  })

  it("is empty for anything else", () => {
    assert.equal(Model.projectNumber("abc-123"), "")
    assert.equal(Model.projectNumber(""), "")
    assert.equal(Model.projectNumber(undefined), "")
  })
})

describe("consoleUrl", () => {
  it("opens the page in the given project", () => {
    assert.equal(Model.consoleUrl("credentials", "42"), "https://console.cloud.google.com/apis/credentials?project=42")
    assert.equal(Model.consoleUrl("audience", "42"), "https://console.cloud.google.com/auth/audience?project=42")
  })

  it("leaves the project to the console when none is known", () => {
    assert.equal(Model.consoleUrl("driveApi", ""), "https://console.cloud.google.com/apis/library/drive.googleapis.com")
  })
})

describe("cardStatus", () => {
  const card = (fields) => Object.assign({ configured: true, state: "idle", pending: 0 }, fields)

  it("tells a missing remote from one that is not mounted", () => {
    assert.equal(Model.cardStatus(card({ configured: false }), strings, formatNumber), "Not set up")
    assert.equal(Model.cardStatus(card({ state: "off" }), strings, formatNumber), "Not mounted")
    assert.equal(Model.cardStatus(card({ state: "starting" }), strings, formatNumber), "Mounting…")
  })

  it("reports a running mount like the tooltip does", () => {
    assert.equal(Model.cardStatus(card({ state: "uploading", pending: 2 }), strings, formatNumber), "Uploading 2 files")
    assert.equal(Model.cardStatus(card({}), strings, formatNumber), "Up to date")
  })
})

describe("typeName", () => {
  it("names the known backends", () => {
    assert.equal(Model.typeName("drive", strings), "Google Drive")
    assert.equal(Model.typeName("onedrive", strings), "OneDrive")
  })

  it("falls back to rclone's type", () => {
    assert.equal(Model.typeName("s3", strings), "s3")
  })
})

describe("heroMeta", () => {
  it("sums up every mount", () => {
    assert.equal(Model.heroMeta([], strings, formatNumber), "No rclone mounts running")
    assert.equal(Model.heroMeta([{ state: "idle", pending: 0 }], strings, formatNumber), "Up to date")
    assert.equal(Model.heroMeta([{ state: "uploading", pending: 1 }], strings, formatNumber), "Uploading 1 file")
    assert.equal(Model.heroMeta([{ state: "unreachable", pending: 0 }], strings, formatNumber), "A mount stopped answering")
  })
})

describe("terminalCommand", () => {
  it("runs the script in Omarchy's floating terminal with every word quoted", () => {
    assert.deepEqual(plain(Model.terminalCommand("/p/ctl.sh", ["login", "it's"])), [
      "omarchy-launch-floating-terminal-with-presentation",
      "'bash' '/p/ctl.sh' 'login' 'it'\\''s'",
    ])
  })
})

describe("replyError", () => {
  it("takes the first line with text", () => {
    assert.equal(Model.replyError("\n  Failed to enable unit\nmore\n"), "Failed to enable unit")
  })

  it("is empty for a quiet success", () => {
    assert.equal(Model.replyError(""), "")
    assert.equal(Model.replyError(undefined), "")
  })
})

describe("typeGlyph", () => {
  it("has a logo for each guided backend and a cloud for the rest", () => {
    assert.equal(Model.typeGlyph("drive"), "\u{F02B6}")
    assert.equal(Model.typeGlyph("onedrive"), "\u{F03CA}")
    assert.equal(Model.typeGlyph("s3"), Model.glyph("idle"))
  })
})

describe("helpUrl", () => {
  it("links rclone's page for the backend", () => {
    assert.equal(Model.helpUrl("drive"), "https://rclone.org/drive/#making-your-own-client-id")
    assert.equal(Model.helpUrl("onedrive"), "https://rclone.org/onedrive/")
    assert.equal(Model.helpUrl("s3"), "https://rclone.org/docs/")
  })
})

describe("driveTypeName", () => {
  it("names OneDrive's drive types", () => {
    assert.equal(Model.driveTypeName("business", strings), "OneDrive for Business")
    assert.equal(Model.driveTypeName("documentLibrary", strings), "SharePoint library")
  })

  it("falls back to rclone's value", () => {
    assert.equal(Model.driveTypeName("other", strings), "other")
  })
})
