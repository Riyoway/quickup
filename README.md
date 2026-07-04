# QuickUp

Right-click any file in Windows Explorer, pick a host, and get a shareable URL
copied to your clipboard. No app to keep running, no dependencies beyond the
PowerShell that already ships with Windows.

## Install

```powershell
iwr https://raw.githubusercontent.com/Riyoway/quickup/main/quickup.ps1 -OutFile "$env:TEMP\quickup.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\quickup.ps1" install
```

The installer copies the script to `%LOCALAPPDATA%\QuickUp` and adds a per-user
context-menu entry (`HKCU`, no administrator rights needed).

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
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\QuickUp\quickup.ps1" uninstall
```

## License

[MIT](LICENSE)
