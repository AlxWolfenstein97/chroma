#!/usr/bin/env bash
# Full wipe of the AlxWolfenstein97 Style/Chroma extender family.
# Runs each uninstall.sh --yes (hooks/menus/state/paint; skips optional pkg Y/n),
# then omarchy plugin remove --yes. From home:
#   ~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/tools/wipe-all-family.sh
#
# Does NOT pacman -R shared deps (pillow etc.) — keep those for other tools.
# Privileged teardown (Limine/VT/FONT/root/SDDM) may still open a floater or
# ask for a password once per plugin that needs it.
set -euo pipefail
base="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
plugins=(chroma omacursor omaobs omahud omaboot omavt omatty)
fail=0
for p in "${plugins[@]}"; do
  id="io.github.alxwolfenstein97.$p"
  dir="$base/$id"
  if [[ ! -d $dir ]]; then
    printf 'wipe-all-family: skip %s (not installed)\n' "$p"
    continue
  fi
  printf 'wipe-all-family: uninstall %s --yes\n' "$p"
  if [[ -x $dir/uninstall.sh ]]; then
    if ! "$dir/uninstall.sh" --yes; then
      printf 'wipe-all-family: %s uninstall failed\n' "$p" >&2
      fail=1
    fi
  fi
  if command -v omarchy >/dev/null 2>&1; then
    printf 'wipe-all-family: plugin remove %s\n' "$id"
    omarchy plugin remove "$id" --yes >/dev/null 2>&1 \
      || omarchy plugin remove "$id" --yes \
      || { printf 'wipe-all-family: remove %s failed\n' "$id" >&2; fail=1; }
  fi
done
printf 'wipe-all-family: done (shared packages like python-pillow left installed)\n'
exit "$fail"
