#!/usr/bin/env bash
# Runs every test suite. Suites whose environment is missing report SKIP
# (exit code 77) and do not count as failures.
set -uo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

failed=0
suite() {
  local name=$1; shift
  echo "### $name"
  "$@"; local rc=$?
  case $rc in
    0) echo "### $name: PASS" ;;
    77) echo "### $name: SKIP" ;;
    *) echo "### $name: FAIL ($rc)"; failed=1 ;;
  esac
  echo
}

if command -v node >/dev/null; then
  suite "model" node "$here/model.test.js"
  suite "model edge cases" node "$here/model-edge.test.js"
else
  echo "### model: SKIP (node not installed)"; echo
fi
suite "storage-scan" bash "$here/storage-scan.test.sh"
suite "QML runtime" bash "$here/qml/run.sh"

exit $failed
