#!/usr/bin/env bash
#
# QuickUp - upload a file to a temporary/permanent host from the file
# manager's right-click menu. macOS (Finder Quick Actions) and Linux
# (Nautilus / Dolphin / Thunar) are wired up by `install`.
#
#   ./quickup.sh install
#   ./quickup.sh uninstall
#
set -euo pipefail

UA='QuickUp/1.0 (+https://github.com/Riyoway/quickup)'
SELF="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)/$(basename "$0")"

# Service order == submenu order.
services=(catbox litterbox 0x0 uguu)

display_of() {
    case "$1" in
        catbox)    echo "Catbox (permanent)" ;;
        litterbox) echo "Litterbox (1 hour)" ;;
        0x0)       echo "0x0.st (up to 1 year)" ;;
        uguu)      echo "Uguu (48 hours)" ;;
        *)         return 1 ;;
    esac
}

# Uploads $2 to service $1, echoing the plain-text URL the host returns.
upload_of() {
    local svc="$1" file="$2"
    case "$svc" in
        catbox)    curl -fsS -A "$UA" -F reqtype=fileupload -F "fileToUpload=@$file" https://catbox.moe/user/api.php ;;
        litterbox) curl -fsS -A "$UA" -F reqtype=fileupload -F time=1h -F "fileToUpload=@$file" https://litterbox.catbox.moe/resources/internals/api.php ;;
        0x0)       curl -fsS -A "$UA" -F "file=@$file" https://0x0.st ;;
        uguu)      curl -fsS -A "$UA" -F "files[]=@$file" "https://uguu.se/upload?output=text" ;;
        *)         echo "unknown service: $svc" >&2; return 1 ;;
    esac
}

is_mac() { [ "$(uname)" = "Darwin" ]; }

install_dir() {
    if is_mac; then echo "$HOME/Library/Application Support/QuickUp"
    else echo "${XDG_DATA_HOME:-$HOME/.local/share}/quickup"; fi
}

# --- feedback -------------------------------------------------------------

copy_clip() {
    local text="$1"
    if   command -v pbcopy  >/dev/null 2>&1; then printf '%s' "$text" | pbcopy
    elif command -v wl-copy >/dev/null 2>&1; then printf '%s' "$text" | wl-copy
    elif command -v xclip   >/dev/null 2>&1; then printf '%s' "$text" | xclip -selection clipboard
    elif command -v xsel    >/dev/null 2>&1; then printf '%s' "$text" | xsel -ib
    fi
}

show_ok() {  # $1 host label, $2 url
    local msg="Uploaded to $1 (copied to clipboard):"
    if is_mac; then
        local btn
        btn=$(osascript -e "button returned of (display dialog \"$msg\" & return & \"$2\" buttons {\"Open\", \"OK\"} default button \"OK\" with title \"QuickUp\")" 2>/dev/null || true)
        [ "$btn" = "Open" ] && open "$2"
    elif command -v zenity >/dev/null 2>&1; then
        zenity --entry --title=QuickUp --text="$msg" --entry-text="$2" >/dev/null 2>&1 || true
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --title QuickUp --msgbox "$msg"$'\n'"$2" >/dev/null 2>&1 || true
    else
        echo "$2"
    fi
}

show_err() {  # $1 message
    if is_mac; then
        osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with title \"QuickUp\" with icon stop" >/dev/null 2>&1 || true
    elif command -v zenity >/dev/null 2>&1; then
        zenity --error --title=QuickUp --text="$1" >/dev/null 2>&1 || true
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --title QuickUp --error "$1" >/dev/null 2>&1 || true
    else
        echo "QuickUp: $1" >&2
    fi
}

# --- commands -------------------------------------------------------------

cmd_upload() {
    local svc="$1" file="$2"
    display_of "$svc" >/dev/null || { show_err "Unknown service: $svc"; return 1; }
    [ -f "$file" ] || { show_err "File not found: $file"; return 1; }
    command -v curl >/dev/null 2>&1 || { show_err "curl is required but not installed."; return 1; }

    local url
    if ! url=$(upload_of "$svc" "$file" | tr -d '\r' | tail -n1); then
        show_err "Upload failed (host rejected the request)."
        return 1
    fi
    url="$(printf '%s' "$url" | tr -d '[:space:]')"
    case "$url" in
        http://*|https://*) copy_clip "$url"; show_ok "$(display_of "$svc")" "$url" ;;
        *) show_err "Unexpected response: $url" ;;
    esac
}

cmd_install() {
    local dir; dir="$(install_dir)"
    mkdir -p "$dir"
    local target="$dir/quickup.sh"
    [ "$SELF" = "$target" ] || install -m 755 "$SELF" "$target"

    if is_mac; then
        install_macos "$target"
        echo "Installed. Finder right-click -> Quick Actions -> QuickUp: <host>."
        echo "(You may need to enable them in System Settings -> Extensions -> Finder.)"
    else
        local any=0
        install_nautilus "$target" && { echo "Nautilus (GNOME) integrated."; any=1; }
        install_dolphin  "$target" && { echo "Dolphin (KDE) integrated."; any=1; }
        install_thunar   "$target" && { echo "Thunar (XFCE) integrated."; any=1; }
        [ "$any" = 1 ] || echo "No supported file manager config path found; script installed at $target."
        echo "Restart your file manager (or log out/in) for the menu to appear."
    fi
    echo "Uninstall with: $target uninstall"
}

cmd_uninstall() {
    if is_mac; then
        for s in "${services[@]}"; do rm -rf "$HOME/Library/Services/QuickUp - $(display_of "$s").workflow"; done
    else
        rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/nautilus/scripts/QuickUp"
        rm -f  "$HOME/.local/share/kio/servicemenus/quickup.desktop" \
               "$HOME/.local/share/kservices5/ServiceMenus/quickup.desktop"
        remove_thunar_block "$HOME/.config/Thunar/uca.xml"
    fi
    echo "QuickUp removed from the context menu. Files remain in $(install_dir)."
}

cmd_selftest() {
    local ok=1
    for s in "${services[@]}"; do display_of "$s" >/dev/null || { echo "no display for $s"; ok=0; }; done
    case "https://a.b/c" in http://*|https://*) ;; *) ok=0 ;; esac
    case "some error text" in http://*|https://*) ok=0 ;; esac
    command -v curl >/dev/null 2>&1 || echo "warning: curl not found on PATH"
    if [ "$ok" = 1 ]; then echo "SELFTEST OK"; else echo "SELFTEST FAILED"; exit 1; fi
}

# --- integrations ---------------------------------------------------------

install_nautilus() {
    local q="$1"
    local base="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus/scripts/QuickUp"
    mkdir -p "$base"
    for s in "${services[@]}"; do
        cat > "$base/$(display_of "$s")" <<EOF
#!/usr/bin/env bash
# Generated by QuickUp. Nautilus provides selected paths via this env var.
IFS=\$'\n'
for f in \$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS; do
    [ -n "\$f" ] && "$q" upload $s "\$f"
done
EOF
        chmod +x "$base/$(display_of "$s")"
    done
}

install_dolphin() {
    local q="$1"
    local dir="$HOME/.local/share/kio/servicemenus"
    mkdir -p "$dir"
    local f="$dir/quickup.desktop"
    {
        echo "[Desktop Entry]"
        echo "Type=Service"
        echo "MimeType=all/allfiles;"
        printf "Actions="; for s in "${services[@]}"; do printf "%s;" "$s"; done; echo
        echo "X-KDE-Submenu=QuickUp"
        echo "X-KDE-Priority=TopLevel"
        echo "Icon=go-up"
        echo
        for s in "${services[@]}"; do
            echo "[Desktop Action $s]"
            echo "Name=$(display_of "$s")"
            echo "Icon=go-up"
            echo "Exec=\"$q\" upload $s %f"
            echo
        done
    } > "$f"
    chmod +x "$f"
}

install_thunar() {
    local q="$1"
    local dir="$HOME/.config/Thunar"
    local f="$dir/uca.xml"
    mkdir -p "$dir"
    [ -f "$f" ] || printf '<?xml version="1.0" encoding="UTF-8"?>\n<actions>\n</actions>\n' > "$f"
    remove_thunar_block "$f"

    local blk; blk="$(mktemp)"
    {
        echo "<!-- quickup:begin -->"
        for s in "${services[@]}"; do
            printf '<action><icon>go-up</icon><name>%s</name><submenu>QuickUp</submenu>' "$(display_of "$s")"
            printf '<unique-id>quickup-%s</unique-id><command>&quot;%s&quot; upload %s %%f</command>' "$s" "$q" "$s"
            printf '<description>QuickUp</description><patterns>*</patterns>'
            printf '<other-files/><text-files/><image-files/><audio-files/><video-files/></action>\n'
        done
        echo "<!-- quickup:end -->"
    } > "$blk"

    awk -v blkfile="$blk" '
        /<\/actions>/ && !done { while ((getline line < blkfile) > 0) print line; done=1 }
        { print }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    rm -f "$blk"
}

remove_thunar_block() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -i.bak '/<!-- quickup:begin -->/,/<!-- quickup:end -->/d' "$f" && rm -f "$f.bak"
}

install_macos() {
    local q="$1"
    for s in "${services[@]}"; do
        local label; label="$(display_of "$s")"
        local wf="$HOME/Library/Services/QuickUp - $label.workflow/Contents"
        mkdir -p "$wf"
        cat > "$wf/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>NSServices</key><array><dict>
    <key>NSMenuItem</key><dict><key>default</key><string>QuickUp: $label</string></dict>
    <key>NSMessage</key><string>runWorkflowAsService</string>
    <key>NSSendFileTypes</key><array><string>public.item</string></array>
  </dict></array>
</dict></plist>
EOF
        local script="for f in \"\$@\"; do \"$q\" upload $s \"\$f\"; done"
        cat > "$wf/document.wflow" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>AMApplicationBuild</key><string>512</string>
  <key>AMApplicationVersion</key><string>2.10</string>
  <key>AMDocumentVersion</key><string>2</string>
  <key>actions</key><array><dict>
    <key>action</key><dict>
      <key>AMAccepts</key><dict>
        <key>Container</key><string>List</string><key>Optional</key><true/>
        <key>Types</key><array><string>com.apple.cocoa.path</string></array>
      </dict>
      <key>AMActionVersion</key><string>2.0.3</string>
      <key>AMApplication</key><array><string>Automator</string></array>
      <key>AMProvides</key><dict>
        <key>Container</key><string>List</string>
        <key>Types</key><array><string>com.apple.cocoa.string</string></array>
      </dict>
      <key>ActionBundlePath</key><string>/System/Library/Automator/Run Shell Script.action</string>
      <key>ActionName</key><string>Run Shell Script</string>
      <key>ActionParameters</key><dict>
        <key>COMMAND_STRING</key><string>$script</string>
        <key>CheckedForUserDefaultShell</key><true/>
        <key>inputMethod</key><integer>1</integer>
        <key>shell</key><string>/bin/bash</string>
        <key>source</key><string></string>
      </dict>
      <key>BundleIdentifier</key><string>com.apple.RunShellScript</string>
      <key>CFBundleVersion</key><string>2.0.3</string>
      <key>CanShowSelectedItemsWhenRun</key><false/>
      <key>CanShowWhenRun</key><true/>
      <key>Category</key><array><string>AMCategoryUtilities</string></array>
      <key>Class Name</key><string>RunShellScriptAction</string>
      <key>InputUUID</key><string>$(uuidgen)</string>
      <key>OutputUUID</key><string>$(uuidgen)</string>
      <key>UUID</key><string>$(uuidgen)</string>
      <key>UnlocalizedApplications</key><array><string>Automator</string></array>
      <key>arguments</key><dict/>
      <key>isViewVisible</key><integer>1</integer>
    </dict>
    <key>isViewVisible</key><integer>1</integer>
  </dict></array>
  <key>connectors</key><dict/>
  <key>workflowMetaData</key><dict>
    <key>serviceInputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject</string>
    <key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
    <key>serviceProcessesInput</key><integer>0</integer>
    <key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
  </dict>
</dict></plist>
EOF
    done
}

# --- dispatch -------------------------------------------------------------

case "${1:-install}" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    upload)    cmd_upload "${2:?service}" "${3:?file}" ;;
    selftest)  cmd_selftest ;;
    *)         echo "usage: quickup.sh {install|uninstall|upload <service> <file>}" >&2; exit 1 ;;
esac
