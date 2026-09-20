#!/usr/bin/env bash
# Bulk full wipe of the AlxWolfenstein97 Style/Chroma extender family.
# Each plugin's `uninstall.sh --yes` already tears down + `plugin remove`.
# From home (same ease as arm-all-family):
#   ~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/tools/wipe-all-family.sh
#
# Single plugin: ~/.config/omarchy/plugins/io.github.alxwolfenstein97.<name>/uninstall.sh --yes
#
# Does NOT pacman -R shared deps (pillow etc.). Privileged teardown may still
# ask for a password once per plugin that needs it.
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
printf 'wipe-all-family: done (shared packages like python-pillow left installed)\n'
exit "$fail"
