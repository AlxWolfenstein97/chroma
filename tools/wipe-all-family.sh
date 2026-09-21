#!/usr/bin/env bash
# True one-shot OUT for the AlxWolfenstein97 Style/Chroma extender family.
# Each uninstall.sh --yes:
#   • tears down menus/hooks/state
#   • resets privileged paint inline (Limine / VT / FONT / chroma root) — no floater Y/n
#   • best-effort omarchy pkg drop for packages that plugin may have pulled
#   • omarchy plugin remove
# Then a final shared-dep sweep (pillow / numpy / adw / terminus).
#
# Interactive per-plugin uninstall.sh (no --yes) uses this TTY for privileged
# reset + optional pkg Y/n — no floaters. No TTY → re-run from a terminal or --yes.
#
#   ~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/tools/wipe-all-family.sh
#
# Single plugin: ~/.config/omarchy/plugins/io.github.alxwolfenstein97.<name>/uninstall.sh --yes
set -euo pipefail

base="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
# Hint uninstall scripts to prefer inline privileged resets (belt + suspenders
# with --yes). Chroma last so this tree is not deleted mid-loop.
export STYLE_EXTENDERS_ONESHOT=1
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
