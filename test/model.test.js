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
