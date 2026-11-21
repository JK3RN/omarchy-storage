// Edge cases for Model.js: malformed metadata, partial scans and path helpers.
// Pure functions only; nothing here touches the real filesystem.
const assert = require("node:assert/strict")
const Model = require("../Model.js")

let checks = 0
function check(name, fn) { fn(); checks++ }

check("invalid JSON yields an error, not an exception", () => {
  const r = Model.parseMetadata("not json", "/")
  assert.equal(r.primary, null)
  assert.deepEqual(r.mounts, [])
  assert.match(r.error, /Could not read/)
})

check("empty findmnt output yields an error", () => {
  assert.match(Model.parseMetadata("", "/").error, /Could not read/)
})

check("missing filesystems array yields 'no usable filesystem'", () => {
  const r = Model.parseMetadata(JSON.stringify({}), "/")
  assert.equal(r.primary, null)
  assert.match(r.error, /No usable filesystem/)
})

// findmnt never emits null entries; Model.js does not guard against them in its
// primary lookup (documented limitation), so they are not part of this case.
check("sizeless, zero-size and non-numeric entries are skipped", () => {
  const r = Model.parseMetadata(JSON.stringify({ filesystems: [
    { target: "/no-size" },
    { target: "/zero", size: 0, used: 0, avail: 0 },
    { target: "/nan", size: "abc", used: 1, avail: 1 },
    { target: "/ok", source: "/dev/x", size: 200, used: "50", avail: 150 }
  ]}), "/ok")
  assert.deepEqual(r.mounts.map(m => m.target), ["/ok"])
  assert.equal(r.primary.percent, 25)
  assert.equal(r.error, "")
})

check("configured mount that does not exist falls back to the first listed mount", () => {
  const r = Model.parseMetadata(JSON.stringify({ filesystems: [
    { target: "/boot", source: "/dev/b", size: 100, used: 10, avail: 90 },
    { target: "/", source: "/dev/r", size: 100, used: 70, avail: 30 }
  ]}), "/does/not/exist")
  assert.equal(r.primary.target, "/")
  assert.equal(r.primary.percent, 70)
})

check("a non-root configured mount sorts first and drives the meter", () => {
  const r = Model.parseMetadata(JSON.stringify({ filesystems: [
    { target: "/", source: "/dev/r", size: 100, used: 70, avail: 30 },
    { target: "/mnt/Media Archive", source: "/dev/m", size: 1000, used: 930, avail: 70 }
  ]}), "/mnt/Media Archive")
  assert.equal(r.mounts[0].target, "/mnt/Media Archive")
  assert.equal(r.primary.percent, 93)
})

check("btrfs subvolumes with identical pool numbers collapse onto /", () => {
  const pool = { source: "/dev/mapper/root", fstype: "btrfs", size: 500, used: 100, avail: 380 }
  const r = Model.parseMetadata(JSON.stringify({ filesystems: [
    Object.assign({ target: "/var/log" }, pool, { source: pool.source + "[/@log]" }),
    Object.assign({ target: "/home" }, pool, { source: pool.source + "[/@home]" }),
    Object.assign({ target: "/" }, pool, { source: pool.source + "[/@]" })
  ]}), "/")
  assert.deepEqual(r.mounts.map(m => m.target), ["/"])
})

check("missing avail is derived from size - used", () => {
  const r = Model.parseMetadata(JSON.stringify({ filesystems: [
    { target: "/", size: 100, used: 40 }
  ]}), "/")
  assert.equal(r.primary.avail, 60)
})

check("percent is clamped when used exceeds size", () => {
  const r = Model.parseMetadata(JSON.stringify({ filesystems: [
    { target: "/", size: 100, used: 150, avail: 0 }
  ]}), "/")
  assert.equal(r.primary.percent, 100)
})

check("formatBytes rejects negative and non-numeric values", () => {
  assert.equal(Model.formatBytes(-1), "—")
  assert.equal(Model.formatBytes("x"), "—")
  assert.equal(Model.formatBytes(0), "0 B")
  assert.equal(Model.formatBytes(1500), "1.50 KB")
  assert.equal(Model.formatBytes(4e15), "4.00 PB")
})

check("clampPercent handles NaN and negatives", () => {
  assert.equal(Model.clampPercent(NaN), 0)
  assert.equal(Model.clampPercent(-5), 0)
  assert.equal(Model.clampPercent(49.5), 50)
})

check("empty scan output yields no entries and zero total", () => {
  const r = Model.parseScan("", "/data")
  assert.deepEqual(r.entries, [])
  assert.equal(r.total, 0)
})

check("partial scan without the total line sums the children and adds no Other row", () => {
  const r = Model.parseScan("10\t/data/a\n30\t/data/b\n", "/data")
  assert.equal(r.total, 40)
  assert.deepEqual(r.entries.map(e => e.name), ["b", "a"])
})

check("malformed scan lines (no tab, negative, non-numeric) are ignored", () => {
  const r = Model.parseScan("garbage\n-5\t/data/neg\nabc\t/data/x\n\t/data/empty\n7\t/data/ok\n7\t/data\n", "/data")
  assert.deepEqual(r.entries.map(e => e.name), ["ok"])
  assert.equal(r.total, 7)
})

check("names with spaces, tabs-after-size, leading dashes and unicode survive", () => {
  const r = Model.parseScan("5\t/d/My Files\n4\t/d/-rf\n3\t/d/Ünïcødé ✓\n12\t/d\n", "/d")
  assert.deepEqual(r.entries.map(e => e.name), ["My Files", "-rf", "Ünïcødé ✓"])
  assert.equal(r.entries[0].path, "/d/My Files")
})

check("percentages refer to the scanned directory total", () => {
  const r = Model.parseScan("25\t/d/a\n100\t/d\n", "/d")
  assert.equal(r.entries.find(e => e.name === "a").percent, 25)
  assert.equal(r.entries.find(e => e.path === "").percent, 75)
})

check("path helpers handle root, trailing slashes and top-level dirs", () => {
  assert.equal(Model.parentPath("/"), "/")
  assert.equal(Model.parentPath("/home"), "/")
  assert.equal(Model.parentPath("/a/b/"), "/a")
  assert.equal(Model.parentPath(""), "/")
  assert.equal(Model.baseName("/a/b/"), "b")
  // "/" itself is only ever the scan total, never a listed entry.
  assert.equal(Model.baseName("/"), "")
})

console.log("Model edge tests passed (" + checks + " checks)")
