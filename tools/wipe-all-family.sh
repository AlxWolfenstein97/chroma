#!/usr/bin/env bash
# Bulk full wipe of the AlxWolfenstein97 Style/Chroma extender family.
# Each plugin's `uninstall.sh --yes` tears down, best-effort drops the
# packages that plugin may have pulled (kept if something else still needs
# them), then `plugin remove`.
# From home (same ease as arm-all-family):
#   ~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/tools/wipe-all-family.sh
#
# Single plugin: ~/.config/omarchy/plugins/io.github.alxwolfenstein97.<name>/uninstall.sh --yes
#
# Privileged teardown may still ask for a password once per plugin that needs it.
set -euo pipefail
base="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
# Chroma last so this script's tree is not deleted mid-loop.
plugins=(omacursor omaobs omahud omaboot omavt omatty chroma)
fail=0
for p in "${plugins[@]}"; do
  id="io.github.alxwolfenstein97.$p"
  un="$base/$id/uninstall.sh"
  if [[ ! -x $un ]]; then
    printf 'wipe-all-family: skip %s (not installed)\n' "$p"
    continue
  fi
  printf 'wipe-all-family: %s uninstall --yes\n' "$p"
  if ! "$un" --yes; then
    printf 'wipe-all-family: %s failed\n' "$p" >&2
    fail=1
  fi
done

# Final shared-dep sweep — each uninstall already tried its own list; this
# catches leftovers (e.g. pillow claimed by a sibling that wiped earlier).
# pacman keeps anything still Required By elsewhere.
printf 'wipe-all-family: final shared package sweep\n'
for pkg in python-pillow python-numpy adw-gtk-theme terminus-font; do
  pacman -Q "$pkg" &>/dev/null || continue
  if command -v omarchy >/dev/null 2>&1 && omarchy pkg drop "$pkg"; then
    printf 'wipe-all-family: dropped %s\n' "$pkg"
  else
    printf 'wipe-all-family: kept %s (still required elsewhere or drop failed — fine)\n' "$pkg"
  fi
done

printf 'wipe-all-family: done\n'
exit "$fail"
