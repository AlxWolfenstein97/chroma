#!/bin/bash
# Lightweight self-check for Chroma (no full Accord-style suite).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
pass() { printf 'ok  %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=1; }

[[ -x $here/bin/chroma-apply ]] || bad "chroma-apply not executable"
[[ -x $here/bin/chroma-sync-root ]] || bad "chroma-sync-root not executable"
[[ -x $here/bin/chroma-boot-install ]] || bad "chroma-boot-install not executable"
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

# settings.ini is shared with the user and other Omarchy tooling. Seed
# unrelated keys plus the pre-Chroma values of the keys Chroma owns so the
# merge/rollback path is exercised instead of a file-replacement path.
for d in gtk4 gtk3; do
  cat >"$tmp/$d/settings.ini" <<'EOF'
[Settings]
gtk-enable-animations=false
gtk-decoration-layout=menu:close
gtk-theme-name=Adwaita
gtk-font-name=Original 10
EOF
done

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

if out=$("$here/bin/chroma-apply" --no-restart --no-root); then
  pass "apply dark fixture"
else
  bad "apply dark fixture"
fi

# Apply merges Chroma's keys into settings.ini instead of replacing the file.
for d in gtk4 gtk3; do
  ini="$tmp/$d/settings.ini"
  grep -q '^gtk-enable-animations=false$' "$ini" \
    && pass "$d settings.ini keeps gtk-enable-animations" \
    || bad "$d settings.ini lost gtk-enable-animations"
  grep -q '^gtk-decoration-layout=menu:close$' "$ini" \
    && pass "$d settings.ini keeps gtk-decoration-layout" \
    || bad "$d settings.ini lost gtk-decoration-layout"
  grep -q '^# chroma:managed$' "$ini" \
    && pass "$d settings.ini carries marker" \
    || bad "$d settings.ini missing marker"
done

# A switch to dark pins open libhandy windows to stock Adwaita; name them so
# the user knows what to relaunch. Non-libhandy windows must stay quiet.
echo "$out" | grep -q 'relaunch Disks (libhandy pinned to Adwaita)' \
  && pass "dark switch reports libhandy relaunch" \
  || bad "dark switch reports libhandy relaunch ($out)"
echo "$out" | grep -q 'Nautilus' \
  && bad "non-libhandy window reported" \
  || pass "non-libhandy window not reported"

grep -q 'accent_bg_color #ff3d9a' "$tmp/gtk4/gtk.css" && pass "gtk4 accent" || bad "gtk4 accent"

# Apply must not delete a user-owned environment.d file (ownership marker).
[[ -f $CHROMA_QT_ENV_FILE ]] && grep -q 'qt6ct' "$CHROMA_QT_ENV_FILE" \
  && pass "apply keeps unowned environment.d file" \
  || bad "apply deleted an unowned environment.d file"

# GTK3 uses a generated wrapper theme so it (and Qt) can repaint live.
wrap=$(sed -n 's/^gtk-theme-name=//p' "$tmp/gtk3/settings.ini")
case $wrap in
  *-chroma-a|*-chroma-b) pass "gtk3 wrapper theme name ($wrap)" ;;
  *) bad "gtk3 wrapper theme name ($wrap)" ;;
esac
wcss="$tmp/themes/$wrap/gtk-3.0/gtk.css"
grep -q 'chroma:managed' "$wcss" 2>/dev/null && pass "wrapper carries managed block" || bad "wrapper carries managed block"
grep -q 'theme_bg_color #0b0618' "$wcss" 2>/dev/null && pass "gtk3 wrapper bg" || bad "gtk3 wrapper bg"
if [[ -f $tmp/gtk3/gtk.css ]] && grep -q 'chroma:managed' "$tmp/gtk3/gtk.css"; then
  bad "wrapper mode leaves user gtk-3.0/gtk.css alone"
else
  pass "wrapper mode leaves user gtk-3.0/gtk.css alone"
fi

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
[[ -f $tmp/state/state.json ]] && pass "state.json" || bad "state.json"
[[ -f $tmp/stage/manifest.json ]] && pass "root stage manifest" || bad "root stage manifest"
[[ -f $tmp/stage/themes/$wrap/gtk-3.0/gtk.css ]] && pass "root stage theme" || bad "root stage theme"

# Idempotent re-apply (same palette → same wrapper, no rewrite)
out=$("$here/bin/chroma-apply" --no-restart --no-root)
echo "$out" | grep -q 'gtk4 unchanged' && pass "idempotent gtk4" || bad "idempotent gtk4 ($out)"
echo "$out" | grep -q "gtk3 wrapper $wrap unchanged" && pass "idempotent wrapper" || bad "idempotent wrapper ($out)"

# An empty Chroma-unique stub is safe to prune; a marked legacy file too.
: >"$CHROMA_QT_ENV_FILE"
"$here/bin/chroma-apply" --no-restart --no-root >/dev/null
[[ ! -e $CHROMA_QT_ENV_FILE ]] && pass "apply prunes empty environment.d stub" \
  || bad "apply leaves empty environment.d stub"
printf '# Managed by Chroma — legacy Qt override\nQT_QPA_PLATFORMTHEME=gtk3\n' >"$CHROMA_QT_ENV_FILE"
"$here/bin/chroma-apply" --no-restart --no-root >/dev/null
[[ ! -e $CHROMA_QT_ENV_FILE ]] && pass "apply removes owned environment.d file" \
  || bad "apply leaves owned environment.d file"

# Palette change rotates to the other wrapper name so GTK3/Qt reload live.
sed -i 's/background = "#0B0618"/background = "#0B0620"/' "$tmp/theme/colors.toml"
out=$("$here/bin/chroma-apply" --no-restart --no-root)
newwrap=$(sed -n 's/^gtk-theme-name=//p' "$tmp/gtk3/settings.ini")
if [[ $newwrap != "$wrap" ]]; then
  pass "wrapper rotation ($wrap → $newwrap)"
else
  bad "wrapper rotation did not change name ($newwrap)"
fi
grep -q 'theme_bg_color #0b0620' "$tmp/themes/$newwrap/gtk-3.0/gtk.css" 2>/dev/null \
  && pass "rotated wrapper has new color" || bad "rotated wrapper has new color"
[[ -f $tmp/stage/themes/$newwrap/gtk-3.0/gtk.css ]] \
  && pass "root stage follows active wrapper" || bad "root stage follows active wrapper"
[[ ! -d $tmp/stage/themes/$wrap ]] \
  && pass "root stage prunes stale wrappers" || bad "root stage prunes stale wrappers"

# Escape hatch keeps the old user-CSS bridge.
base=${wrap%-chroma-*}
out=$("$here/bin/chroma-apply" --no-restart --no-root --no-gtk-wrapper)
grep -q 'chroma:managed' "$tmp/gtk3/gtk.css" 2>/dev/null && pass "legacy css escape hatch" || bad "legacy css escape hatch"
grep -q "gtk-theme-name=$base" "$tmp/gtk3/settings.ini" \
  && pass "legacy css uses base theme" || bad "legacy css uses base theme ($base)"
echo "$out" | grep -q 'relaunch ' \
  && bad "legacy css mode reports libhandy relaunch" \
  || pass "legacy css mode does not report libhandy relaunch"

# A switch to a light theme makes libhandy reset its pin instead of setting it,
# so those windows recover live and no relaunch hint is needed.
sed -i 's/mode = "dark"/mode = "light"/' "$tmp/theme/colors.toml"
out=$("$here/bin/chroma-apply" --no-restart --no-root)
echo "$out" | grep -q 'relaunch ' \
  && bad "light switch reports libhandy relaunch" \
  || pass "light switch does not report libhandy relaunch"
sed -i 's/mode = "light"/mode = "dark"/' "$tmp/theme/colors.toml"

# Revert restores the base theme before deleting generated wrappers.
# It must also respect environment.d ownership.
# A key the user adds to the marked file after apply must survive both the
# next apply and the revert, while Chroma's keys roll back to their originals.
printf 'gtk-show-unicode-menu=false\n' >>"$tmp/gtk4/settings.ini"
"$here/bin/chroma-apply" --no-restart --no-root >/dev/null
grep -q '^gtk-show-unicode-menu=false$' "$tmp/gtk4/settings.ini" \
  && pass "re-apply keeps later user setting" \
  || bad "re-apply dropped later user setting"
printf 'QT_QPA_PLATFORMTHEME=qt5ct\n' >"$CHROMA_QT_ENV_FILE"
"$here/bin/chroma-apply" --revert >/dev/null
[[ -f $tmp/gtk4/settings.ini ]] && grep -q '^gtk-enable-animations=false$' "$tmp/gtk4/settings.ini" \
  && pass "revert restores original gtk4 settings" \
  || bad "revert lost original gtk4 settings"
grep -q '^gtk-decoration-layout=menu:close$' "$tmp/gtk4/settings.ini" \
  && pass "revert keeps unrelated gtk4 setting" \
  || bad "revert dropped unrelated gtk4 setting"
grep -q '^gtk-show-unicode-menu=false$' "$tmp/gtk4/settings.ini" \
  && pass "revert keeps later user setting" \
  || bad "revert dropped later user setting"
grep -q '^gtk-theme-name=Adwaita$' "$tmp/gtk4/settings.ini" \
  && pass "revert restores original gtk theme" \
  || bad "revert did not restore original gtk theme"
grep -q '^gtk-font-name=Original 10$' "$tmp/gtk4/settings.ini" \
  && pass "revert restores original gtk font" \
  || bad "revert did not restore original gtk font"
grep -q '^gtk-application-prefer-dark-theme=' "$tmp/gtk4/settings.ini" \
  && bad "revert left Chroma-only prefer-dark key" \
  || pass "revert removes Chroma-only prefer-dark key"
grep -q '^# chroma:managed$' "$tmp/gtk4/settings.ini" \
  && bad "revert left settings.ini marker" \
  || pass "revert removes settings.ini marker"
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
  && pass "revert strips legacy gtk3 block" || bad "revert strips legacy gtk3 block"
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

# Failure paths: the pre-Chroma INI snapshot must reach state.json before the
# first settings.ini is replaced, and a snapshot that cannot be persisted must
# leave both INIs untouched. Cover both immediate revert and a later retry.
make_ini_fixture() {
  local f
  f=$(mktemp -d)
  mkdir -p "$f/theme" "$f/gtk4css" "$f/gtk3css" "$f/gtk4ini" "$f/gtk3ini" \
    "$f/state" "$f/stage" "$f/themes"
  cp "$tmp/theme/colors.toml" "$f/theme/colors.toml"
  for d in gtk4ini gtk3ini; do
    cat >"$f/$d/settings.ini" <<'EOF'
[Settings]
gtk-enable-animations=false
gtk-theme-name=Original
gtk-font-name=Original 10
EOF
  done
  printf '%s\n' "$f"
}

apply_ini_fixture() {
  local f=$1
  shift
  CHROMA_THEME_DIR="$f/theme" \
  CHROMA_GTK4_CSS="$f/gtk4css/gtk.css" \
  CHROMA_GTK3_CSS="$f/gtk3css/gtk.css" \
  CHROMA_GTK4_INI="$f/gtk4ini/settings.ini" \
  CHROMA_GTK3_INI="$f/gtk3ini/settings.ini" \
  CHROMA_STATE_DIR="$f/state" \
  CHROMA_ROOT_STAGE="$f/stage" \
  CHROMA_THEMES_DIR="$f/themes" \
  CHROMA_QT6_DIR="$f/qt6" \
  CHROMA_QT5_DIR="$f/qt5" \
  CHROMA_QT_ENV_FILE="$f/environment.d/99-chroma-qt.conf" \
  "$here/bin/chroma-apply" --no-restart --no-root "$@"
}

for mode in revert retry absent; do
  f=$(make_ini_fixture)
  if [[ $mode == absent ]]; then
    rm -f "$f/gtk4ini/settings.ini" "$f/gtk3ini/settings.ini"
  fi
  chmod 0555 "$f/gtk3ini"
  if apply_ini_fixture "$f" >/dev/null 2>&1; then
    bad "INI failure-path ($mode): apply unexpectedly succeeded"
  else
    pass "INI failure-path ($mode): apply fails after gtk4 INI write"
  fi
  if python3 - "$f/state/state.json" "$mode" "$f/gtk4ini/settings.ini" "$f/gtk3ini/settings.ini" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
expect = sys.argv[2] != "absent"
for path in sys.argv[3:]:
    rec = state["settings_ini"][path]
    assert rec["existed"] is expect, path
    if expect:
        assert rec["keys"]["gtk-theme-name"] == "Original", path
        assert rec["keys"]["gtk-font-name"] == "Original 10", path
    else:
        assert all(value is None for value in rec["keys"].values()), path
PY
  then
    pass "INI failure-path ($mode): snapshot persisted before first write"
  else
    bad "INI failure-path ($mode): snapshot missing/incomplete"
  fi
  chmod 0755 "$f/gtk3ini"
  if [[ $mode == retry ]]; then
    if apply_ini_fixture "$f" >/dev/null 2>&1; then
      pass "INI failure-path ($mode): retry applies"
    else
      bad "INI failure-path ($mode): retry failed"
    fi
  fi
  apply_ini_fixture "$f" --revert >/dev/null 2>&1 || true
  for d in gtk4ini gtk3ini; do
    ini="$f/$d/settings.ini"
    if [[ $mode == absent ]]; then
      [[ ! -e $ini ]] \
        && pass "INI failure-path ($mode): $d stays absent" \
        || bad "INI failure-path ($mode): $d was left behind"
      continue
    fi
    grep -q '^gtk-theme-name=Original$' "$ini" \
      && pass "INI failure-path ($mode): $d original theme restored" \
      || bad "INI failure-path ($mode): $d original theme not restored"
    grep -q '^gtk-font-name=Original 10$' "$ini" \
      && pass "INI failure-path ($mode): $d original font restored" \
      || bad "INI failure-path ($mode): $d original font not restored"
    grep -q '^gtk-enable-animations=false$' "$ini" \
      && pass "INI failure-path ($mode): $d unrelated key kept" \
      || bad "INI failure-path ($mode): $d unrelated key lost"
    grep -q '^# chroma:managed$' "$ini" \
      && bad "INI failure-path ($mode): $d marker left" \
      || pass "INI failure-path ($mode): $d marker removed"
  done
  rm -rf "$f"
done

# A snapshot that cannot be written must not be followed by an INI replacement.
f=$(make_ini_fixture)
chmod 0555 "$f/state"
if apply_ini_fixture "$f" >/dev/null 2>&1; then
  pass "INI snapshot failure: apply continues"
else
  bad "INI snapshot failure: apply aborted"
fi
chmod 0755 "$f/state"
for d in gtk4ini gtk3ini; do
  ini="$f/$d/settings.ini"
  grep -q '^# chroma:managed$' "$ini" \
    && bad "INI snapshot failure: $d was modified" \
    || pass "INI snapshot failure: $d left unchanged"
  grep -q '^gtk-theme-name=Original$' "$ini" \
    && pass "INI snapshot failure: $d original theme kept" \
    || bad "INI snapshot failure: $d original theme lost"
done
rm -rf "$f"

# The startup installer wrapper must bound the whole operation, clean up
# descendants on expiry, and keep captured stderr small. Service.qml runs the
# wrapper instead of install.sh directly.
boot=$(mktemp -d)
mkdir -p "$boot/bin"
cp "$here/bin/chroma-boot-install" "$boot/bin/"
cat >"$boot/install.sh" <<'EOF'
#!/bin/bash
head -c 100000 /dev/zero | tr '\0' 'x' >&2
sleep 30 &
echo "$!" >"$STALL_PID"
wait
EOF
chmod 755 "$boot/install.sh"
start=$SECONDS
if CHROMA_BOOT_TIMEOUT=1 STALL_PID="$boot/pid" \
  bash "$boot/bin/chroma-boot-install" >/dev/null 2>"$boot/err"; then
  bad "boot installer: stalled child did not time out"
else
  rc=$?
  elapsed=$((SECONDS - start))
  [[ $rc == 124 ]] \
    && pass "boot installer: stalled child exits 124" \
    || bad "boot installer: stalled child exited $rc"
  (( elapsed <= 10 )) \
    && pass "boot installer: deadline enforced (${elapsed}s)" \
    || bad "boot installer: deadline overrun (${elapsed}s)"
  stalled=$(cat "$boot/pid" 2>/dev/null || true)
  if [[ -n $stalled ]] && kill -0 "$stalled" 2>/dev/null; then
    bad "boot installer: descendant $stalled survived"
  else
    pass "boot installer: descendants cleaned up"
  fi
  tail -c 400 "$boot/err" | grep -q 'exceeded 1s' \
    && pass "boot installer: timeout notice survives a noisy child" \
    || bad "boot installer: timeout notice was truncated"
fi

# Cancelling the wrapper (not just reaching the deadline) must also signal and
# reap the installer group.
cat >"$boot/install.sh" <<'EOF'
#!/bin/bash
sleep 30 &
echo "$$" >"$INSTALLER_PID"
echo "$!" >"$STALL_PID"
wait
EOF
chmod 755 "$boot/install.sh"
INSTALLER_PID="$boot/installer.pid" STALL_PID="$boot/pid" \
  bash "$boot/bin/chroma-boot-install" >/dev/null 2>/dev/null &
wrapper=$!
for _ in $(seq 1 50); do
  if [[ -s $boot/installer.pid && -s $boot/pid ]]; then
    break
  fi
  sleep 0.1
done
kill -TERM "$wrapper" 2>/dev/null || true
wait "$wrapper" 2>/dev/null || true
sleep 0.3
for name in installer pid; do
  pid=$(cat "$boot/$name" 2>/dev/null || true)
  if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
    bad "boot installer: $name survived cancellation"
  else
    pass "boot installer: $name cleaned up on cancellation"
  fi
done

# A descendant can outlive the installer leader while staying in its process
# group; cleanup must signal the group, not just probe the leader PID.
cat >"$boot/install.sh" <<'EOF'
#!/bin/bash
sleep 30 &
echo "$!" >"$STALL_PID"
exit 0
EOF
chmod 755 "$boot/install.sh"
start=$SECONDS
if CHROMA_BOOT_TIMEOUT=10 STALL_PID="$boot/pid" \
  bash "$boot/bin/chroma-boot-install" >/dev/null 2>"$boot/err3"; then
  pass "boot installer: leader exit returns success"
else
  bad "boot installer: leader exit returned failure"
fi
elapsed=$((SECONDS - start))
(( elapsed <= 5 )) \
  && pass "boot installer: leader exit returns promptly (${elapsed}s)" \
  || bad "boot installer: leader exit hung (${elapsed}s)"
sleep 0.2
orphan=$(cat "$boot/pid" 2>/dev/null || true)
if [[ -n $orphan ]] && kill -0 "$orphan" 2>/dev/null; then
  bad "boot installer: descendant $orphan survived leader exit"
else
  pass "boot installer: descendant cleaned up after leader exit"
fi

cat >"$boot/install.sh" <<'EOF'
#!/bin/bash
head -c 100000 /dev/zero | tr '\0' 'x' >&2
echo "final line" >&2
EOF
if CHROMA_BOOT_TIMEOUT=10 bash "$boot/bin/chroma-boot-install" >/dev/null 2>"$boot/err2"; then
  size=$(wc -c <"$boot/err2")
  (( size <= 400 )) \
    && pass "boot installer: stderr bounded to ${size} bytes" \
    || bad "boot installer: stderr grew to ${size} bytes"
  grep -q 'final line' "$boot/err2" \
    && pass "boot installer: keeps the last stderr line" \
    || bad "boot installer: lost the last stderr line"
else
  bad "boot installer: noisy child failed"
fi

cat >"$boot/install.sh" <<'EOF'
#!/bin/bash
echo "boom" >&2
exit 7
EOF
if CHROMA_BOOT_TIMEOUT=10 bash "$boot/bin/chroma-boot-install" >/dev/null 2>/dev/null; then
  bad "boot installer: child exit status swallowed"
else
  [[ $? == 7 ]] \
    && pass "boot installer: child exit status propagated" \
    || bad "boot installer: child exit status changed"
fi
rm -rf "$boot"

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
