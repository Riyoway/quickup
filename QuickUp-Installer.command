#!/bin/bash
echo
echo "  =========================================="
echo "     QuickUp  -  Installer"
echo "  =========================================="
echo
echo "  Adds a QuickUp entry to Finder's right-click"
echo "  (Quick Actions) menu so you can upload files."
echo
echo "  Installing..."
echo
curl -fsSL https://raw.githubusercontent.com/Riyoway/quickup/main/quickup.sh | sh
echo
echo "  Right-click a file in Finder -> Quick Actions -> QuickUp."
echo
read -r -p "  Press Enter to close. " _
