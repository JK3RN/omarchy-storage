#!/usr/bin/env bash
# Exercises scripts/storage-scan against a throwaway directory tree with the
# real GNU du. Read-only towards everything outside the temporary directory.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
scan="$here/../scripts/storage-scan"
work=$(mktemp -d)
trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf -- "$work"' EXIT

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

[[ -x $scan ]] && pass "storage-scan is executable" || fail "storage-scan lost its executable bit"

mkdir -p "$work/root/My Files" "$work/root/-rf" "$work/root/Ünïcødé" "$work/root/locked"
head -c 65536 /dev/zero > "$work/root/My Files/blob"
head -c 4096 /dev/zero > "$work/root/locked/secret"

out=$("$scan" "$work/root" 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && pass "scan of a readable tree exits 0" || fail "scan exit was $rc"
lines=$(printf '%s\n' "$out" | grep -c $'\t')
[[ $lines -eq 5 ]] && pass "one line per immediate child plus the total (5)" || fail "expected 5 lines, got $lines"
grep -qF $'\t'"$work/root/My Files" <<<"$out" && pass "path with a space is reported intact" || fail "space path missing"
grep -qF $'\t'"$work/root/-rf" <<<"$out" && pass "dash-leading name is treated as a path, not an option" || fail "dash path missing"
grep -qF $'\t'"$work/root/Ünïcødé" <<<"$out" && pass "unicode name is reported" || fail "unicode path missing"
! grep -qF "blob" <<<"$out" && pass "depth is limited to one level" || fail "scan descended below one level"

"$scan" "$work/root/-rf" >/dev/null 2>&1 && pass "a dash-leading target directory is scanned" || fail "dash-leading target failed"

"$scan" "$work/missing" >/dev/null 2>"$work/err"; rc=$?
[[ $rc -eq 2 ]] && grep -q "not a readable directory" "$work/err" && pass "missing target exits 2 with a message" || fail "missing target rc=$rc"

"$scan" "$work/root/My Files/blob" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && pass "a regular file is refused (exit 2)" || fail "file target rc=$rc"

"$scan" "" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && pass "empty argument is refused (exit 2)" || fail "empty target rc=$rc"

"$scan" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && pass "no argument is refused (exit 2)" || fail "no argument rc=$rc"

if [[ $(id -u) -ne 0 ]]; then
  chmod 000 "$work/root/locked"
  out=$("$scan" "$work/root" 2>"$work/err"); rc=$?
  [[ $rc -ne 0 ]] && grep -q "Permission denied" "$work/err" && pass "unreadable child reports a permission error on stderr" || fail "unreadable child rc=$rc"
  grep -qF $'\t'"$work/root/My Files" <<<"$out" && pass "readable siblings are still reported (partial result)" || fail "partial result missing"
  chmod 700 "$work/root/locked"
else
  printf '  SKIP permission test (running as root)\n'
fi

before=$(find "$work" | sort | sha256sum)
"$scan" "$work/root" >/dev/null 2>&1
after=$(find "$work" | sort | sha256sum)
[[ $before == "$after" ]] && pass "a scan does not create, move or delete anything" || fail "tree changed during scan"

if (( fails )); then printf 'storage-scan tests: %d failure(s)\n' "$fails"; exit 1; fi
echo "storage-scan tests passed"
