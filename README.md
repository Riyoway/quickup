<p align="center">
  <img src="assets/logo.png" width="128" alt="QuickUp">
</p>

<h1 align="center">QuickUp</h1>

Right-click a file, pick a host, and QuickUp uploads it and copies the link to
your clipboard. It runs on the PowerShell already built into Windows, and
nothing stays running in the background.

<p align="center">
  <img src="assets/demo.gif" width="640" alt="QuickUp demo">
</p>

## Install

### Windows

Two ways to the same result:

- **Double-click.** Download [QuickUp-Installer.bat](https://github.com/Riyoway/quickup/releases/latest/download/QuickUp-Installer.bat)
  from the [latest release](https://github.com/Riyoway/quickup/releases/latest) and run it.
  Windows may warn about an unknown file — click *More info → Run anyway*.
- **Terminal**, if you know your way around one — it's the quicker route:

  ```powershell
  irm https://apps.riyo.me/install/quickup.ps1 | iex
  ```

Both do the same thing (the batch just runs the same PowerShell for you), so use
whichever you like. It installs to `%LOCALAPPDATA%\QuickUp` and adds a per-user
right-click entry — no admin rights. To remove it later: right-click a file →
QuickUp → **Uninstall QuickUp**, or run `QuickUp-Uninstaller.bat`.

### macOS

Download [QuickUp-Installer.command](https://github.com/Riyoway/quickup/releases/latest/download/QuickUp-Installer.command)
from the [latest release](https://github.com/Riyoway/quickup/releases/latest), then
**right-click it → Open** (macOS blocks double-clicking downloaded scripts the first
time). If it won't run, the download dropped its executable bit — open Terminal and run
`sh ~/Downloads/QuickUp-Installer.command`.

Or, from a terminal:

```sh
curl -fsSL https://apps.riyo.me/install/quickup.sh | sh
```

### Linux

```sh
curl -fsSL https://apps.riyo.me/install/quickup.sh | sh
```

Both need `curl`. QuickUp integrates with the file managers it finds:

- **macOS** — Finder Quick Actions (`right-click → Quick Actions → QuickUp: <host>`)
- **Linux** — Nautilus (GNOME), Dolphin (KDE), Thunar (XFCE)

A dialog needs `zenity` or `kdialog` on Linux (`pbcopy`/`osascript` are built in on
macOS); clipboard uses `wl-copy`, `xclip`, or `xsel`.

## Use

Right-click a file → **QuickUp** → pick a host. It uploads right away and shows
the link, already copied. **Copy** copies it again, **Open** opens it in your
browser, and **About** lists what each host allows. If a host can't take the
file — too big, or a blocked type — QuickUp says so before uploading and points
you to one that can.

## Hosts

| Host      | Retention                 | Max size | Blocked types                          |
| --------- | ------------------------- | -------- | -------------------------------------- |
| Catbox    | permanent                 | 200 MB   | `.exe .scr .cpl .doc .docx .jar`       |
| x0.at     | 3–100 days (smaller lasts longer) | 1 GB | executables (`.exe .dll .jar .class`)  |
| Litterbox | 1 hour                    | 1 GB     | `.exe .scr .cpl .doc .docx .jar`       |
| Uguu      | 3 hours                   | 128 MB   | executables, scripts, `.html .svg .jar .apk` |

Files go straight to the host you pick — nothing passes through a server of
ours. These are public services, so now and then one is down or blocks your
network; just pick another.

## Update

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\QuickUp\quickup.ps1" update
```

```sh
# macOS / Linux
sh quickup.sh update
```

Pulls the latest script and re-registers the menu.

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
