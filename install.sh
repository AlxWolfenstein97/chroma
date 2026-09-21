#!/bin/bash
#
# Chroma installer. Safe to re-run: rewrites what it owns, leaves the rest alone.
#
# Flags:
#   --quiet       shell service: restore armed wiring; no pkg floaters
#   --with-root   one-time: symlink /root/.config GTK/Qt dirs to yours
#                 (sudo on a TTY — arm-all / interactive; pkexec otherwise)
#   --with-sudoers  alias for --with-root (old name)
#   --no-pkgs     skip package installs
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.chroma"
quiet=0
with_style_menu=0
with_theme_hook=0
arm_all=0
assume_yes=0
with_root=0
no_pkgs=0
for arg in "$@"; do
  case $arg in
    --with-theme-hook) with_theme_hook=1 ;;
    --arm-all) arm_all=1 ;;
    --yes|-y) assume_yes=1; arm_all=1 ;;
    --quiet) quiet=1; no_pkgs=1 ;;  # Service: no pkg floaters; arm-all / interactive own deps
    --with-root|--with-sudoers) with_root=1 ;;
    --no-pkgs) no_pkgs=1 ;;
  esac
done

note() { (( quiet )) || printf 'chroma: %s\n' "$1"; }
warn() { printf 'chroma: %s\n' "$1" >&2; }

# Prefer sudo on a real TTY (arm-all / interactive install) so the password
# lands in the same terminal. pkexec needs a working polkit agent — fine for
# GUI menus, brittle in VMs / SSH / piped boom-in scripts.
# Always `command sudo` / absolute path so aliases like `sudo='sudo -A'` never
# steal the prompt in interactive wrappers.
elevate() {
  local sudo_bin=""
  if command -v sudo >/dev/null 2>&1; then
    sudo_bin=$(command -v sudo)
  elif [[ -x /usr/bin/sudo ]]; then
    sudo_bin=/usr/bin/sudo
  fi
  if { [[ -t 0 ]] || [[ -t 1 ]]; } && [[ -n $sudo_bin ]]; then
    command "$sudo_bin" "$@"
  elif command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
  elif [[ -n $sudo_bin ]]; then
    command "$sudo_bin" "$@"
  else
    return 127
  fi
}

# If a previous --with-root-before-apply left ~/.config/gtk-* owned by root,
# reclaim them so chroma-apply can write CSS.
repair_root_owned_gtk() {
  local -a owned=()
  local p
  for p in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" \
           "$HOME/.config/qt6ct" "$HOME/.config/qt5ct"; do
    [[ -e $p ]] || continue
    [[ -O $p ]] && continue
    owned+=("$p")
  done
  ((${#owned[@]})) || return 0
  warn "reclaiming root-owned GTK/Qt config dirs from a bad prior root-link: ${owned[*]}"
  elevate chown -R "$USER:" "${owned[@]}" \
    || warn "could not chown ${owned[*]} — apply may fail until fixed"
}

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
  # Per-plugin prompt stamps + shared Pillow claim. Claim survives an ignored
  # floater and would block pillow-only plugins (OmaBoot/OmaVT/OmaOBS) on
  # same-session reinstall — drop it with the tombstone. Shell restart does
  # *not* clear these (XDG_RUNTIME_DIR); only logout/reboot or reinstall.
  rm -f "$state/uninstalled" "$pkgs_stamp"     "$runtime_dir/drm-prompted"     "$state/udev-prompted" "$state/udev-skipped" 2>/dev/null || true
  style_rt="${XDG_RUNTIME_DIR:-/tmp}/omarchy-style-extenders"
  mkdir -p "$style_rt"
  (
    flock 8
    ledger="$style_rt/shared-pkgs-claimed"
    if [[ -f $ledger ]]; then
      grep -vxF python-pillow "$ledger" >"$ledger.tmp" 2>/dev/null || true
      if [[ -s $ledger.tmp ]]; then
        mv -f "$ledger.tmp" "$ledger"
      else
        rm -f "$ledger" "$ledger.tmp"
      fi
    fi
  ) 8>"$style_rt/pkgs.lock"
fi


mkdir -p "$hooks" "$state"

# --- marketplace consent: Style menu / theme-set hook are opt-in -----------
# Quiet Service must not write user config unless previously armed.
# Interactive asks; --with-style-menu / --with-theme-hook / --arm-all force.
# Existing hook/menu from older installs grandfather into armed-*.
arm_theme_hook=0
arm_style_menu=0
[[ -f $hooks/chroma ]] && arm_theme_hook=1
(( with_theme_hook || arm_all )) && arm_theme_hook=1
[[ -f $state/armed-theme-hook ]] && arm_theme_hook=1
[[ -f $state/armed-style-menu ]] && arm_style_menu=1
if (( ! quiet && ! assume_yes )); then
  if (( ! arm_theme_hook )); then
    printf '%s' "chroma: install theme-set auto-sync hook? [Y/n] "
    read -r _ans || _ans=
    case ${_ans:-Y} in [nN]|[nN][oO]) arm_theme_hook=0 ;; *) arm_theme_hook=1 ;; esac
  fi
fi
if (( arm_theme_hook )); then touch "$state/armed-theme-hook"; else rm -f "$state/armed-theme-hook"; fi
if (( arm_style_menu )); then touch "$state/armed-style-menu"; else rm -f "$state/armed-style-menu"; fi

chmod 755 "$here/bin/chroma-apply" "$here/bin/chroma-sync-root" \
  "$here/bin/chroma-link-root" "$here/omarchy/theme-set-hook" 2>/dev/null || true

# ------------------------------------------------------------------ packages
# adw-gtk-theme: GTK3 apps only honour libadwaita-style @define-color variables
# when the active gtk-theme is adw-gtk3 / adw-gtk3-dark. Without it, Chroma still
# writes CSS, but classic GTK3 chrome often stays beige (Accord-like). Not Pillow —
# Chroma has no Style carousel to warm (silent theme-set sync instead).
# Deliberately NOT qt6ct: Omarchy defaults to QT_QPA_PLATFORMTHEME=gtk3 so Qt
# inherits the GTK palette. Forcing qt6ct changed Quickshell icon lookup.
#
# Packages need sudo. Shared python-pillow claimed under a flock so parallel
# install.sh runs do not each race a Pillow pull. Scan pacman -Q first.
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
  # Inline pkg add (interactive or --yes). No floaters.
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
    # Flip gtk-theme to adw-gtk3* as soon as the package lands (arm-all may
    # have installed it already — then the later apply path covers it).
    if [[ -n ${PULL_PKGS_AFTER:-} ]]; then
      # shellcheck disable=SC2086
      eval "$PULL_PKGS_AFTER" || true
    fi
    return 0
  fi
  warn "Chroma could not install: ${missing[*]}"
  return 1
}

if (( ! no_pkgs )); then
  # After adw-gtk lands, re-apply so gtk-theme flips to adw-gtk3*.
  PULL_PKGS_AFTER="\"$here/bin/chroma-apply\" --no-restart --no-root" \
    pull_pkgs adw-gtk-theme || true
fi

# --------------------------------------------------------------- theme hook
if (( arm_theme_hook )); then
  install -m 755 "$here/omarchy/theme-set-hook" "$hooks/chroma"
  note "hook: $hooks/chroma"
else
  rm -f "$hooks/chroma"
  note "theme-set hook skipped — run: $here/tools/install-theme-hook.sh"
fi

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

# Reclaim ~/.config/gtk-* if a prior root-link created them as root (fresh VM
# boom-in used to link before apply — CSS writes then failed forever).
repair_root_owned_gtk

run_apply() {
  local extra=()
  (( $# )) && extra=("$@")
  # Prefer python3 so a lost +x bit cannot silently skip theming.
  if command -v python3 >/dev/null 2>&1; then
    python3 "$here/bin/chroma-apply" "${extra[@]}"
  elif [[ -x $here/bin/chroma-apply ]]; then
    "$here/bin/chroma-apply" "${extra[@]}"
  else
    return 127
  fi
}

# ------------------------------------------------------------------- apply
# MUST run before --with-root so ~/.config/gtk-* exist as the user. Linking
# first on a fresh machine mkdir'd those dirs as root and blocked all CSS.
if (( arm_theme_hook )); then
  if (( quiet )); then
    run_apply --no-restart --no-root >/dev/null 2>&1 || true
  else
    if run_apply --no-restart; then
      note "GTK palette applied"
    else
      warn "initial apply failed — check ~/.local/state/omarchy/current/theme/colors.toml"
    fi
    # Verify adw-gtk is actually selected when the package is present.
    if pacman -Q adw-gtk-theme &>/dev/null && command -v gsettings >/dev/null 2>&1; then
      _gtk=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)
      case $_gtk in
        *adw-gtk3*) ;;
        *)
          warn "gtk-theme is ${_gtk:-unknown} after apply (want adw-gtk3*) — retrying"
          run_apply --no-restart || true
          ;;
      esac
    fi
  fi
elif (( ! arm_theme_hook )); then
  note "GTK apply skipped until theme-set hook is armed"
fi

# ---------------------------------------------------------------- root link
# Optional — after apply so user GTK dirs already exist. Failure must not
# abort GTK arming (arm-all continues either way).
if (( with_root )); then
  if [[ -f $state/root-linked ]]; then
    note "root already linked ($state/root-linked)"
  else
    note "linking /root/.config GTK dirs to yours (password once — sudo on TTY)"
    link="$here/bin/chroma-link-root"
    if elevate "$link"; then
      note "root linked"
    else
      warn "root link failed — GTK theming still armed; re-run: $here/install.sh --with-root"
    fi
  fi
else
  if [[ ! -f $state/root-linked ]]; then
    note "root apps: run '$here/install.sh --with-root' once to theme sudo/pkexec BleachBit"
  fi
fi

# Match siblings — keep the Service enabled after uninstall→re-arm / arm-all.
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin enable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — Qt stays on Omarchy's gtk3 platform theme; GTK is fully chroma's"
exit 0
