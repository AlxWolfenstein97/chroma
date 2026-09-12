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
mkdir -p "$tmp/theme" "$tmp/gtk4" "$tmp/gtk3" "$tmp/state" "$tmp/stage"
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
export CHROMA_NO_GSETTINGS=1
export CHROMA_NO_ROOT=1
export CHROMA_NO_QT_ENV=1
export CHROMA_QT6_DIR="$tmp/qt6"
export CHROMA_QT5_DIR="$tmp/qt5"

if "$here/bin/chroma-apply" --no-restart --no-root; then
  pass "apply dark fixture"
else
  bad "apply dark fixture"
fi

grep -q 'accent_bg_color #ff3d9a' "$tmp/gtk4/gtk.css" && pass "gtk4 accent" || bad "gtk4 accent"
grep -q 'theme_bg_color #0b0618' "$tmp/gtk3/gtk.css" && pass "gtk3 bg" || bad "gtk3 bg"
grep -q 'chroma:managed' "$tmp/gtk4/settings.ini" && pass "gtk4 settings.ini" || bad "gtk4 settings.ini"
[[ -f $tmp/state/state.json ]] && pass "state.json" || bad "state.json"
[[ -f $tmp/stage/manifest.json ]] && pass "root stage manifest" || bad "root stage manifest"

# Idempotent re-apply
out=$("$here/bin/chroma-apply" --no-restart --no-root)
echo "$out" | grep -q 'gtk4 unchanged' && pass "idempotent gtk4" || bad "idempotent gtk4 ($out)"

# Revert cleans managed block
"$here/bin/chroma-apply" --revert >/dev/null
[[ ! -f $tmp/gtk4/gtk.css ]] || ! grep -q 'chroma:managed' "$tmp/gtk4/gtk.css" \
  && pass "revert strips block" || bad "revert strips block"

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
