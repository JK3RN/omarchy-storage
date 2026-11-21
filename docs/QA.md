# QA — Omarchy Storage 0.1.0

## Test environment

| Component | Version |
| --- | --- |
| Omarchy | 4.5.0 (x86_64) |
| Compositor | Hyprland, one 1920×1080 display at scale 1.25, horizontal top bar |
| Quickshell | 0.3.2 |
| Qt | 6.12.0 |
| util-linux (`findmnt`) | 2.42.4 |
| coreutils (`du`) | 9.12 |
| Node.js (tests only) | 26 |

## Automated tests

`tests/run-all.sh`, all suites passing:

| Suite | Result |
| --- | --- |
| `tests/model.test.js` | PASS |
| `tests/model-edge.test.js` | PASS (17 checks) |
| `tests/storage-scan.test.sh` | PASS (15 checks, real GNU `du` on a temporary tree) |
| `tests/qml/run.sh`, stand-ins for `findmnt`/`du` | PASS (51 checks) |
| `tests/qml/run.sh`, `findmnt` missing | PASS (2 checks; documents the limitation below) |

## Manual checks on a real desktop

| Check | Result |
| --- | --- |
| `omarchy plugin validate` on the plugin folder | PASS |
| Widget loads in the running Omarchy shell, no plugin warnings in the shell log | PASS |
| Glance panel opened with `omarchy-shell dev.kern.storage open`: values match `findmnt` (Btrfs subvolumes merged into `/`) | PASS |
| `refresh`, `close` over IPC | PASS |
| Glance, investigation, drill-down and the 90% warning state rendered with the real QML and Omarchy UI components (`tools/showcase/capture.sh`) | PASS, see `docs/media` |
| `omarchy plugin add <git-url> --yes` in a sandboxed home: clone, manifest validation, folder `dev.kern.storage`, executable bit kept; a second add is refused as a duplicate id | PASS |
| Full `omarchy plugin add --enable` / `remove` on a live desktop | not run by the automated checks (talks to the running shell); manual acceptance step |
| Vertical bar, several monitors | not tested |

## Fixed in this release

On Qt 6.12, QtQuick provides its own type called `Color`, which hides the bare name
`Color` from `qs.Commons`. The panel's warning colour (glyph, percentage and bar from 90%),
its error messages and its hover fill therefore had no valid colour: the glyph turned black
and error text was nearly invisible on dark themes. The panel and the glyph now use
`Commons.Color`, like Omarchy's own plugins, and `tests/qml/run.sh` fails on any
`Unable to assign` warning.

## Known limits

See *Known limits* in the [README](../README.md#known-limits).
