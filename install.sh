#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v pacman >/dev/null 2>&1; then
    echo "This installer expects Omarchy (pacman)." >&2
    exit 1
fi

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not as root or via 'sudo ./install.sh'." >&2
    echo "It will call sudo itself for the steps that need it." >&2
    exit 1
fi

INSTALL_USER="$USER"

sudo -v
sudo pacman -S --needed base-devel hidapi pkgconf

make clean all

sudo install -Dm755 build/omarchy-k380-fnlock-engine \
    /usr/lib/omarchy-k380-fnlock/engine
sudo install -Dm755 bin/omarchy-k380-fnlock \
    /usr/bin/omarchy-k380-fnlock
sudo install -Dm644 systemd/omarchy-k380-fnlock.service \
    /etc/systemd/user/omarchy-k380-fnlock.service
sudo install -Dm644 udev/90-omarchy-k380-fnlock.rules \
    /etc/udev/rules.d/90-omarchy-k380-fnlock.rules

sudo udevadm control --reload-rules
# Применить новое правило к уже подключённой K380 и остальным hidraw.
sudo udevadm trigger --action=add --subsystem-match=hidraw
sudo udevadm settle

USER_RUNTIME_DIR="/run/user/$(id -u "$INSTALL_USER")"

if [[ -d "$USER_RUNTIME_DIR" ]] &&
   sudo -u "$INSTALL_USER" \
       env XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
       systemctl --user daemon-reload; then
    :
else
    echo "Warning: could not reload the user systemd manager now." >&2
    echo "The unit will be picked up at the next user login." >&2
fi

echo "Installed. Try: omarchy-k380-fnlock set on"