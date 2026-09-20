#!/bin/bash
# Full clean-slate: revert GTK/Qt CSS + gsettings, remove theme-set hook,
# hypr leftovers, root symlinks, state. Headed floater for privileged teardown
# + optional adw-gtk-theme drop. Does not pacman -R unless you say y.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.chroma"
state="$HOME/.local/state/omarchy/chroma"

note() { printf 'chroma: %s\n' "$1"; }
warn() { printf 'chroma: %s\n' "$1" >&2; }

# Tombstone + disable first so Service --quiet cannot resurrect wiring.
mkdir -p "$state"
touch "$state/uninstalled"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

# Revert managed CSS / gsettings / qt env first (no sudo).
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

need_root=0
[[ -f $state/root-linked ]] && need_root=1
[[ -f /etc/sudoers.d/chroma-sync-root ]] && need_root=1

have_adw=0
pacman -Q adw-gtk-theme &>/dev/null && have_adw=1

launch_cleanup_floater() {
  (( need_root || have_adw )) || return 0
  local script="$state/uninstall-floater.sh"
  mkdir -p "$state"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'
    printf '%s\n' "printf '%s\n' 'Chroma — uninstall'"
    printf '%s\n' "printf '%s\n' 'io.github.alxwolfenstein97.chroma'"
    printf '%s\n' "printf '%s\n' 'GTK / libadwaita theme sync with Omarchy palettes'"
    printf '%s\n' "printf '%s\n' '────────────────────────────────'"
    if (( need_root )); then
      printf '%s\n' "printf '%s\n' 'Will remove (sudo / pkexec):'"
      printf '%s\n' "printf '%s\n' '  • /root/.config gtk/qt symlinks Chroma may have linked'"
      printf '%s\n' "printf '%s\n' '  • /etc/sudoers.d/chroma-sync-root (legacy, if present)'"
      printf '%s\n' "printf '%s\n' '────────────────────────────────'"
      printf '%s\n' "printf '%s\n' ''"
      printf '%s\n' "if command -v pkexec >/dev/null 2>&1; then"
      printf '%s\n' "  pkexec /bin/sh -c 'for d in gtk-3.0 gtk-4.0 qt6ct qt5ct; do p=/root/.config/\$d; [[ -L \$p ]] && rm -f \"\$p\"; done; rm -f /etc/sudoers.d/chroma-sync-root' \\"
      printf '%s\n' "    && printf 'root chroma wiring removed\n' || printf 'root teardown failed\n' >&2"
      printf '%s\n' "else"
      printf '%s\n' "  sudo bash -c 'for d in gtk-3.0 gtk-4.0 qt6ct qt5ct; do p=/root/.config/\$d; [[ -L \$p ]] && rm -f \"\$p\"; done; rm -f /etc/sudoers.d/chroma-sync-root' \\"
      printf '%s\n' "    && printf 'root chroma wiring removed\n' || printf 'root teardown failed\n' >&2"
      printf '%s\n' "fi"
    fi
    if (( have_adw )); then
      printf '%s
' ''
      printf '%s
' "printf '%s
' 'Optional package drops — scanned; only if installed.'"
      printf '%s
' "printf '%s
' 'Answer n / Enter to keep. Close with Done when finished.'"
      printf '%s
' "printf '%s
' ''"
      printf '%s
' "printf '%s
' 'adw-gtk-theme — GTK theme Chroma paints over'"
      printf '%s
' "read -r -p 'Drop adw-gtk-theme? [y/N] ' a"
      printf '%s
' 'case $a in'
      printf '%s
' "  [yY]|[yY][eE][sS]) omarchy pkg drop adw-gtk-theme && printf 'dropped adw-gtk-theme
' || printf 'not dropped
' ;;"
      printf '%s
' "  *) printf 'kept adw-gtk-theme
' ;;"
      printf '%s
' 'esac'
    fi
  } >"$script"
  chmod 755 "$script"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    note "Chroma opening floating terminal for root teardown / optional pkg drop"
    omarchy-launch-floating-terminal-with-presentation "bash $(printf %q "$script")" >/dev/null 2>&1 &
  else
    note "optional: finish root teardown by hand; omarchy pkg drop adw-gtk-theme"
  fi
}

# Remember root flag before state wipe.
root_linked=0
[[ -f $state/root-linked ]] && root_linked=1
need_root=$root_linked
[[ -f /etc/sudoers.d/chroma-sync-root ]] && need_root=1

rm -rf "$HOME/.local/share/chroma"
rm -rf "$HOME/.cache/omarchy/chroma"
find "$state" -mindepth 1 ! -name uninstalled -delete 2>/dev/null || true
touch "$state/uninstalled"
# Keep root-linked hint for the floater if we still need teardown
if (( root_linked )); then
  touch "$state/root-linked"
fi
note "cleared state/cache (tombstone left so quiet install cannot resurrect)"

launch_cleanup_floater

# Drop the hint after floater is launched (script already baked in).
rm -f "$state/root-linked"

note "done — no chroma hook/CSS blocks left; root/pkg cleanup in floating terminal when needed"
note "plugin files remain at $here until you omit/remove the plugin"
note "  omarchy plugin remove $plugin_id"
exit 0

rm -f "$state/armed-theme-hook" "$state/armed-style-menu" 2>/dev/null || true
