function clampPercent(value) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  return Math.max(0, Math.min(100, Math.round(n)))
}

function formatBytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return "—"
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var index = 0
  while (n >= 1000 && index < units.length - 1) {
    n /= 1000
    index++
  }
  var digits = index === 0 ? 0 : (n >= 100 ? 0 : n >= 10 ? 1 : 2)
  return n.toFixed(digits) + " " + units[index]
}

function parseMetadata(raw, primaryTarget) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (e) {
    return { primary: null, mounts: [], error: "Could not read filesystem metadata" }
  }
  var source = parsed && Array.isArray(parsed.filesystems) ? parsed.filesystems : []
  var mounts = []
  var seen = {}
  for (var i = 0; i < source.length; i++) {
    var item = source[i] || {}
    var size = Number(item.size)
    var used = Number(item.used)
    var avail = Number(item.avail)
    if (!item.target || !isFinite(size) || size <= 0) continue
    var sourceKey = String(item.source || "").replace(/\[.*\]$/, "")
    var key = sourceKey + "|" + size + "|" + used + "|" + avail
    // Btrfs subvolumes report the same pool repeatedly. Prefer /, then the
    // shortest mountpoint, so the glance list does not claim duplicate disks.
    if (seen[key] !== undefined) {
      var old = mounts[seen[key]]
      if (String(item.target) === "/" || (old.target !== "/" && String(item.target).length < old.target.length))
        mounts[seen[key]] = normalizedMount(item)
      continue
    }
    seen[key] = mounts.length
    mounts.push(normalizedMount(item))
  }
  mounts.sort(function(a, b) {
    if (a.target === primaryTarget) return -1
    if (b.target === primaryTarget) return 1
    if (a.target === "/") return -1
    if (b.target === "/") return 1
    return a.target.localeCompare(b.target)
  })
  var primary = null
  for (var j = 0; j < source.length; j++)
    if (String(source[j].target) === String(primaryTarget)) { primary = normalizedMount(source[j]); break }
  if (!primary && mounts.length) primary = mounts[0]
  return { primary: primary, mounts: mounts, error: primary ? "" : "No usable filesystem found" }
}

function normalizedMount(item) {
  var size = Number(item.size) || 0
  var used = Number(item.used) || 0
  var avail = Number(item.avail) || Math.max(0, size - used)
  return {
    target: String(item.target || ""),
    source: String(item.source || ""),
    fstype: String(item.fstype || ""),
    size: size,
    used: used,
    avail: avail,
    percent: size > 0 ? clampPercent(used * 100 / size) : 0
  }
}

function parseScan(raw, scannedPath) {
  var lines = String(raw || "").split("\n")
  var entries = []
  var total = 0
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var tab = lines[i].indexOf("\t")
    if (tab < 1) continue
    var size = Number(lines[i].slice(0, tab))
    var path = lines[i].slice(tab + 1)
    if (!isFinite(size) || size < 0) continue
    if (path === scannedPath) { total = size; continue }
    entries.push({ path: path, name: baseName(path), size: size })
  }
  entries.sort(function(a, b) { return b.size - a.size })
  if (!total) for (var j = 0; j < entries.length; j++) total += entries[j].size
  var childrenTotal = 0
  for (var k = 0; k < entries.length; k++) childrenTotal += entries[k].size
  var other = Math.max(0, total - childrenTotal)
  if (other > 0) entries.push({ path: "", name: "Other (files and metadata)", size: other })
  entries.sort(function(a, b) { return b.size - a.size })
  for (var m = 0; m < entries.length; m++)
    entries[m].percent = total > 0 ? clampPercent(entries[m].size * 100 / total) : 0
  return { entries: entries, total: total }
}

function baseName(path) {
  var clean = String(path || "").replace(/\/+$/, "")
  var slash = clean.lastIndexOf("/")
  return slash >= 0 ? clean.slice(slash + 1) || "/" : clean
}

function parentPath(path) {
  var clean = String(path || "/").replace(/\/+$/, "") || "/"
  if (clean === "/") return "/"
  var slash = clean.lastIndexOf("/")
  return slash <= 0 ? "/" : clean.slice(0, slash)
}

if (typeof module !== "undefined") module.exports = {
  clampPercent: clampPercent,
  formatBytes: formatBytes,
  parseMetadata: parseMetadata,
  parseScan: parseScan,
  baseName: baseName,
  parentPath: parentPath
}
