const assert = require("node:assert/strict")
const Model = require("../Model.js")

assert.equal(Model.clampPercent(101), 100)
assert.equal(Model.formatBytes(1000000000), "1.00 GB")
assert.equal(Model.parentPath("/home/user/Games"), "/home/user")

const metadata = Model.parseMetadata(JSON.stringify({ filesystems: [
  { target: "/home", source: "/dev/root[/@home]", fstype: "btrfs", size: 100, used: 40, avail: 60 },
  { target: "/", source: "/dev/root[/@]", fstype: "btrfs", size: 100, used: 40, avail: 60 },
  { target: "/boot", source: "/dev/boot", fstype: "vfat", size: 20, used: 5, avail: 15 }
]}), "/")
assert.equal(metadata.primary.target, "/")
assert.equal(metadata.mounts.length, 2)
assert.equal(metadata.primary.percent, 40)

const scan = Model.parseScan("10\t/home/user/A Folder\n30\t/home/user/B\n50\t/home/user\n", "/home/user")
assert.equal(scan.entries[0].name, "B")
assert.equal(scan.entries[1].name, "A Folder")
assert.equal(scan.total, 50)
assert.equal(scan.entries[2].name, "Other (files and metadata)")
assert.equal(scan.entries[2].size, 10)

console.log("Model tests passed")
