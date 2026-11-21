#!/usr/bin/env bash
# Runs tests/qml/shell.qml in a throwaway Quickshell config that links the
# installed Omarchy shell modules (Commons, Ui) and this plugin. HOME and the
# tool PATH point into a temporary directory; nothing outside it is written.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
shell_dir=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}
qs_bin=$(command -v qs || command -v quickshell || true)
timeout_bin=$(command -v timeout)

[[ -n $qs_bin ]] || { echo "SKIP: quickshell (qs) not installed"; exit 77; }
[[ -d $shell_dir/Commons && -d $shell_dir/Ui ]] || { echo "SKIP: Omarchy shell modules not found in $shell_dir"; exit 77; }
[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "SKIP: needs a Wayland session (WAYLAND_DISPLAY unset)"; exit 77; }

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/config" "$work/state" "$work/home/.config/omarchy/plugins" "$work/home/Alpha" "$work/home/Beta Gamma"
cp -- "$here/shell.qml" "$work/config/shell.qml"
ln -s -- "$shell_dir/Commons" "$work/config/Commons"
ln -s -- "$shell_dir/Ui" "$work/config/Ui"
ln -s -- "$repo" "$work/config/plugin"
ln -s -- "$repo" "$work/home/.config/omarchy/plugins/dev.kern.storage"
cp -- "$here/bin/findmnt" "$here/bin/du" "$work/state/"
mkdir -p "$work/state/bin" && mv -- "$work/state/findmnt" "$work/state/du" "$work/state/bin/"
cp -- "$repo/tests/fixtures/findmnt-a.json" "$work/state/findmnt.json"

run() {
  local mode=$1 path=$2
  env -i \
    HOME="$work/home" \
    PATH="$path" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
    STORAGE_TEST_DIR="$work/state" \
    STORAGE_TEST_FIXTURES="$repo/tests/fixtures" \
    STORAGE_TEST_MODE="$mode" \
    QT_QPA_PLATFORM=wayland \
    "$timeout_bin" 60 "$qs_bin" -p "$work/config" --no-color 2>&1 |
    sed -e "s#$work#<tmp>#g" -e "s#$repo#<repo>#g" |
    grep -E '^\s*(ok|FAIL|note|SKIP)\b|^[a-z].*$|RESULT|WARN|ERROR|TypeError|ReferenceError|qml:' |
    grep -v 'quickshell.qmlscanner' || true
}

status=0
echo "== QML runtime tests (test doubles for findmnt/du)"
out=$(run full "$work/state/bin:/usr/bin:/bin"); printf '%s\n' "$out"
grep -q 'RESULT passes=[0-9]* failures=0' <<<"$out" || status=1
if grep -q 'Unable to assign\|TypeError\|ReferenceError' <<<"$out"; then
  echo "  FAIL QML runtime warnings in plugin code (see above)"; status=1
fi

echo "== QML runtime tests (findmnt missing)"
mkdir -p "$work/empty-bin"
out=$(run missing-findmnt "$work/empty-bin"); printf '%s\n' "$out"
grep -q 'RESULT passes=[0-9]* failures=0' <<<"$out" || status=1

exit $status
