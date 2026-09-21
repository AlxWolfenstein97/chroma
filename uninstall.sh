#!/bin/bash
# Full clean-slate: revert GTK/Qt CSS + gsettings, remove theme-set hook,
# hypr leftovers, root symlinks, state. Root teardown + optional adw-gtk drop
# in this TTY (or best-effort on --yes). No floaters.
set -euo pipefail

assume_yes=0
for arg in "$@"; do
  case $arg in --yes|-y) assume_yes=1 ;; esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.chroma"
state="$HOME/.local/state/omarchy/chroma"

note() { printf 'chroma: %s\n' "$1"; }
warn() { printf 'chroma: %s\n' "$1" >&2; }

# Prefer sudo on a TTY (wipe-all / interactive) so the password lands in the
# same terminal. pkexec is for GUI / non-TTY launches with a polkit agent.
elevate() {
  if { [[ -t 0 ]] || [[ -t 1 ]]; } && command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    return 127
  fi
}

try_pkg_drop() {
  # Best-effort: drop packages we may have pulled. If something else still
  # needs them, pacman refuses and we leave them — that is fine.
  local pkg
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null || continue
    if command -v omarchy >/dev/null 2>&1 && omarchy pkg drop "$pkg"; then
      note "dropped $pkg"
    else
      note "kept $pkg (still required elsewhere or drop failed — fine)"
    fi
  done
}

ask_pkg_drop() {
  # Interactive — prompts in this terminal (no floater).
  local -a have=()
  local pkg a req
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null && have+=("$pkg")
  done
  ((${#have[@]})) || return 0
  note "optional package drops — n / Enter keeps; pacman may refuse if still required"
  for pkg in "${have[@]}"; do
    case $pkg in
      python-pillow)
        note "python-pillow — Style carousel mockups (shared); MangoHud/goverlay/Lutris may need it"
        req=$(pacman -Qi python-pillow 2>/dev/null | awk -F': ' '/^Required By/{print $2}')
        note "  pacman Required By: ${req:-none}"
        ;;
      python-numpy)
        note "python-numpy — OmaCursor Adwaita remaps"
        req=$(pacman -Qi python-numpy 2>/dev/null | awk -F': ' '/^Required By/{print $2}')
        note "  pacman Required By: ${req:-none}"
        ;;
      terminus-font)
        note "terminus-font — OmaTTY console faces"
        ;;
      adw-gtk-theme)
        note "adw-gtk-theme — GTK theme Chroma paints over"
        ;;
      *)
        note "package: $pkg"
        ;;
    esac
    read -r -p "Drop $pkg? [y/N] " a || a=
    case $a in
      [yY]|[yY][eE][sS]) try_pkg_drop "$pkg" ;;
      *) note "kept $pkg" ;;
    esac
  done
}



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



# Remember root flag before state wipe.
root_linked=0
[[ -f $state/root-linked ]] && root_linked=1
need_root=$root_linked
[[ -f /etc/sudoers.d/chroma-sync-root ]] && need_root=1

rm -rf "$HOME/.local/share/chroma"
rm -rf "$HOME/.cache/omarchy/chroma"
find "$state" -mindepth 1 ! -name uninstalled -delete 2>/dev/null || true
touch "$state/uninstalled"
# Keep root-linked hint until teardown finishes
if (( root_linked )); then
  touch "$state/root-linked"
fi
note "cleared state/cache (tombstone left so quiet install cannot resurrect)"

root_teardown() {
  (( need_root )) || return 0
  note "removing root chroma wiring (password once — sudo on TTY)"
  root_cmd='for d in gtk-3.0 gtk-4.0 qt6ct qt5ct; do p=/root/.config/$d; [[ -L $p ]] && rm -f "$p"; done; rm -f /etc/sudoers.d/chroma-sync-root'
  if elevate /bin/sh -c "$root_cmd"; then
    note "root chroma wiring removed"
  else
    note "root teardown failed — remove /root/.config/gtk-* symlinks by hand if needed"
  fi
}

if (( assume_yes )); then
  note "full wipe (--yes): root teardown + package drops inline"
  root_teardown
  try_pkg_drop adw-gtk-theme
else
  root_teardown
  ask_pkg_drop adw-gtk-theme
fi

rm -f "$state/root-linked"
rm -f "$state/armed-theme-hook" "$state/armed-style-menu" 2>/dev/null || true

note "done — no chroma hook/CSS blocks left"
if (( assume_yes )); then
  note "full wipe (--yes): removing plugin $plugin_id"
  if command -v omarchy >/dev/null 2>&1; then
    # Leave the tree before Omarchy deletes it out from under us.
    cd "${HOME:-/}" || cd /
    omarchy plugin remove "$plugin_id" --yes \
      || note "plugin remove failed — try: omarchy plugin remove $plugin_id --yes"
  else
    note "omarchy CLI missing — delete by hand: $here"
  fi
else
  note "plugin files remain at $here until you omit/remove the plugin"
  note "  omarchy plugin remove $plugin_id"
fi

exit 0
