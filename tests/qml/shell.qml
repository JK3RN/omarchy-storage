import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "plugin" as P

// Runtime regression tests for the plugin's QML. Started by tests/qml/run.sh
// inside a real Quickshell process with the installed Omarchy Commons/Ui
// modules. findmnt and du are test doubles on PATH (tests/qml/bin), so no real
// mount is read and no real directory is scanned. The panel stays closed: only
// its scan state machine is exercised.
ShellRoot {
  id: harness

  readonly property string dir: Quickshell.env("STORAGE_TEST_DIR")
  readonly property string fixtures: Quickshell.env("STORAGE_TEST_FIXTURES")
  readonly property string mode: Quickshell.env("STORAGE_TEST_MODE") || "full"
  readonly property string home: Quickshell.env("HOME")
  property int failures: 0
  property int passes: 0

  function check(name, got, want) {
    if (JSON.stringify(got) === JSON.stringify(want)) { passes++; console.log("  ok   " + name) }
    else { failures++; console.log("  FAIL " + name + ": got " + JSON.stringify(got) + ", wanted " + JSON.stringify(want)) }
  }
  function note(text) { console.log("  note " + text) }

  // ---- tiny sequential step runner ----------------------------------------
  property var steps: []
  property int stepIndex: -1
  property var stepUntil: null
  property double stepDeadline: 0

  function runSteps(list) { steps = list; stepIndex = -1; advance() }
  function advance() {
    stepIndex++
    if (stepIndex >= steps.length) { finish(); return }
    var s = steps[stepIndex]
    if (s.title) console.log(s.title)
    if (s.act) s.act()
    stepUntil = s.until || null
    stepDeadline = Date.now() + (s.timeout || 5000)
    poller.restart()
  }
  Timer {
    id: poller
    interval: 25
    repeat: true
    onTriggered: {
      var s = harness.steps[harness.stepIndex]
      var done = !harness.stepUntil || harness.stepUntil()
      if (!done && Date.now() < harness.stepDeadline) return
      stop()
      if (!done) harness.check((s.title || "step") + " finished in time", false, true)
      else if (s.verify) s.verify()
      harness.advance()
    }
  }
  function finish() {
    console.log("RESULT passes=" + passes + " failures=" + failures)
    Qt.exit(failures === 0 ? 0 : 1)
  }

  // Writes test-double control files through argv, never through a shell.
  Process { id: writer }
  function write(args) { writer.command = args; writer.running = true }
  function writerIdle() { return !writer.running }

  Process {
    id: lister
    property string out: ""
    stdout: StdioCollector { onStreamFinished: lister.out = text }
  }

  // ---- objects under test ---------------------------------------------------
  P.StorageState { id: storage; primaryTarget: "/" }
  P.StorageState { id: nanStorage; refreshSeconds: Number("not-a-number") }
  P.StorageState { id: tinyStorage; refreshSeconds: 1 }
  P.StorageGlyph { id: glyph; width: 24; height: 24; foreground: "#00ff66"; urgent: "#ffcc00" }
  P.StorageGlyph { id: defaultGlyph }
  P.Panel { id: panel; settings: ({ investigatePath: "~" }) }

  Component.onCompleted: mode === "missing-findmnt" ? runSteps(missingSteps()) : runSteps(fullSteps())

  function missingSteps() {
    return [
      { title: "findmnt missing from PATH", until: function() { return !storage.metadataProcess.running }, timeout: 3000,
        verify: function() {
          check("no primary filesystem", storage.primary, null)
          check("percent falls back to 0", storage.percent, 0)
          note("error text: " + JSON.stringify(storage.error) + ", loading: " + storage.loading)
        } }
    ]
  }

  function fullSteps() {
    return [
      { title: "idle metadata refresh (fixture A)", until: function() { return !storage.metadataProcess.running && storage.primary !== null },
        verify: function() {
          check("primary is /", storage.primary.target, "/")
          check("percent of / is 42", storage.percent, 42)
          check("btrfs /home collapses into /", storage.mounts.map(function(m) { return m.target }), ["/", "/boot", "/mnt/Media Archive"])
          check("mount with a space is kept intact", storage.mounts[2].percent, 93)
          check("no error", storage.error, "")
          check("loading cleared", storage.loading, false)
        } },
      { title: "findmnt is called with the metadata-only arguments", act: function() { lister.command = ["cat", dir + "/findmnt.args"]; lister.running = true },
        until: function() { return !lister.running && lister.out !== "" },
        verify: function() {
          check("exact argv", lister.out.trim().split("\n"),
                ["--json", "--list", "--bytes", "--real", "--output", "TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL"])
        } },
      { title: "refresh interval", verify: function() {
          check("default 60 s", storage.refreshTimer.interval, 60000)
          check("non-numeric setting falls back to the 15 s floor", nanStorage.refreshTimer.interval, 15000)
          check("values below 15 s are raised to 15 s", tinyStorage.refreshTimer.interval, 15000)
          check("timer runs", storage.refreshTimer.running, true)
        } },
      { title: "data changes between refreshes (fixture B)", act: function() { write(["cp", fixtures + "/findmnt-b.json", dir + "/findmnt.json"]) },
        until: writerIdle },
      { act: function() { storage.refresh() }, until: function() { return !storage.metadataProcess.running && storage.percent === 61 },
        verify: function() {
          check("percent follows the new data", storage.percent, 61)
          check("vanished mount disappears from the list", storage.mounts.map(function(m) { return m.target }), ["/", "/boot"])
        } },
      { title: "configured mount disappears", act: function() { storage.primaryTarget = "/mnt/Media Archive"; storage.refresh() },
        until: function() { return !storage.metadataProcess.running },
        verify: function() {
          check("meter falls back to the first mount", storage.primary.target, "/")
          check("no error shown", storage.error, "")
        } },
      { title: "findmnt fails with no output", act: function() { storage.primaryTarget = "/"; write(["sh", "-c", ": > \"$1/findmnt.json\"; echo 1 > \"$1/findmnt.exit\"", "sh", dir]) },
        until: writerIdle },
      { act: function() { storage.refresh() }, until: function() { return !storage.metadataProcess.running && storage.error !== "" },
        verify: function() {
          check("primary cleared", storage.primary, null)
          check("error names the failure", storage.error, "findmnt failed (exit 1)")
          check("percent falls back to 0", storage.percent, 0)
        } },
      { title: "recovery after failure", act: function() { write(["sh", "-c", "cp \"$2\" \"$1/findmnt.json\"; rm -f \"$1/findmnt.exit\"", "sh", dir, fixtures + "/findmnt-a.json"]) },
        until: writerIdle },
      { act: function() { storage.refresh() }, until: function() { return !storage.metadataProcess.running && storage.percent === 42 },
        verify: function() { check("error cleared after recovery", storage.error, "") } },
      { title: "glyph meter", verify: function() {
          var cases = [[0, 0], [0.01, 1], [0.42, 4], [0.5, 4], [0.875, 7], [0.9, 8], [1, 8], [1.7, 8], [-1, 0]]
          for (var i = 0; i < cases.length; i++) {
            glyph.fraction = cases[i][0]
            check("fraction " + cases[i][0] + " lights " + cases[i][1] + " segments", glyph.litSegments, cases[i][1])
          }
          glyph.fraction = 0.89
          check("below 90% uses the foreground", String(glyph.fillColor), "#00ff66")
          glyph.fraction = 0.9
          check("from 90% uses the urgent colour", String(glyph.fillColor), "#ffcc00")
        } },
      { title: "theme colours resolve to Omarchy's palette (Qt 6.12 shadows the bare name Color)", verify: function() {
          check("glyph default urgent is the theme urgent", String(defaultGlyph.urgent), String(Commons.Color.urgent))
          check("glyph default foreground is the theme foreground", String(defaultGlyph.foreground), String(Commons.Color.foreground))
          check("panel without a bar uses the theme foreground", String(panel.foreground), String(Commons.Color.foreground))
        } },
      { title: "investigation of the start directory", act: function() { panel.investigate(panel.expandedStartPath()) },
        until: function() { return !panel.scanning && panel.entries.length > 0 },
        verify: function() {
          check("start path is $HOME", panel.currentPath, home)
          check("entries sorted by size, remainder as Other", panel.entries.map(function(e) { return e.name }),
                ["Alpha", "Other (files and metadata)", "Beta Gamma"])
          check("remainder is total minus children", panel.entries[1].size, 1500000000)
          check("total from du", panel.scanTotal, 5000000000)
          check("no error", panel.scanError, "")
        } },
      { title: "du is called one level deep, on one filesystem", act: function() { lister.out = ""; lister.command = ["cat", dir + "/du.args"]; lister.running = true },
        until: function() { return !lister.running && lister.out !== "" },
        verify: function() { check("exact argv", lister.out.trim().split("\n"), ["-x", "-B1", "--max-depth=1", "--", home]) } },
      { title: "drill down into a child", act: function() { panel.investigate(home + "/Alpha") },
        until: function() { return !panel.scanning && panel.entries.length > 0 },
        verify: function() {
          check("current path is the child", panel.currentPath, home + "/Alpha")
          check("child entries", panel.entries[0].path, home + "/Alpha/Alpha")
        } },
      { title: "back navigation", act: function() { panel.goBack() },
        until: function() { return !panel.scanning && panel.entries.length > 0 },
        verify: function() { check("back to the start", panel.currentPath, home) } },
      { act: function() { panel.goBack() }, until: function() { return !panel.scanning },
        verify: function() { check("back from the start leaves the investigation", panel.investigating, false) } },
      { title: "unreadable target", act: function() { panel.investigate(home + "/does-not-exist") },
        until: function() { return !panel.scanning && panel.scanError !== "" },
        verify: function() {
          check("error from storage-scan is shown", panel.scanError, "Storage path is not a readable directory: " + home + "/does-not-exist")
          check("no entries", panel.entries.length, 0)
        } },
      { title: "slow scan is cancelled", act: function() { write(["sh", "-c", "echo 3 > \"$1/du.delay\"", "sh", dir]) }, until: writerIdle },
      { act: function() { panel.investigate(home + "/Alpha") }, until: function() { return panel.scanning } },
      { act: function() { panel.stopScan() }, until: function() { return !panel.scanning },
        verify: function() { check("scanning stops at once", panel.scanning, false); check("cancel is not reported as an error", panel.scanError, "") } },
      { title: "cancelled du process is gone", act: function() { lister.out = ""; lister.command = ["pgrep", "-f", "^(/usr/bin/)?bash [^ ]*/bin/du -x"]; lister.running = true },
        until: function() { return !lister.running }, timeout: 3000,
        verify: function() { check("no du test double left running", lister.out.trim(), "") } },
      { title: "switching target while a scan runs", act: function() { panel.investigate(home + "/Alpha") }, until: function() { return panel.scanning } },
      { act: function() { panel.investigate(home + "/Beta Gamma") }, until: function() { return panel.currentPath === home + "/Beta Gamma" && panel.scanning },
        verify: function() {
          var stale = panel.entries.filter(function(e) { return e.path.indexOf(home + "/Alpha") === 0 }).length
          note("entries of the abandoned scan visible while the new one runs: " + stale)
        } },
      { until: function() { return !panel.scanning && panel.entries.length > 0 }, timeout: 8000,
        verify: function() {
          check("final entries belong to the new target", panel.entries[0].path.indexOf(home + "/Beta Gamma/") === 0, true)
          check("no error", panel.scanError, "")
        } },
      { title: "closing the panel stops a running scan", act: function() { panel.investigate(home + "/Alpha") }, until: function() { return panel.scanning } },
      { act: function() { panel.close() }, until: function() { return !panel.scanning },
        verify: function() { check("investigation closed", panel.investigating, false) } }
    ]
  }
}
