# Omarchy Storage 0.1.0

First public release of the storage meter for the Omarchy bar.

## Features

- Eight-segment bar glyph that shows the usage of one mount (default `/`) and switches to
  the theme's urgent colour from 90%.
- Glance panel: percentage, used / total, Used, Free, Total and all real file systems,
  with Btrfs subvolumes of one pool merged.
- On-demand investigation: sizes of a folder's immediate sub-folders with `du`, on one
  file system only, with drill-down, back navigation, rescan and cancel.
- Settings for the mount, the refresh interval (default 60 s, minimum 15 s) and the
  investigation start folder.
- IPC target `dev.kern.storage` with `open`, `close`, `toggle` and `refresh`.
- Follows the active Omarchy theme. No daemon, no network, no root, no files written.

## Changes since the private prototype

- Fixed: on Qt 6.12 the panel's warning colour, error text and hover fill had no valid
  colour (see [QA](QA.md#fixed-in-this-release)).
- Added tests for malformed data, the scan script and the QML at runtime.
- Added the README, QA notes and a reproducible, privacy-safe screenshot tool.

## Requirements

Omarchy 4.5 or newer, with `findmnt` (util-linux), GNU `du` (coreutils) and `bash`.
Tested on Omarchy 4.5.0, Quickshell 0.3.2 and Qt 6.12.0 on a horizontal bar.

## Install

```sh
omarchy plugin add https://github.com/JK3RN/omarchy-storage --enable
```

Remove it with `omarchy plugin remove dev.kern.storage`.
