# Chroma

**Omarchy themes your terminal, editor, and shell. Chroma carries the same
palette into GTK and Qt apps — including the ones that used to ignore you.**

![Chroma on Hackerman — Files, Document Viewer, and BleachBit wearing the theme](preview.png)

Stock Omarchy flips Nautilus, BleachBit, Evince and friends between light and
dark Adwaita. That is all they ever get: the same default grey in every theme.
Your desktop wears Hackerman neon; your file manager wears beige.

Chroma closes that gap. Enable it once and every `omarchy theme set` paints
GTK3, GTK4 / libadwaita, and Qt (via Omarchy's stock `QT_QPA_PLATFORMTHEME=gtk3`)
with the active theme's real colours — background, foreground, accent,
destructive / success / warning — light and dark alike.

Inspired by [Accord](https://github.com/vonsensey/accord), which proved the
GTK `@define-color` bridge on Omarchy. Chroma keeps that core idea, hooks it
straight into `theme-set.d` for an instant apply, prefers `adw-gtk3` when
installed so GTK3 actually consumes the palette, and optionally themes root
GUIs (`sudo` / `pkexec` BleachBit) with a one-time symlink — without forcing
`qt6ct` or fighting Omarchy's Qt defaults.

## What you get

- **GTK4 / libadwaita** — Nautilus, Evince, Calendar, Text Editor, Loupe, …
  via `~/.config/gtk-4.0/gtk.css` (the only user lever libadwaita honors).
- **GTK3** — classic named colours + dialog polish in
  `~/.config/gtk-3.0/gtk.css`, with `adw-gtk3` / `adw-gtk3-dark` when the
  package is present so those variables actually stick.
- **Qt 5 / Qt 6** — stays on Omarchy's `QT_QPA_PLATFORMTHEME=gtk3`, so Qt
  inherits the GTK3 palette Chroma just wrote. No qt6ct, no Kvantum, no
  shell-side icon side effects.
- **Root apps (optional)** — one-time
  `/root/.config/gtk-*` → your configs, so `sudo bleachbit` / pkexec GUIs
  match. Password once; every later theme switch follows for free.
- **Light and dark** — `color-scheme` and `gtk-theme` stay mode-correct,
  preferring adw-gtk3 over stock Adwaita when available.

## Install

```sh
omarchy plugin add https://github.com/AlxWolfenstein97/chroma.git --enable
```

Or from a checkout:

```sh
~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/install.sh
omarchy plugin enable io.github.alxwolfenstein97.chroma
```

Theme root GUIs (BleachBit as root, etc.) — one password prompt:

```sh
~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/install.sh --with-root
```

**Package pulled when missing:** `adw-gtk-theme` (GTK3 needs it to honour
libadwaita-style `@define-color`s). Nothing else.

## How it works

1. A script in `~/.config/omarchy/hooks/theme-set.d/chroma` runs at the end of
   every `omarchy theme set` / `theme refresh`.
2. `bin/chroma-apply` reads the active theme's `colors.toml`, writes marked
   managed blocks into `gtk-3.0` / `gtk-4.0` CSS + `settings.ini`, and sets
   GNOME `color-scheme` / `gtk-theme`.
3. A small shell **service** is the safety net: if a switch somehow skips the
   hook, it notices within a few seconds and re-applies.
4. Windowless GTK daemons (`--gapplication-service`) and
   `xdg-desktop-portal-gtk` are restarted only when they have no open window,
   so open apps are never killed mid-use.

Idempotent: unchanged themes write nothing (byte-compared before write).

## What it writes — and what it does not

**Writes**

- `~/.config/gtk-4.0/gtk.css` and `gtk-3.0/gtk.css` — marked
  `chroma:managed` block; pre-existing user CSS is backed up once and kept.
- `~/.config/gtk-{3,4}.0/settings.ini` — theme name, prefer-dark, font
  (no icon / cursor keys — Omarchy owns those).
- Two gsettings keys: `color-scheme`, `gtk-theme` (originals saved for revert).
- `~/.local/state/omarchy/chroma/state.json` — last apply metadata.

**Optional ( `--with-root` )**

- Symlinks `/root/.config/{gtk-3.0,gtk-4.0}` → your matching dirs.

**Does not**

- Touch icon or cursor themes.
- Force `QT_QPA_PLATFORMTHEME` away from Omarchy's `gtk3`.
- Network. Ever.
- Kill any app that owns a visible window.

## Disable vs remove

| Action | What happens |
|---|---|
| `omarchy plugin disable …` | Shell service stops. **Theme hook still runs** — apps stay chromed on every theme switch. |
| `./uninstall.sh` then disable / remove | Hook gone, CSS blocks stripped, gsettings restored (or handed back to `omarchy-theme-set-gnome`), root symlinks removable. Clean off. |
| `omarchy pkg drop adw-gtk-theme` | Optional. Back to stock Adwaita binary themes; light/dark flip only. |

```sh
~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/uninstall.sh
omarchy plugin disable io.github.alxwolfenstein97.chroma
omarchy plugin remove io.github.alxwolfenstein97.chroma
```

## Limits, honestly

- **Qt picks the palette up at launch**, not live — relaunch Qt apps after a
  theme switch.
- **Apps with their own skins** (OBS themes, Steam, some Electron) ignore
  platform GTK/Qt colours. Different problem.
- **LibreOffice** themes chrome via GTK; some notebook/brand strips stay LO's
  own blue. Document background is a LO setting (“use printer metrics” /
  white-document prefs), not Chroma.
- **Flatpak** needs the usual hole:
  `flatpak override --user --filesystem=xdg-config/gtk-4.0:ro <app>`.
- We recolor stock Adwaita / adw-gtk3 rather than shipping a full theme
  engine — keeps the bridge small and update-safe on Omarchy's stack.

## Check

```sh
bash ~/.config/omarchy/plugins/io.github.alxwolfenstein97.chroma/check.sh
```

## Credits

- [Accord](https://github.com/vonsensey/accord) by vonsensey — the clear
  demonstration that Omarchy themes can drive libadwaita via user CSS, and
  the craft bar for merge-safe managed blocks, luma-distance on-accent text,
  and never-kill-a-window restarts.
- [OMCP](https://github.com/btsouth/omarchy-omcp) — MCP desktop bridge (themes,
  windows, screenshots, …). Helped build and iterate the preview here:
  `omarchy plugin add https://github.com/btsouth/omarchy-omcp --enable`
- [Omarchy](https://omarchy.org/) — theme pipeline, `theme-set` hooks, and
  the `gtk3` Qt platform theme this plugin deliberately stays aligned with.

## License

MIT — see [LICENSE](LICENSE).
