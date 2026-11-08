#!/usr/bin/env bash
# Diagnostics for the ASUS MB168B USB display. Does not require sudo (some
# checks give more detail when run with sudo).
ok()  { printf '  \e[32m[OK]\e[0m %s\n' "$*"; }
bad() { printf '  \e[31m[XX]\e[0m %s\n' "$*"; }
inf() { printf '  \e[36m[..]\e[0m %s\n' "$*"; }

echo "== USB device"
if lsusb -d 17e9: >/dev/null 2>&1; then
    lsusb -d 17e9: | sed 's/^/  /'
    proto="$(lsusb -v -d 17e9: 2>/dev/null | awk '/bInterfaceClass +255/{f=1} f&&/bInterfaceProtocol/{print $2; exit}')"
    case "$proto" in
        3) ok "DisplayLink DL-3xxx chip (protocol 3): requires EVDI + DisplayLinkManager" ;;
        0) inf "Older DisplayLink chip (protocol 0): would also work with the free 'udl' module" ;;
        *) inf "Interface protocol: ${proto:-unknown}" ;;
    esac
    bus="$(lsusb -d 17e9: | awk '{print $2}' | head -1)"
    speed="$(cat /sys/bus/usb/devices/usb$((10#$bus))/speed 2>/dev/null)"
    [[ "$speed" == "480" ]] && inf "Connected to a USB 2.0 bus (480 Mb/s). It works, but a USB 3 (blue) port will be smoother."
else
    bad "No DisplayLink device (17e9) detected. Check the USB cable."
fi

echo "== Kernel / EVDI"
k="$(uname -r)"; inf "Running kernel: $k"
[[ -d "/lib/modules/$k/build" ]] && ok "Kernel headers present" || bad "Missing headers for $k (run sudo ./install.sh)"
if modinfo evdi >/dev/null 2>&1; then ok "evdi module available ($(modinfo -F version evdi))"; else bad "evdi module not built for $k"; fi
lsmod | grep -q '^evdi' && ok "evdi loaded" || bad "evdi NOT loaded (sudo modprobe evdi)"
command -v dkms >/dev/null && dkms status evdi 2>/dev/null | sed 's/^/  dkms: /'
if [[ -d /sys/firmware/efi ]] && command -v mokutil >/dev/null; then
    mokutil --sb-state 2>/dev/null | grep -qi enabled && inf "Secure Boot ENABLED: the evdi module must be signed (see README)"
fi

echo "== DisplayLinkManager"
[[ -x /opt/displaylink/DisplayLinkManager ]] && ok "Installed ($(cat /opt/displaylink/VERSION 2>/dev/null))" || bad "Not installed"
if systemctl is-active displaylink-driver.service >/dev/null 2>&1; then ok "Service active"
else bad "Service inactive (sudo systemctl start displaylink-driver)"; fi
ls /var/log/displaylink/*.log >/dev/null 2>&1 && inf "Logs: /var/log/displaylink/"

echo "== X11"
inf "Session: ${XDG_SESSION_TYPE:-?} / ${XDG_CURRENT_DESKTOP:-?}"
if [[ -n "${DISPLAY:-}" ]]; then
    xrandr --listproviders | sed 's/^/  /'
    xrandr | grep -E ' connected' | sed 's/^/  /'
    xrandr | grep -qE '^DVI-I[-0-9]* connected' && ok "USB output detected: run 'usb-screen mirror'" \
        || inf "No DVI-I-* output yet (run 'usb-screen mirror' to link the providers)"
fi
