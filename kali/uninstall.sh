#!/usr/bin/env bash
# Removes everything installed by install.sh
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0"; exit 1; }

systemctl disable --now displaylink-driver.service 2>/dev/null
rm -f /etc/systemd/system/displaylink-driver.service \
      /usr/lib/systemd/system-sleep/displaylink.sh \
      /etc/udev/rules.d/99-displaylink.rules \
      /etc/modprobe.d/evdi.conf /etc/modules-load.d/evdi.conf \
      /usr/local/bin/usb-screen /usr/local/bin/pantalla-usb
if [[ -n "${SUDO_USER:-}" ]]; then
    UHOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    rm -f "$UHOME/.config/autostart/usb-screen.desktop" "$UHOME/.config/autostart/pantalla-usb.desktop"
fi
pkill -f 'usb-screen watch' 2>/dev/null
pkill -f 'pantalla-usb vigilar' 2>/dev/null
rm -rf /opt/displaylink
systemctl daemon-reload
udevadm control --reload-rules
modprobe -r evdi 2>/dev/null
if [[ "${1:-}" == "--purge" ]]; then
    apt-get remove -y evdi-dkms libevdi1
fi
echo "Uninstalled. (Use --purge to also remove evdi-dkms and libevdi1)"
