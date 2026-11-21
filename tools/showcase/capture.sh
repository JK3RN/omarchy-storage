#!/usr/bin/env bash
# Captures the README screenshots from the real plugin running in a real
# Quickshell process on the current Wayland (Hyprland) session.
#
# Privacy: the shell runs inside bubblewrap with an empty tmpfs over /home and
# only a synthetic /home/demo bound in. findmnt and du are replaced by doubles
# that print tools/showcase/data, so no real mount, path or size can appear.
# The demo theme in tools/showcase/theme supplies the colours.
#
# Usage: tools/showcase/capture.sh [plugin-dir] [output-dir]
# Needs: bwrap, qs (quickshell), grim, magick (ImageMagick), Omarchy shell.
# The capture briefly covers the screen with a dark backdrop (~15 s).
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
plugin=$(cd -- "${1:-$repo}" && pwd)
out=${2:-$repo/docs/media}
shell_dir=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}

for tool in bwrap qs grim magick; do
  command -v "$tool" >/dev/null || { echo "capture.sh: missing $tool" >&2; exit 1; }
done
[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "capture.sh: needs a Wayland session" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
demo_plugin=/home/demo/.config/omarchy/plugins/dev.kern.storage

mkdir -p "$work/config" "$work/raw" "$work/home/.local/state/omarchy/current/theme"
for d in Games/Steam Games/Heroic Games/Lutris Videos Projects .local .cache Downloads; do
  mkdir -p "$work/home/$d"
done
cp -- "$here/theme/colors.toml" "$work/home/.local/state/omarchy/current/theme/"
cp -r -- "$here/bin" "$here/data" "$work/"
cp -- "$here/shell.qml" "$work/config/"
ln -s -- "$shell_dir/Commons" "$work/config/Commons"
ln -s -- "$shell_dir/Ui" "$work/config/Ui"
ln -s -- "$demo_plugin" "$work/config/plugin"

fontconf=()
[[ -d $HOME/.config/fontconfig ]] && fontconf=(--ro-bind "$HOME/.config/fontconfig" /home/demo/.config/fontconfig)

bwrap --dev-bind / / \
  --tmpfs /home \
  --bind "$work/home" /home/demo \
  --ro-bind "$plugin" "$demo_plugin" \
  "${fontconf[@]}" \
  --unsetenv XDG_CONFIG_HOME --unsetenv XDG_DATA_HOME --unsetenv XDG_STATE_HOME --unsetenv XDG_CACHE_HOME \
  --setenv HOME /home/demo \
  --setenv USER demo \
  --setenv PATH "$work/bin:/usr/bin:/bin" \
  --setenv STORAGE_DEMO_DATA "$work/data" \
  --setenv STORAGE_DEMO_OUT "$work/raw" \
  --chdir /home/demo \
  timeout 60 qs -p "$work/config" --no-color 2>&1 |
  grep -E 'SHOT|WARN scene|qml: .*(Error|error)|TypeError|ReferenceError|Unable' || true

mkdir -p "$out"
for raw in "$work"/raw/raw-*.png; do
  [[ -f $raw ]] || { echo "capture.sh: no captures were written" >&2; exit 1; }
  name=$(basename -- "$raw" .png); name=${name#raw-}
  read -r W H < <(magick identify -format '%w %h\n' "$raw")
  bar=$(( H * 40 / 1080 ))
  # The panel card is outlined by the theme border; trimming the uniform
  # backdrop below the bar finds it.
  geo=$(magick "$raw" -crop "${W}x$((H - bar))+0+${bar}" +repage -fuzz 4% -trim -format '%w %h %X %Y' info:)
  read -r cw ch cx cy <<<"${geo//+/}"
  pad=$(( H * 28 / 1080 ))
  x=$(( cx - pad )); w=$(( cw + 2 * pad )); h=$(( bar + cy + ch + pad ))
  magick "$raw" -crop "${w}x${h}+${x}+0" +repage -strip -define png:exclude-chunks=date,time "$out/$name.png"
  echo "wrote $out/$name.png (${w}x${h})"
done
