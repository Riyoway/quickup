<p align="center">
  <img src="assets/logo.png" width="128" alt="QuickUp">
</p>

<h1 align="center">QuickUp</h1>

Right-click any file in Windows Explorer, pick a host, and get a shareable URL
copied to your clipboard. No app to keep running, no dependencies beyond the
PowerShell that already ships with Windows.

## Install

### Windows

```powershell
iwr https://raw.githubusercontent.com/Riyoway/quickup/main/quickup.ps1 -OutFile "$env:TEMP\quickup.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\quickup.ps1" install
```

Or download the repo and double-click **`install.cmd`** to pick install/uninstall.
The installer copies the script to `%LOCALAPPDATA%\QuickUp` and adds a per-user
context-menu entry (`HKCU`, no administrator rights needed).

### macOS / Linux

```sh
curl -fsSL https://raw.githubusercontent.com/Riyoway/quickup/main/quickup.sh -o quickup.sh
sh quickup.sh install
```

Needs `curl`. Integrates with the file managers it finds:

- **macOS** — Finder Quick Actions (`right-click → Quick Actions → QuickUp: <host>`)
- **Linux** — Nautilus (GNOME), Dolphin (KDE), Thunar (XFCE)

A dialog needs `zenity` or `kdialog` on Linux (`pbcopy`/`osascript` are built in on
macOS); clipboard uses `wl-copy`, `xclip`, or `xsel`.

## Use

Right-click a file → **QuickUp** → choose a host. The upload starts at once and
a small dialog shows the URL, already on your clipboard. **Copy** re-copies it,
**Open** launches it in your browser.

## Hosts

| Host      | Retention        |
| --------- | ---------------- |
| Catbox    | permanent        |
| Litterbox | 1 hour           |
| 0x0.st    | up to 1 year     |
| Uguu      | 48 hours         |

Files are sent directly to the third-party host you pick; nothing is proxied.

## Uninstall

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\QuickUp\quickup.ps1" uninstall
```

```sh
# macOS / Linux
sh quickup.sh uninstall
```

## License

[MIT](LICENSE)
