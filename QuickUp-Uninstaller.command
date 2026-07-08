#!/bin/bash
echo
echo "  Removing QuickUp..."
echo
D="$HOME/Library/Application Support/QuickUp/quickup.sh"
if [ -f "$D" ]; then
    bash "$D" uninstall
else
    echo "  QuickUp does not appear to be installed."
fi
echo
read -r -p "  Press Enter to close. " _
