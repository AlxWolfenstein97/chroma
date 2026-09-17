#!/bin/bash
# Full clean-slate: revert GTK/Qt CSS + gsettings, remove theme-set hook,
# hypr leftovers, root symlinks, state. Does not pacman -R adw-gtk-theme.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.chroma"
state="$HOME/.local/state/omarchy/chroma"

note() { printf 'chroma: %s\n' "$1"; }
warn() { printf 'chroma: %s\n' "$1" >&2; }

# Revert managed CSS / gsettings / qt env first.
if [[ -x $here/bin/chroma-apply ]]; then
  "$here/bin/chroma-apply" --revert || warn "revert reported an error"
fi

rm -f "$HOME/.config/omarchy/hooks/theme-set.d/chroma"
rm -f "$HOME/.config/hypr/chroma-envs.lua"
rm -f "$HOME/.config/environment.d/99-chroma-qt.conf"
rm -f "$HOME/.local/share/applications/qt6ct.desktop"

hl="$HOME/.config/hypr/hyprland.lua"
if [[ -f $hl ]] && grep -q 'hypr.chroma-envs' "$hl"; then
  tmp=$(mktemp)
  awk '
    /^-- Chroma: Qt platform theme override$/ { skip=1; next }
    skip && /^require\("hypr\.chroma-envs"\)$/ { skip=0; next }
    { skip=0; print }
  ' "$hl" >"$tmp" && mv -f "$tmp" "$hl"
  note "removed chroma require from hyprland.lua"
fi

# Root symlinks (optional teardown)
if [[ -f $state/root-linked ]]; then
  note "removing /root/.config chroma symlinks (password prompt)"
  if command -v pkexec >/dev/null 2>&1; then
    pkexec /bin/sh -c '
      for d in gtk-3.0 gtk-4.0 qt6ct qt5ct; do
        p=/root/.config/$d
        if [[ -L $p ]]; then rm -f "$p"; fi
      done
    ' || warn "could not remove root symlinks"
  fi
fi

if [[ -f /etc/sudoers.d/chroma-sync-root ]]; then
  note "removing legacy sudoers (password prompt)"
  if command -v pkexec >/dev/null 2>&1; then
    pkexec rm -f /etc/sudoers.d/chroma-sync-root || warn "could not remove sudoers"
  else
    sudo rm -f /etc/sudoers.d/chroma-sync-root || warn "could not remove sudoers"
  fi
fi

rm -rf "$state"
rm -rf "$HOME/.local/share/chroma"
rm -rf "$HOME/.cache/omarchy/chroma"
mkdir -p "$state"
touch "$state/uninstalled"
note "cleared state/cache (tombstone left so quiet install cannot resurrect)"

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — no chroma hook/CSS blocks/root links left"
note "adw-gtk-theme package kept — optional: omarchy pkg drop adw-gtk-theme"
note "plugin files remain at $here until you omit/remove the plugin"
note "  omarchy plugin remove $plugin_id"
exit 0
