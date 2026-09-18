#!/bin/bash
#
# Chroma installer. Safe to re-run: rewrites what it owns, leaves the rest alone.
#
# Flags:
#   --quiet       less chatter (used by the shell service on startup)
#   --with-root   one-time: symlink /root/.config GTK/Qt dirs to yours (pkexec)
#   --with-sudoers  alias for --with-root (old name)
#   --no-pkgs     skip package installs
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
quiet=0
with_root=0
no_pkgs=0
for arg in "$@"; do
  case $arg in
    --quiet) quiet=1 ;;
    --with-root|--with-sudoers) with_root=1 ;;
    --no-pkgs) no_pkgs=1 ;;
  esac
done

note() { (( quiet )) || printf 'chroma: %s\n' "$1"; }
warn() { printf 'chroma: %s\n' "$1" >&2; }

hooks="$HOME/.config/omarchy/hooks/theme-set.d"
hypr="$HOME/.config/hypr"
state="$HOME/.local/state/omarchy/chroma"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/omarchy-chroma"
pkgs_stamp="$runtime_dir/pkgs-prompted"

# Tombstone from uninstall. Disable-first in uninstall.sh means a later quiet
# Service run is a re-enable / re-add — clear tombstone + prompt stamps so the
# Style menu and package floaters can run again (old quiet-exit left peeps stuck
# with no floater after wipe).
if [[ -f $state/uninstalled ]]; then
  rm -f "$state/uninstalled" "$pkgs_stamp" \
    "$state/udev-prompted" "$state/udev-skipped" 2>/dev/null || true
fi


mkdir -p "$hooks" "$state"
chmod 755 "$here/bin/chroma-apply" "$here/bin/chroma-sync-root" \
  "$here/bin/chroma-link-root" "$here/omarchy/theme-set-hook"

# ------------------------------------------------------------------ packages
# adw-gtk-theme: GTK3 apps only honour libadwaita-style @define-color variables
# when the active gtk-theme is adw-gtk3 / adw-gtk3-dark. Without it, Chroma still
# writes CSS, but classic GTK3 chrome often stays beige (Accord-like). Not Pillow —
# Chroma has no Style carousel to warm (silent theme-set sync instead).
# Deliberately NOT qt6ct: Omarchy defaults to QT_QPA_PLATFORMTHEME=gtk3 so Qt
# inherits the GTK palette. Forcing qt6ct changed Quickshell icon lookup.
#
# Packages need sudo. Shared python-pillow is claimed under a flock so parallel
# quiet Services do not each open a Pillow floater. Scan pacman -Q first.
# Floater: plugin header + missing pkgs only; closable via Done / default answers.
pull_pkgs() {
  local -a missing=()
  local pkg
  local style_rt="${XDG_RUNTIME_DIR:-/tmp}/omarchy-style-extenders"
  local shared_ledger="$style_rt/shared-pkgs-claimed"
  local claim_tmp
  mkdir -p "$style_rt" "$runtime_dir" "$state"

  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
  done

  if ((${#missing[@]})); then
    claim_tmp=$(mktemp)
    (
      flock 8
      local claimed="" line
      [[ -f $shared_ledger ]] && claimed=$(cat "$shared_ledger" 2>/dev/null || true)
      local -a still=()
      for pkg in "${missing[@]}"; do
        if [[ $pkg == python-pillow ]] && grep -qxF python-pillow <<<"$claimed"; then
          continue
        fi
        still+=("$pkg")
        if [[ $pkg == python-pillow ]]; then
          printf '%s\n' python-pillow >>"$shared_ledger"
        fi
      done
      printf '%s\n' "${still[@]}" >"$claim_tmp"
    ) 8>"$style_rt/pkgs.lock"
    mapfile -t missing <"$claim_tmp"
    rm -f "$claim_tmp"
    # drop empty line from mapfile
    local -a cleaned=()
    for pkg in "${missing[@]}"; do
      [[ -n $pkg ]] && cleaned+=("$pkg")
    done
    missing=("${cleaned[@]}")
  fi

  if ((${#missing[@]} == 0)); then
    rm -f "$pkgs_stamp"
    return 0
  fi

  if ! command -v omarchy >/dev/null 2>&1; then
    warn "Chroma needs ${missing[*]} for: GTK / libadwaita theme sync with Omarchy palettes — install manually: pacman -S ${missing[*]}"
    return 1
  fi

  note "Chroma needs ${missing[*]} — GTK / libadwaita theme sync with Omarchy palettes"
  if (( ! quiet )) && [[ -t 0 || -t 1 ]]; then
    printf '%s\n' "Chroma"
    printf '%s\n' "io.github.alxwolfenstein97.chroma"
    printf '%s\n' "GTK / libadwaita theme sync with Omarchy palettes"
    printf '%s\n' "────────────────────────────────"
    printf '%s\n' "Needs to install (sudo / pacman) — only packages missing on this system:"
    for pkg in "${missing[@]}"; do
      case $pkg in
        adw-gtk-theme) printf '  • %s — %s\n' "$pkg" 'GTK theme Chroma paints over' ;;
        *) printf '  • %s\n' "$pkg" ;;
      esac
    done
    printf '%s\n' "────────────────────────────────"
    printf '%s\n' ""
    if omarchy pkg add "${missing[@]}"; then
      rm -f "$pkgs_stamp"
      return 0
    fi
    warn "Chroma could not install: ${missing[*]}"
    return 1
  fi

  if [[ -f $pkgs_stamp ]]; then
    warn "Chroma still missing ${missing[*]} (GTK / libadwaita theme sync with Omarchy palettes) — run: omarchy pkg add ${missing[*]}"
    return 1
  fi
  mkdir -p "$runtime_dir"
  touch "$pkgs_stamp"
  local script="$state/install-floater.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'
    printf '%s\n' "printf '%s\\n' 'Chroma'"
    printf '%s\n' "printf '%s\\n' 'io.github.alxwolfenstein97.chroma'"
    printf '%s\n' "printf '%s\\n' 'GTK / libadwaita theme sync with Omarchy palettes'"
    printf '%s\n' "printf '%s\\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\\n' 'Needs to install (sudo / pacman) — only packages missing on this system:'"
    for pkg in "${missing[@]}"; do
      case $pkg in
        adw-gtk-theme) printf '%s\n' "printf '  • %s — %s\\n' 'adw-gtk-theme' 'GTK theme Chroma paints over'" ;;
        *) printf '%s\n' "printf '  • %s\\n' $(printf %q "$pkg")" ;;
      esac
    done
    printf '%s\n' "printf '%s\\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\\n' ''"
    printf '%s\n' "omarchy pkg add ${missing[*]}"

  } >"$script"
  chmod 755 "$script"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    warn "Chroma missing ${missing[*]} (GTK / libadwaita theme sync with Omarchy palettes) — opening floating terminal"
    omarchy-launch-floating-terminal-with-presentation "bash $(printf %q "$script")" >/dev/null 2>&1 &
  else
    warn "Chroma: run omarchy pkg add ${missing[*]}"
  fi
  return 1
}




if (( ! no_pkgs )); then
  # Interactive: ask in this TTY. Quiet/Service: one floating terminal once
  # (pkgs-prompted). After adw-gtk lands, re-apply so gtk-theme flips to adw-gtk3*.
  PULL_PKGS_AFTER="\"$here/bin/chroma-apply\" --no-restart --no-root" \
    pull_pkgs adw-gtk-theme || true
fi

# --------------------------------------------------------------- theme hook
install -m 755 "$here/omarchy/theme-set-hook" "$hooks/chroma"
note "hook: $hooks/chroma"

# ---------------------------------------------- undo any prior qt6ct wiring
rm -f "$hypr/chroma-envs.lua"
rm -f "$HOME/.config/environment.d/99-chroma-qt.conf"
rm -f "$HOME/.local/share/applications/qt6ct.desktop"
hl="$hypr/hyprland.lua"
if [[ -f $hl ]] && grep -q 'hypr.chroma-envs' "$hl"; then
  tmp=$(mktemp)
  awk '
    /^-- Chroma: Qt platform theme override$/ { skip=1; next }
    skip && /^require\("hypr\.chroma-envs"\)$/ { skip=0; next }
    { skip=0; print }
  ' "$hl" >"$tmp" && mv -f "$tmp" "$hl"
  note "removed leftover qt6ct hypr override"
fi

# ---------------------------------------------------------------- root link
if (( with_root )); then
  if [[ -f $state/root-linked ]]; then
    note "root already linked ($state/root-linked)"
  else
    note "linking /root/.config GTK dirs to yours (password once)"
    link="$here/bin/chroma-link-root"
    if command -v pkexec >/dev/null 2>&1; then
      pkexec "$link" && note "root linked" \
        || warn "root link failed — sudo bleachbit will stay unthemed until this succeeds"
    else
      sudo "$link" && note "root linked" || warn "root link failed"
    fi
  fi
else
  if [[ ! -f $state/root-linked ]]; then
    note "root apps: run '$here/install.sh --with-root' once to theme sudo/pkexec BleachBit"
  fi
fi

# ------------------------------------------------------------------- apply
# Interactive install applies + hyprctl reload. Shell-service --quiet only does a
# soft apply (no app restarts / no hypr reload) so boots stay calm; theme-set
# hook covers later flips.
if [[ -x $here/bin/chroma-apply ]]; then
  if (( quiet )); then
    "$here/bin/chroma-apply" --no-restart --no-root >/dev/null 2>&1 || true
  else
    "$here/bin/chroma-apply" || warn "initial apply failed — check theme colors.toml"
    if command -v hyprctl >/dev/null 2>&1; then
      hyprctl reload >/dev/null 2>&1 || true
    fi
  fi
fi

note "done — Qt stays on Omarchy's gtk3 platform theme; GTK is fully chroma's"
exit 0
