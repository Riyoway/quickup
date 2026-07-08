#!/usr/bin/env bash
#
# QuickUp - upload a file to a temporary/permanent host from the file
# manager's right-click menu. macOS (Finder Quick Actions) and Linux
# (Nautilus / Dolphin / Thunar) are wired up by `install`.
#
#   ./quickup.sh install
#   ./quickup.sh uninstall
#   curl -fsSL https://apps.riyo.me/install/quickup.sh | sh
#

QUICKUP_RAW='https://raw.githubusercontent.com/Riyoway/quickup/main'
QUICKUP_INSTALL_URL='https://apps.riyo.me/install/quickup.sh'

# Bootstrap so `curl -fsSL .../quickup.sh | sh` works on any machine. This
# script needs bash and a real file on disk (it copies itself and derives
# asset paths from $0), but a pipe runs under /bin/sh -- often dash, which
# chokes on the bash array syntax below -- with no $0 file. Re-exec bash on a
# real copy *before* any bash-only syntax is parsed. Kept strictly POSIX.
if [ -z "${BASH_VERSION:-}" ] || [ ! -f "$0" ]; then
    if [ -f "$0" ]; then
        exec bash "$0" "$@"                       # real file, wrong shell
    fi
    _boot="${TMPDIR:-/tmp}/quickup-boot.$$.sh"    # piped: fetch a real copy
    curl -fsSL "$QUICKUP_INSTALL_URL" -o "$_boot" 2>/dev/null \
        || curl -fsSL "$QUICKUP_RAW/quickup.sh" -o "$_boot"
    exec bash "$_boot" "$@"
fi

set -euo pipefail
# Remove the bootstrap copy on exit (only when we are running as that copy).
case "$0" in */quickup-boot.*.sh) trap 'rm -f "$0"' EXIT ;; esac

UA='QuickUp/1.0 (+https://github.com/Riyoway/quickup)'
SELF="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)/$(basename "$0")"

# Service order == submenu order.
services=(catbox x0 litterbox uguu)

# Menu icon; replaced with the installed logo path by cmd_install.
ICON="go-up"

# Decorated banner output (colours only when writing to a terminal).
if [ -t 1 ]; then
    B_RULE=$'\033[36m'; B_TITLE=$'\033[1;36m'; B_OK=$'\033[1;32m'
    B_DIM=$'\033[2m'; B_CMD=$'\033[33m'; B_RST=$'\033[0m'
else
    B_RULE=; B_TITLE=; B_OK=; B_DIM=; B_CMD=; B_RST=
fi
RULE='============================================================'

banner() {
    printf '\n%s%s%s\n%s    QuickUp  -  %s%s\n%s%s%s\n\n' \
        "$B_RULE" "$RULE" "$B_RST" "$B_TITLE" "$1" "$B_RST" "$B_RULE" "$RULE" "$B_RST"
}

field() { printf '%s  %-8s%s%s\n' "$B_DIM" "$1" "$B_RST" "$2"; }

host_list() {
    local out=""
    for s in "${services[@]}"; do
        [ -n "$out" ] && out="$out  |  "
        out="$out$(display_of "$s")"
    done
    printf '%s' "$out"
}

display_of() {
    case "$1" in
        catbox)    echo "Catbox (permanent)" ;;
        x0)        echo "x0.at (up to 100 days)" ;;
        litterbox) echo "Litterbox (1 hour)" ;;
        uguu)      echo "Uguu (3 hours)" ;;
        *)         return 1 ;;
    esac
}

# What each host accepts (from their docs/config): size cap in bytes, blocked
# extensions, and a one-line About summary. Litterbox shares Catbox's ban list.
svc_max_bytes() {
    case "$1" in
        catbox)    echo 209715200 ;;    # 200 MB
        x0)        echo 1073741824 ;;   # 1024 MiB
        litterbox) echo 1073741824 ;;   # 1 GB
        uguu)      echo 134217728 ;;    # 128 MiB
    esac
}
svc_banned() {
    case "$1" in
        catbox|litterbox) echo "exe scr cpl doc docx docm jar" ;;
        x0)               echo "exe dll com scr jar class" ;;
        uguu)             echo "exe scr com vbs bat cmd htm html jar msi apk phtml svg" ;;
        *)                echo "" ;;
    esac
}
svc_accept() {
    case "$1" in
        catbox)    echo "Permanent  |  max 200 MB  |  blocked: .exe .scr .cpl .doc .docx .jar" ;;
        x0)        echo "Kept 3-100 days (smaller lasts longer)  |  max 1 GB  |  blocked: executables (.exe .dll .jar .class)" ;;
        litterbox) echo "Temporary 1 hour  |  max 1 GB  |  blocked: .exe .scr .cpl .doc .docx .jar" ;;
        uguu)      echo "Temporary 3 hours  |  max 128 MB  |  blocked: executables, scripts, .html, .svg, .jar, .apk" ;;
    esac
}

file_size() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null; }
fmt_size() {
    if   [ "$1" -ge 1073741824 ]; then awk "BEGIN{printf \"%.1f GB\", $1/1073741824}"
    elif [ "$1" -ge 1048576 ];    then echo "$(( $1 / 1048576 )) MB"
    elif [ "$1" -ge 1024 ];       then echo "$(( $1 / 1024 )) KB"
    else echo "$1 B"; fi
}

# Prints a reason when $1 can't take file $2; prints nothing when it can.
test_supported() {
    local svc="$1" file="$2" ext=""
    case "$(basename "$file")" in *.*) ext="$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')" ;; esac
    case " $(svc_banned "$svc") " in
        *" $ext "*) printf '%s does not accept .%s files.' "$(display_of "$svc")" "$ext"; return ;;
    esac
    local size max; size="$(file_size "$file")"; max="$(svc_max_bytes "$svc")"
    if [ -n "$size" ] && [ "$size" -gt "$max" ]; then
        printf 'File is %s; %s accepts up to %s.' "$(fmt_size "$size")" "$(display_of "$svc")" "$(fmt_size "$max")"
    fi
}
supporting_services() {
    local s r out=""
    for s in "${services[@]}"; do
        r="$(test_supported "$s" "$1")"
        [ -z "$r" ] && out="$out  - $(display_of "$s")"$'\n'
    done
    printf '%s' "$out"
}

# Uploads $2 to service $1, echoing the plain-text URL the host returns.
upload_of() {
    local svc="$1" file="$2"
    case "$svc" in
        catbox)    curl -fsS -A "$UA" -F reqtype=fileupload -F "fileToUpload=@$file" https://catbox.moe/user/api.php ;;
        litterbox) curl -fsS -A "$UA" -F reqtype=fileupload -F time=1h -F "fileToUpload=@$file" https://litterbox.catbox.moe/resources/internals/api.php ;;
        x0)        curl -fsS -A "$UA" -F "file=@$file" https://x0.at ;;
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

    # Refuse a file this host can't take, and point at the ones that can.
    local reason; reason="$(test_supported "$svc" "$file")"
    if [ -n "$reason" ]; then
        local ok; ok="$(supporting_services "$file")"
        if [ -n "$ok" ]; then show_err "$reason"$'\n\n'"This file works with:"$'\n'"$ok"
        else show_err "$reason"$'\n\n'"None of the configured hosts accept this file."; fi
        return 1
    fi

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

cmd_about() {
    local text="QuickUp - what each host accepts"$'\n\n' s
    for s in "${services[@]}"; do
        text="$text$(display_of "$s")"$'\n'"    $(svc_accept "$s")"$'\n\n'
    done
    text="${text}A file a host can't take is refused before upload, with a working host suggested."
    if   [ -t 1 ]; then printf '%s\n' "$text"
    elif is_mac; then osascript -e "display dialog \"$text\" buttons {\"OK\"} default button \"OK\" with title \"QuickUp\"" >/dev/null 2>&1 || true
    elif command -v zenity  >/dev/null 2>&1; then zenity --info --no-wrap --title=QuickUp --text="$text" >/dev/null 2>&1 || true
    elif command -v kdialog >/dev/null 2>&1; then kdialog --title QuickUp --msgbox "$text" >/dev/null 2>&1 || true
    else printf '%s\n' "$text"; fi
}

# Resolve a per-service favicon (bundled or fetched), echoing its path; falls
# back to the app icon ($ICON) for hosts without one (e.g. x0.at).
svc_icon() {
    local svc="$1" idir="$2"
    local dest="$idir/icons/$svc.png" src; src="$(dirname "$SELF")/assets/services/$svc.png"
    mkdir -p "$idir/icons"
    if [ -f "$src" ]; then cp "$src" "$dest"
    elif [ ! -f "$dest" ]; then
        curl -fsSL "$QUICKUP_RAW/assets/services/$svc.png" -o "$dest" 2>/dev/null || true
    fi
    if [ -f "$dest" ]; then printf '%s' "$dest"; else printf '%s' "$ICON"; fi
}

# Show a result when update/uninstall are launched from a file manager (no tty);
# in a terminal the banner already covers it.
gui_notify() {
    [ -t 1 ] && return 0
    if is_mac; then osascript -e "display notification \"$1\" with title \"QuickUp\"" >/dev/null 2>&1 || true
    elif command -v zenity  >/dev/null 2>&1; then zenity --info --title=QuickUp --text="$1" >/dev/null 2>&1 || true
    elif command -v kdialog >/dev/null 2>&1; then kdialog --title QuickUp --msgbox "$1" >/dev/null 2>&1 || true
    fi
}

cmd_install() {
    local dir; dir="$(install_dir)"
    mkdir -p "$dir"
    local target="$dir/quickup.sh"
    [ "$SELF" = "$target" ] || install -m 755 "$SELF" "$target"

    # Menu icon: bundled logo from the repo, or fetched once (best effort).
    local icon="$dir/icon.png" src="$(dirname "$SELF")/assets/logo.png"
    if [ -f "$src" ]; then cp "$src" "$icon"
    elif [ ! -f "$icon" ]; then
        curl -fsSL "$QUICKUP_RAW/assets/logo.png" -o "$icon" 2>/dev/null || true
    fi
    [ -f "$icon" ] && ICON="$icon"

    local integrated=()
    if is_mac; then
        install_macos "$target"; integrated+=("Finder Quick Actions")
    else
        install_nautilus "$target" && integrated+=("Nautilus (GNOME)")
        install_dolphin  "$target" && integrated+=("Dolphin (KDE)")
        install_thunar   "$target" && integrated+=("Thunar (XFCE)")
    fi

    banner INSTALLED
    printf '%s  [ OK ]%s Configured for:\n' "$B_OK" "$B_RST"
    for m in "${integrated[@]}"; do printf '           - %s\n' "$m"; done
    printf '\n'
    field Use    "Right-click a file  ->  QuickUp  ->  pick a host"
    field Hosts  "$(host_list)"
    field Script "$target"
    printf '\n'
    if is_mac; then
        printf '%s  Enable under System Settings -> Extensions -> Finder if needed.%s\n' "$B_DIM" "$B_RST"
    else
        printf '%s  Restart your file manager (or log out/in) to see the menu.%s\n' "$B_DIM" "$B_RST"
    fi
    printf '%s  Uninstall:%s %s"%s" uninstall%s\n' "$B_DIM" "$B_RST" "$B_CMD" "$target" "$B_RST"
    printf '%s%s%s\n\n' "$B_RULE" "$RULE" "$B_RST"
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
    banner REMOVED
    printf '%s  [ OK ]%s Right-click menu entries deleted.\n\n' "$B_OK" "$B_RST"
    field Note "The installed script still lives at:"
    printf '           %s\n' "$(install_dir)"
    printf '%s           Delete that folder to remove QuickUp completely.%s\n' "$B_DIM" "$B_RST"
    printf '%s%s%s\n\n' "$B_RULE" "$RULE" "$B_RST"
    gui_notify "QuickUp removed from the context menu."
}

cmd_update() {
    local tmp; tmp="$(mktemp)"
    echo "Fetching the latest QuickUp ..."
    curl -fsSL "$QUICKUP_RAW/quickup.sh" -o "$tmp"
    sh "$tmp" install
    rm -f "$tmp"
    gui_notify "QuickUp updated to the latest version."
}

cmd_selftest() {
    local ok=1
    for s in "${services[@]}"; do
        display_of "$s" >/dev/null || { echo "no display for $s"; ok=0; }
        [ -n "$(svc_max_bytes "$s")" ] || { echo "no size limit for $s"; ok=0; }
    done
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
    # Management entries (Nautilus scripts have no icons or separators).
    printf '#!/usr/bin/env bash\n"%s" about\n'     "$q" > "$base/About QuickUp";     chmod +x "$base/About QuickUp"
    printf '#!/usr/bin/env bash\n"%s" update\n'    "$q" > "$base/Update QuickUp";    chmod +x "$base/Update QuickUp"
    printf '#!/usr/bin/env bash\n"%s" uninstall\n' "$q" > "$base/Uninstall QuickUp"; chmod +x "$base/Uninstall QuickUp"
}

install_dolphin() {
    local q="$1" idir; idir="$(dirname "$q")"
    local dir="$HOME/.local/share/kio/servicemenus"
    mkdir -p "$dir"
    local f="$dir/quickup.desktop"
    {
        echo "[Desktop Entry]"
        echo "Type=Service"
        echo "MimeType=all/allfiles;"
        printf "Actions="; for s in "${services[@]}"; do printf "%s;" "$s"; done; printf "about;update;uninstall;\n"
        echo "X-KDE-Submenu=QuickUp"
        echo "X-KDE-Priority=TopLevel"
        echo "Icon=$ICON"
        echo
        for s in "${services[@]}"; do
            echo "[Desktop Action $s]"
            echo "Name=$(display_of "$s")"
            echo "Icon=$(svc_icon "$s" "$idir")"
            echo "Exec=\"$q\" upload $s %f"
            echo
        done
        # Dolphin submenus have no separator, so the info/management items just
        # follow the hosts.
        echo "[Desktop Action about]"
        echo "Name=About QuickUp"
        echo "Icon=$ICON"
        echo "Exec=\"$q\" about"
        echo
        echo "[Desktop Action update]"
        echo "Name=Update QuickUp"
        echo "Icon=$ICON"
        echo "Exec=\"$q\" update"
        echo
        echo "[Desktop Action uninstall]"
        echo "Name=Uninstall QuickUp"
        echo "Icon=$ICON"
        echo "Exec=\"$q\" uninstall"
        echo
    } > "$f"
    chmod +x "$f"
}

install_thunar() {
    local q="$1" idir; idir="$(dirname "$q")"
    local dir="$HOME/.config/Thunar"
    local f="$dir/uca.xml"
    mkdir -p "$dir"
    [ -f "$f" ] || printf '<?xml version="1.0" encoding="UTF-8"?>\n<actions>\n</actions>\n' > "$f"
    remove_thunar_block "$f"

    local types='<other-files/><text-files/><image-files/><audio-files/><video-files/>'
    local blk; blk="$(mktemp)"
    {
        echo "<!-- quickup:begin -->"
        for s in "${services[@]}"; do
            printf '<action><icon>%s</icon><name>%s</name><submenu>QuickUp</submenu>' "$(svc_icon "$s" "$idir")" "$(display_of "$s")"
            printf '<unique-id>quickup-%s</unique-id><command>&quot;%s&quot; upload %s %%f</command>' "$s" "$q" "$s"
            printf '<description>QuickUp</description><patterns>*</patterns>%s</action>\n' "$types"
        done
        printf '<action><icon>%s</icon><name>About QuickUp</name><submenu>QuickUp</submenu>' "$ICON"
        printf '<unique-id>quickup-about</unique-id><command>&quot;%s&quot; about</command>' "$q"
        printf '<description>QuickUp</description><patterns>*</patterns>%s</action>\n' "$types"
        printf '<action><icon>%s</icon><name>Update QuickUp</name><submenu>QuickUp</submenu>' "$ICON"
        printf '<unique-id>quickup-update</unique-id><command>&quot;%s&quot; update</command>' "$q"
        printf '<description>QuickUp</description><patterns>*</patterns>%s</action>\n' "$types"
        printf '<action><icon>%s</icon><name>Uninstall QuickUp</name><submenu>QuickUp</submenu>' "$ICON"
        printf '<unique-id>quickup-uninstall</unique-id><command>&quot;%s&quot; uninstall</command>' "$q"
        printf '<description>QuickUp</description><patterns>*</patterns>%s</action>\n' "$types"
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
    update)    cmd_update ;;
    upload)    cmd_upload "${2:?service}" "${3:?file}" ;;
    about)     cmd_about ;;
    selftest)  cmd_selftest ;;
    *)         echo "usage: quickup.sh {install|uninstall|update|about|upload <service> <file>}" >&2; exit 1 ;;
esac
