#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not as root or via 'sudo ./uninstall.sh'." >&2
    exit 1
fi

INSTALL_USER="$USER"
USER_RUNTIME_DIR="/run/user/$(id -u "$INSTALL_USER")"

sudo -v

if [[ -d "$USER_RUNTIME_DIR" ]]; then
    sudo -u "$INSTALL_USER" \
        env XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        systemctl --user stop omarchy-k380-fnlock.service 2>/dev/null || true
fi

sudo rm -f /usr/bin/omarchy-k380-fnlock
sudo rm -f /usr/lib/omarchy-k380-fnlock/engine
sudo rm -f /etc/systemd/user/omarchy-k380-fnlock.service
sudo rm -f /etc/systemd/system/omarchy-k380-fnlock.service
sudo rm -f /etc/udev/rules.d/90-omarchy-k380-fnlock.rules
sudo rm -f /etc/sudoers.d/omarchy-k380-fnlock
sudo rmdir --ignore-fail-on-non-empty /usr/lib/omarchy-k380-fnlock

if [[ -d "$USER_RUNTIME_DIR" ]]; then
    sudo -u "$INSTALL_USER" \
        env XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        systemctl --user daemon-reload 2>/dev/null || true
fi

sudo udevadm control --reload-rules

echo "Uninstalled. Saved state in"
echo "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-k380-fnlock was left intact."