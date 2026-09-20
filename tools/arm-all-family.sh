#!/usr/bin/env bash
# Arm Style-menu + theme-set consent for the whole AlxWolfenstein97 extender family.
# Safe to re-run. From anywhere (incl. home):
#   ~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/tools/arm-all-family.sh
set -euo pipefail
base="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
plugins=(chroma omacursor omaobs omahud omaboot omavt omatty)
fail=0
for p in "${plugins[@]}"; do
  inst="$base/io.github.alxwolfenstein97.$p/install.sh"
  if [[ ! -x $inst ]]; then
    printf 'arm-all-family: skip %s (not installed)\n' "$p"
    continue
  fi
  printf 'arm-all-family: %s --yes\n' "$p"
  if ! "$inst" --yes; then
    printf 'arm-all-family: %s failed\n' "$p" >&2
    fail=1
  fi
done
exit "$fail"
