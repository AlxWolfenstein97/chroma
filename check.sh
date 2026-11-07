#!/bin/bash
# Lightweight self-check for Chroma (no full Accord-style suite).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
pass() { printf 'ok  %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=1; }

[[ -x $here/bin/chroma-apply ]] || bad "chroma-apply not executable"
[[ -x $here/bin/chroma-sync-root ]] || bad "chroma-sync-root not executable"
[[ -f $here/manifest.json ]] || bad "manifest.json missing"

# Hermetic apply against a temp theme.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/theme" "$tmp/gtk4" "$tmp/gtk3" "$tmp/state" "$tmp/stage" "$tmp/themes"
cat >"$tmp/theme/colors.toml" <<'EOF'
mode = "dark"
accent = "#FF3D9A"
background = "#0B0618"
foreground = "#F2E8FF"
dark_background = "#070412"
darker_background = "#04020C"
lighter_background = "#1A1030"
muted = "#5A4A78"
selection = "#2A1848"
red = "#FF3355"
green = "#3DFF9A"
yellow = "#FFD400"
blue = "#5B7CFF"
magenta = "#FF3D9A"
cyan = "#00E8FF"
EOF

export CHROMA_THEME_DIR="$tmp/theme"
export CHROMA_GTK4_CSS="$tmp/gtk4/gtk.css"
export CHROMA_GTK3_CSS="$tmp/gtk3/gtk.css"
export CHROMA_GTK4_INI="$tmp/gtk4/settings.ini"
export CHROMA_GTK3_INI="$tmp/gtk3/settings.ini"
export CHROMA_STATE_DIR="$tmp/state"
export CHROMA_ROOT_STAGE="$tmp/stage"
export CHROMA_THEMES_DIR="$tmp/themes"
export CHROMA_NO_GSETTINGS=1
export CHROMA_NO_ROOT=1
export CHROMA_NO_QT_ENV=1
export CHROMA_QT6_DIR="$tmp/qt6"
export CHROMA_QT5_DIR="$tmp/qt5"
export CHROMA_QT_ENV_FILE="$tmp/environment.d/99-chroma-qt.conf"

# A window-manager snapshot plus a fake /proc lets the libhandy hint be tested
# hermetically: only processes whose maps mention libhandy are reported.
mkdir -p "$tmp/proc/9001" "$tmp/proc/9002"
printf '/usr/lib/libhandy-1.so.0\n' >"$tmp/proc/9001/maps"
printf '/usr/lib/libgtk-3.so.0\n' >"$tmp/proc/9002/maps"
cat >"$tmp/clients.json" <<'EOF'
[
  {"pid": 9001, "class": "org.gnome.DiskUtility", "title": "Disks"},
  {"pid": 9002, "class": "org.gnome.Nautilus", "title": "Files"}
]
EOF
export CHROMA_PROC_ROOT="$tmp/proc"
export CHROMA_WINDOWED_JSON="$tmp/clients.json"

# A user-written environment.d override must survive apply/revert. Only files
# carrying Chroma's ownership marker (or an empty Chroma-unique stub) are ours.
mkdir -p "$tmp/environment.d"
printf 'QT_QPA_PLATFORMTHEME=qt6ct\n' >"$CHROMA_QT_ENV_FILE"

# ---------------------------------------------------------------------------
# Default mode: user CSS, restart-only. No wrapper rotation, no libhandy hint.
# ---------------------------------------------------------------------------
if out=$("$here/bin/chroma-apply" --no-restart --no-root); then
  pass "apply dark fixture"
else
  bad "apply dark fixture"
fi
echo "$out" | grep -q 'gtk3 wrapper' \
  && bad "default apply rotates a wrapper ($out)" \
  || pass "default apply uses user CSS"
echo "$out" | grep -q 'relaunch ' \
  && bad "default mode reports libhandy relaunch" \
  || pass "default mode does not report libhandy relaunch"

grep -q 'accent_bg_color #ff3d9a' "$tmp/gtk4/gtk.css" && pass "gtk4 accent" || bad "gtk4 accent"
grep -q 'chroma:managed' "$tmp/gtk3/gtk.css" 2>/dev/null \
  && pass "default mode writes gtk3 user css" || bad "default mode writes gtk3 user css"
grep -q 'theme_bg_color #0b0618' "$tmp/gtk3/gtk.css" 2>/dev/null \
  && pass "gtk3 user css bg" || bad "gtk3 user css bg"
base=$(sed -n 's/^gtk-theme-name=//p' "$tmp/gtk3/settings.ini")
case $base in
  '') bad "gtk3 base theme name is empty" ;;
  *-chroma-a|*-chroma-b) bad "default mode points at a wrapper ($base)" ;;
  *) pass "default mode uses base theme ($base)" ;;
esac
shopt -s nullglob
default_wrappers=("$tmp/themes"/*-chroma-*)
shopt -u nullglob
((${#default_wrappers[@]} == 0)) \
  && pass "default mode writes no wrappers" \
  || bad "default mode left wrappers: ${default_wrappers[*]}"

# Apply must not delete a user-owned environment.d file (ownership marker).
[[ -f $CHROMA_QT_ENV_FILE ]] && grep -q 'qt6ct' "$CHROMA_QT_ENV_FILE" \
  && pass "apply keeps unowned environment.d file" \
  || bad "apply deleted an unowned environment.d file"

[[ -f $tmp/state/state.json ]] && pass "state.json" || bad "state.json"
grep -q '"enabled": false' "$tmp/state/state.json" \
  && pass "state records legacy mode" || bad "state records legacy mode"
[[ -f $tmp/stage/manifest.json ]] && pass "root stage manifest" || bad "root stage manifest"
[[ -f $tmp/stage/gtk-3.0/gtk.css ]] && pass "root stage gtk3 css" || bad "root stage gtk3 css"
[[ ! -d $tmp/stage/themes ]] \
  && pass "legacy stage copies no wrapper" || bad "legacy stage copies a wrapper"

# Sidebar/places panes must read as a distinct surface from the file view.
hex_luma() { local h=${1#\#}; echo $(( (0x${h:0:2} * 299 + 0x${h:2:2} * 587 + 0x${h:4:2} * 114) / 1000 )); }
view_hex=$(sed -n 's/^@define-color view_bg_color \(#[0-9a-f]*\);/\1/p' "$tmp/gtk4/gtk.css" | head -1)
side_hex=$(sed -n 's/^@define-color sidebar_bg_color \(#[0-9a-f]*\);/\1/p' "$tmp/gtk4/gtk.css" | head -1)
if [[ -n $view_hex && -n $side_hex && $view_hex != "$side_hex" ]] \
  && (( $(hex_luma "$side_hex") > $(hex_luma "$view_hex") )); then
  pass "sidebar brighter than view"
else
  bad "sidebar brighter than view (view=$view_hex sidebar=$side_hex)"
fi
grep -q 'chroma:managed' "$tmp/gtk4/settings.ini" && pass "gtk4 settings.ini" || bad "gtk4 settings.ini"

# Idempotent re-apply (same palette → same files, no rewrite).
out=$("$here/bin/chroma-apply" --no-restart --no-root)
echo "$out" | grep -q 'gtk4 unchanged' && pass "idempotent gtk4" || bad "idempotent gtk4 ($out)"
echo "$out" | grep -q 'gtk3 unchanged' && pass "idempotent gtk3" || bad "idempotent gtk3 ($out)"
echo "$out" | grep -q "theme $base" && pass "idempotent base theme" || bad "idempotent base theme ($out)"

# An empty Chroma-unique stub is safe to prune; a marked legacy file too.
: >"$CHROMA_QT_ENV_FILE"
"$here/bin/chroma-apply" --no-restart --no-root >/dev/null
[[ ! -e $CHROMA_QT_ENV_FILE ]] && pass "apply prunes empty environment.d stub" \
  || bad "apply leaves empty environment.d stub"
printf '# Managed by Chroma — legacy Qt override\nQT_QPA_PLATFORMTHEME=gtk3\n' >"$CHROMA_QT_ENV_FILE"
"$here/bin/chroma-apply" --no-restart --no-root >/dev/null
[[ ! -e $CHROMA_QT_ENV_FILE ]] && pass "apply removes owned environment.d file" \
  || bad "apply leaves owned environment.d file"

# A palette change in default mode updates the user CSS in place; the theme
# name stays the base theme, so nothing rotates and no window is repainted.
sed -i 's/background = "#0B0618"/background = "#0B0620"/' "$tmp/theme/colors.toml"
out=$("$here/bin/chroma-apply" --no-restart --no-root)
grep -q 'theme_bg_color #0b0620' "$tmp/gtk3/gtk.css" 2>/dev/null \
  && pass "default mode follows palette" || bad "default mode follows palette"
[[ $(sed -n 's/^gtk-theme-name=//p' "$tmp/gtk3/settings.ini") == "$base" ]] \
  && pass "default mode keeps base theme on change" \
  || bad "default mode changed theme name on palette change"

# ---------------------------------------------------------------------------
# Live mode is opt-in: --gtk-wrapper generates a rotating theme so GTK3 and Qt
# repaint without a relaunch.
# ---------------------------------------------------------------------------
out=$("$here/bin/chroma-apply" --no-restart --no-root --gtk-wrapper)
echo "$out" | grep -q 'gtk3 wrapper' \
  && pass "wrapper opt-in switches mode ($out)" \
  || bad "wrapper opt-in switches mode ($out)"
wrap=$(sed -n 's/^gtk-theme-name=//p' "$tmp/gtk3/settings.ini")
case $wrap in
  *-chroma-a|*-chroma-b) pass "gtk3 wrapper theme name ($wrap)" ;;
  *) bad "gtk3 wrapper theme name ($wrap)" ;;
esac
wcss="$tmp/themes/$wrap/gtk-3.0/gtk.css"
grep -q 'chroma:managed' "$wcss" 2>/dev/null && pass "wrapper carries managed block" || bad "wrapper carries managed block"
grep -q 'theme_bg_color #0b0620' "$wcss" 2>/dev/null && pass "gtk3 wrapper bg" || bad "gtk3 wrapper bg"
if [[ -f $tmp/gtk3/gtk.css ]] && grep -q 'chroma:managed' "$tmp/gtk3/gtk.css"; then
  bad "wrapper mode strips user gtk3 block"
else
  pass "wrapper mode strips user gtk3 block"
fi

# A switch to dark pins open libhandy windows to stock Adwaita; name them so
# the user knows what to relaunch. Non-libhandy windows must stay quiet.
echo "$out" | grep -q 'relaunch Disks (libhandy pinned to Adwaita)' \
  && pass "dark wrapper switch reports libhandy relaunch" \
  || bad "dark wrapper switch reports libhandy relaunch ($out)"
echo "$out" | grep -q 'Nautilus' \
  && bad "non-libhandy window reported" \
  || pass "non-libhandy window not reported"

[[ -f $tmp/stage/themes/$wrap/gtk-3.0/gtk.css ]] && pass "root stage theme" || bad "root stage theme"

# Persistent opt-in lives in the environment; the explicit off switch wins
# over it and the one-shot flag wins over the environment.
out=$(CHROMA_GTK_WRAPPER=1 "$here/bin/chroma-apply" --no-restart --no-root)
echo "$out" | grep -q 'gtk3 wrapper' \
  && pass "CHROMA_GTK_WRAPPER=1 opts in" || bad "CHROMA_GTK_WRAPPER=1 opts in ($out)"
out=$(CHROMA_GTK_WRAPPER=1 "$here/bin/chroma-apply" --no-restart --no-root --no-gtk-wrapper)
echo "$out" | grep -q 'gtk3 wrapper' \
  && bad "--no-gtk-wrapper loses to env opt-in" \
  || pass "--no-gtk-wrapper overrides env opt-in"
grep -q 'chroma:managed' "$tmp/gtk3/gtk.css" 2>/dev/null \
  && pass "override writes user css" || bad "override writes user css"
out=$(CHROMA_NO_GTK_WRAPPER=1 "$here/bin/chroma-apply" --no-restart --no-root --gtk-wrapper)
echo "$out" | grep -q 'gtk3 wrapper' \
  && pass "--gtk-wrapper overrides env off switch" \
  || bad "--gtk-wrapper overrides env off switch ($out)"
out=$(CHROMA_GTK_WRAPPER=1 CHROMA_NO_GTK_WRAPPER=1 "$here/bin/chroma-apply" --no-restart --no-root)
echo "$out" | grep -q 'gtk3 wrapper' \
  && bad "CHROMA_NO_GTK_WRAPPER=1 loses to opt-in" \
  || pass "CHROMA_NO_GTK_WRAPPER=1 wins over opt-in"

# Palette change rotates to the other wrapper name so GTK3/Qt reload live.
"$here/bin/chroma-apply" --no-restart --no-root --gtk-wrapper >/dev/null
wrap=$(sed -n 's/^gtk-theme-name=//p' "$tmp/gtk3/settings.ini")
sed -i 's/background = "#0B0620"/background = "#0B0628"/' "$tmp/theme/colors.toml"
out=$("$here/bin/chroma-apply" --no-restart --no-root --gtk-wrapper)
newwrap=$(sed -n 's/^gtk-theme-name=//p' "$tmp/gtk3/settings.ini")
if [[ $newwrap != "$wrap" ]]; then
  pass "wrapper rotation ($wrap → $newwrap)"
else
  bad "wrapper rotation did not change name ($newwrap)"
fi
grep -q 'theme_bg_color #0b0628' "$tmp/themes/$newwrap/gtk-3.0/gtk.css" 2>/dev/null \
  && pass "rotated wrapper has new color" || bad "rotated wrapper has new color"
[[ -f $tmp/stage/themes/$newwrap/gtk-3.0/gtk.css ]] \
  && pass "root stage follows active wrapper" || bad "root stage follows active wrapper"
[[ ! -d $tmp/stage/themes/$wrap ]] \
  && pass "root stage prunes stale wrappers" || bad "root stage prunes stale wrappers"

# A switch to a light theme makes libhandy reset its pin instead of setting it,
# so those windows recover live and no relaunch hint is needed.
sed -i 's/mode = "dark"/mode = "light"/' "$tmp/theme/colors.toml"
out=$("$here/bin/chroma-apply" --no-restart --no-root --gtk-wrapper)
echo "$out" | grep -q 'relaunch ' \
  && bad "light switch reports libhandy relaunch" \
  || pass "light switch does not report libhandy relaunch"
sed -i 's/mode = "light"/mode = "dark"/' "$tmp/theme/colors.toml"
"$here/bin/chroma-apply" --no-restart --no-root --gtk-wrapper >/dev/null

# Escape hatch: default mode also prunes wrappers left by an earlier opt-in.
out=$("$here/bin/chroma-apply" --no-restart --no-root --no-gtk-wrapper)
grep -q 'chroma:managed' "$tmp/gtk3/gtk.css" 2>/dev/null \
  && pass "escape hatch writes user css" || bad "escape hatch writes user css"
[[ $(sed -n 's/^gtk-theme-name=//p' "$tmp/gtk3/settings.ini") == "$base" ]] \
  && pass "escape hatch uses base theme" \
  || bad "escape hatch uses base theme ($base)"
shopt -s nullglob
leftover=("$tmp/themes"/*-chroma-*)
shopt -u nullglob
((${#leftover[@]} == 0)) \
  && pass "escape hatch prunes old wrappers" \
  || bad "escape hatch leaves wrappers: ${leftover[*]}"

# Revert restores the base theme before deleting generated wrappers.
# It must also respect environment.d ownership.
"$here/bin/chroma-apply" --no-restart --no-root --gtk-wrapper >/dev/null
printf 'QT_QPA_PLATFORMTHEME=qt5ct\n' >"$CHROMA_QT_ENV_FILE"
"$here/bin/chroma-apply" --revert >/dev/null
[[ -f $CHROMA_QT_ENV_FILE ]] && grep -q 'qt5ct' "$CHROMA_QT_ENV_FILE" \
  && pass "revert keeps unowned environment.d file" \
  || bad "revert deleted an unowned environment.d file"
printf '# Managed by Chroma — legacy Qt override\n' >"$CHROMA_QT_ENV_FILE"
"$here/bin/chroma-apply" --revert >/dev/null
[[ ! -e $CHROMA_QT_ENV_FILE ]] && pass "revert removes owned environment.d file" \
  || bad "revert leaves owned environment.d file"
[[ ! -f $tmp/gtk4/gtk.css ]] || ! grep -q 'chroma:managed' "$tmp/gtk4/gtk.css" \
  && pass "revert strips gtk4 block" || bad "revert strips gtk4 block"
[[ ! -f $tmp/gtk3/gtk.css ]] || ! grep -q 'chroma:managed' "$tmp/gtk3/gtk.css" \
  && pass "revert strips gtk3 block" || bad "revert strips gtk3 block"
shopt -s nullglob
leftovers=("$tmp/themes"/*-chroma-*)
shopt -u nullglob
((${#leftovers[@]} == 0)) && pass "revert removes wrappers" || bad "revert leaves wrappers: ${leftovers[*]}"
[[ ! -e $tmp/stage ]] && pass "revert clears root stage" || bad "revert leaves root stage"

# Success stays quiet, but the hook keeps the full run and surfaces the one
# actionable libhandy line on stderr for `omarchy theme set` to show.
hookplugin="$tmp/hookplugin"
hookstate="$tmp/hookstate"
mkdir -p "$hookplugin/bin"
cat >"$hookplugin/bin/chroma-apply" <<'PY'
print("chroma: Fixture (dark), relaunch Disks (libhandy pinned to Adwaita)")
PY
hook_err=$(CHROMA_PLUGIN_DIR="$hookplugin" XDG_STATE_HOME="$hookstate" \
  bash "$here/omarchy/theme-set-hook" 2>&1 >/dev/null)
[[ $hook_err == *"chroma: relaunch Disks (libhandy pinned to Adwaita)"* ]] \
  && pass "hook surfaces libhandy hint on stderr" \
  || bad "hook surfaces libhandy hint on stderr ($hook_err)"
grep -q 'relaunch Disks' "$hookstate/omarchy/chroma/last-run" 2>/dev/null \
  && pass "hook keeps full run in last-run" \
  || bad "hook keeps full run in last-run"
[[ ! -e $hookstate/omarchy/chroma/last-hook-error ]] \
  && pass "hook leaves no error on success" \
  || bad "hook writes last-hook-error on success"

# Failures still land in last-hook-error and stay off stderr.
failplugin="$tmp/failplugin"
failstate="$tmp/failstate"
mkdir -p "$failplugin/bin"
printf 'import sys\nprint("chroma: fixture failed")\nsys.exit(1)\n' \
  >"$failplugin/bin/chroma-apply"
fail_err=$(CHROMA_PLUGIN_DIR="$failplugin" XDG_STATE_HOME="$failstate" \
  bash "$here/omarchy/theme-set-hook" 2>&1 >/dev/null)
[[ -z $fail_err ]] && pass "hook stays quiet on failure" \
  || bad "hook prints on failure ($fail_err)"
grep -q 'fixture failed' "$failstate/omarchy/chroma/last-hook-error" 2>/dev/null \
  && pass "hook records failure in last-hook-error" \
  || bad "hook records failure in last-hook-error"

# Validate manifest against omarchy if available
if command -v omarchy >/dev/null 2>&1; then
  if omarchy plugin validate "$here" >/dev/null 2>&1; then
    pass "omarchy plugin validate"
  else
    bad "omarchy plugin validate"
  fi
fi

if (( fail )); then
  echo "chroma check: FAILED"
  exit 1
fi
echo "chroma check: all good"
exit 0
