#!/usr/bin/env bash
# Arms --with-theme-hook. Pass --yes to skip prompts.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$here/install.sh" --with-theme-hook "$@"
