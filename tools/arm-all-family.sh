#!/usr/bin/env bash
# True one-shot IN for whatever of the AlxWolfenstein97 extender family is
# already installed (you pick plugins yourself with `plugin add`):
#   1. collect missing deps once → omarchy pkg add
#   2. arm Style / theme-set (--yes)
#   3. chroma --with-root, omacursor --with-sddm, omatty --with-drm-reapply
#
# Privileged steps use sudo on a TTY (may ask a few passwords). GTK / Style /
# cursors still arm if a root/SDDM step is declined.
#
# `omarchy plugin add …` only clones + enables the shell service. That service
# runs install.sh --quiet, which restores already-armed wiring and does NOT
# open package floaters (marketplace consent). Boom-in = add plugins, then
# this script once. Piece-meal still works: run each install.sh interactively
# (TTY prompts) instead of arm-all.
#
#   ~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/tools/arm-all-family.sh
set -euo pipefail

base="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
plugins=(chroma omacursor omaobs omahud omaboot omavt omatty)

# plugin → packages that install.sh may pull
declare -A pkgs_for=(
  [chroma]="adw-gtk-theme"
  [omacursor]="python-pillow python-numpy"
  [omaobs]="python-pillow"
  [omahud]="python-pillow"
  [omaboot]="python-pillow"
  [omavt]="python-pillow"
  [omatty]="python-pillow terminus-font"
)

installed=()
for p in "${plugins[@]}"; do
  inst="$base/io.github.alxwolfenstein97.$p/install.sh"
  [[ -x $inst ]] || continue
  installed+=("$p")
done

if ((${#installed[@]} == 0)); then
  printf 'arm-all-family: nothing installed — plugin add first, then re-run\n' >&2
  exit 1
fi

printf 'arm-all-family: installed → %s\n' "${installed[*]}"

# ---- one package pass -------------------------------------------------------
declare -A want=()
for p in "${installed[@]}"; do
  # shellcheck disable=SC2206
  for pkg in ${pkgs_for[$p]}; do
    want[$pkg]=1
  done
done

missing=()
for pkg in "${!want[@]}"; do
  pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
done

if ((${#missing[@]})); then
  printf 'arm-all-family: installing deps once: %s\n' "${missing[*]}"
  if command -v omarchy >/dev/null 2>&1; then
    omarchy pkg add "${missing[@]}" || {
      printf 'arm-all-family: pkg add failed — fix packages, then re-run\n' >&2
      exit 1
    }
  else
    printf 'arm-all-family: omarchy CLI missing — pacman -S %s\n' "${missing[*]}" >&2
    exit 1
  fi
else
  printf 'arm-all-family: deps already present\n'
fi

# ---- arm each plugin (extras for root / SDDM / DRM) -------------------------
fail=0
for p in "${installed[@]}"; do
  inst="$base/io.github.alxwolfenstein97.$p/install.sh"
  args=(--yes)
  case $p in
    chroma) args+=(--with-root) ;;
    omacursor) args+=(--with-sddm) ;;
    omatty) args+=(--with-drm-reapply) ;;
  esac
  printf 'arm-all-family: %s %s\n' "$p" "${args[*]}"
  if ! "$inst" "${args[@]}"; then
    printf 'arm-all-family: %s failed\n' "$p" >&2
    fail=1
  fi
done

printf 'arm-all-family: done\n'
exit "$fail"
