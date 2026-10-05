#!/bin/bash
# Validation script for Bazzite-Deepin dependencies

echo "--- Checking Deepin Packages ---"
PACKAGES=(deepin-desktop deepin-kwin deepin-control-center deepin-launcher deepin-session-ui deepin-terminal jq)

for pkg in "${PACKAGES[@]}"; do
    if dnf info "$pkg" > /dev/null 2>&1; then
        echo "✅ $pkg found"
    else
        echo "❌ $pkg NOT FOUND - check 'dnf search deepin' for alternatives"
    fi
done

echo -e "\n--- Checking Systemd Units ---"
# Locates the .service file within the deepin-daemon package
if rpm -ql deepin-daemon | grep -E "dde-daemon.service|dde-system-daemon.service" > /dev/null; then
    UNIT=$(rpm -ql deepin-daemon | grep -oP 'dde-.*\.service' | head -n 1)
    echo "✅ Found unit: $UNIT"
else
    echo "❌ Could not locate dde service unit in deepin-daemon package"
fi