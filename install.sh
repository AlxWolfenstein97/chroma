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

# Tombstone from uninstall: Service --quiet must not resurrect wiring.
if [[ -f $state/uninstalled ]]; then
  if (( quiet )); then
    exit 0
  fi
  rm -f "$state/uninstalled"
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
# Packages need sudo. Interactive install asks in this TTY; Service --quiet
# opens one floating terminal once (pkgs-prompted) — not again every boot.
pull_pkgs() {
  local -a missing=()
  local pkg
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
  done
  if ((${#missing[@]} == 0)); then
    rm -f "$state/pkgs-prompted"
    return 0
  fi

  if ! command -v omarchy >/dev/null 2>&1; then
    warn "install manually: pacman -S ${missing[*]}"
    return 1
  fi

  note "installing ${missing[*]}"
  if (( ! quiet )) && [[ -t 0 || -t 1 ]]; then
    if omarchy pkg add "${missing[@]}"; then
      rm -f "$state/pkgs-prompted"
      return 0
    fi
    warn "could not install: ${missing[*]}"
    return 1
  fi

  if [[ -f $state/pkgs-prompted ]]; then
    warn "still missing ${missing[*]} — run: omarchy pkg add ${missing[*]}"
    return 1
  fi
  mkdir -p "$state"
  touch "$state/pkgs-prompted"
  local cmd="omarchy pkg add ${missing[*]}"
  [[ -n ${PULL_PKGS_AFTER:-} ]] && cmd+=" && ${PULL_PKGS_AFTER}"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    warn "sudo needed for ${missing[*]} — opening a floating terminal"
    omarchy-launch-floating-terminal-with-presentation "$cmd" >/dev/null 2>&1 &
  else
    warn "run: $cmd"
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
