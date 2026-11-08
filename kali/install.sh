#!/usr/bin/env bash
# Installer for the USB driver of the ASUS MB168B display (DisplayLink DL-3xxx)
# on Kali / Debian.
#
#   Kernel : EVDI (free module, via DKMS)              -> evdi-dkms
#   User   : libevdi + DisplayLinkManager (Synaptics)  -> /opt/displaylink
#   Autostart: systemd service + udev rule
#
# Usage:  sudo ./install.sh            (normal install)
#         sudo ./install.sh --no-upgrade-kernel
set -euo pipefail

DL_VERSION="6.4"
DL_FULLVER="6.4.0-22"
DL_URL="https://www.synaptics.com/sites/default/files/exe_files/2026-10/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu${DL_VERSION}-EXE.zip"
DL_SHA256="7e1a81d2194a40b20de704cb3846d66cbfb1e7837e30de23455729ba14f0296d"

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="/opt/displaylink"
CACHE="$HERE/downloads"
UPGRADE_KERNEL=1
[[ "${1:-}" == "--no-upgrade-kernel" ]] && UPGRADE_KERNEL=0

msg()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[!]\e[0m %s\n' "$*"; }
die()  { printf '\e[1;31m[x]\e[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run with sudo:  sudo $0"
[[ "$(uname -m)" == "x86_64" ]] || die "This installer only supports x86_64."

# ------------------------------------------------ 0. Check the distribution
# Debian family only (uses apt and the evdi-dkms / libevdi1 packages).
command -v apt-get >/dev/null || die "This distro does not use apt. This installer is only for Kali/Debian/Ubuntu and derivatives (see the README)."
OS_ID="unknown"; OS_LIKE=""
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"; OS_LIKE="${ID_LIKE:-}"
fi
case " $OS_ID $OS_LIKE " in
    *" kali "*)   msg "Distribution: Kali Linux (tested)." ;;
    *" debian "*|*" ubuntu "*) warn "Distribution: ${PRETTY_NAME:-$OS_ID}. Debian family: it should work, but it has only been tested on Kali." ;;
    *) warn "Unrecognized distribution (${PRETTY_NAME:-$OS_ID}). Trying anyway because apt is available." ;;
esac

# ---------------------------------------------------------------- 1. Packages
msg "Installing dependencies (dkms, evdi, libusb)…"
apt-get update
apt-get install -y dkms curl unzip libusb-1.0-0 pciutils usbutils x11-xserver-utils

# ------------------------------------------------------- 2. Kernel headers
KREL="$(uname -r)"
NEED_REBOOT=0
if [[ -d "/lib/modules/$KREL/build" ]]; then
    msg "Kernel headers for $KREL already present."
elif apt-cache show "linux-headers-$KREL" >/dev/null 2>&1; then
    msg "Installing linux-headers-$KREL…"
    apt-get install -y "linux-headers-$KREL"
else
    warn "Your distro no longer publishes headers for the running kernel ($KREL)."
    warn "EVDI is built against the headers, so you need to move to the current kernel."
    [[ $UPGRADE_KERNEL -eq 1 ]] || die "EVDI cannot be built without headers. Remove --no-upgrade-kernel."
    if apt-cache show linux-image-amd64 >/dev/null 2>&1; then        # Kali / Debian
        KPKGS="linux-image-amd64 linux-headers-amd64"
    elif apt-cache show linux-generic >/dev/null 2>&1; then          # Ubuntu and derivatives
        KPKGS="linux-generic"
    else
        die "Don't know which kernel package to use on this distro. Install a kernel with its headers manually and retry."
    fi
    msg "Installing the current kernel + its headers ($KPKGS)…"
    # shellcheck disable=SC2086
    apt-get install -y $KPKGS
    NEED_REBOOT=1
fi
# Make sure headers get installed for any future kernel (metapackage per distro)
apt-get install -y linux-headers-amd64 2>/dev/null || apt-get install -y linux-headers-generic 2>/dev/null || true

# --------------------------------------------------------- 3. EVDI (kernel)
msg "Installing EVDI (evdi-dkms + libevdi1)…"
apt-get install -y evdi-dkms libevdi1

# DKMS builds for every kernel that has headers; check it worked
if ! dkms status evdi 2>/dev/null | grep -q installed; then
    warn "The evdi-dkms package did not build. Check: /var/lib/dkms/evdi/*/build/make.log"
fi

cat > /etc/modprobe.d/evdi.conf <<'EOF'
# Created by asus-mb168b-linux-usb-monitor (ASUS MB168B)
options evdi initial_device_count=4
EOF
echo evdi > /etc/modules-load.d/evdi.conf

# ------------------------------------------- 4. DisplayLinkManager (user space)
mkdir -p "$CACHE"
ZIP="$CACHE/displaylink-${DL_VERSION}.zip"
if [[ ! -f "$ZIP" ]] || ! echo "$DL_SHA256  $ZIP" | sha256sum -c --quiet - 2>/dev/null; then
    msg "Downloading DisplayLink ${DL_VERSION} from synaptics.com…"
    echo "    (By installing it you accept the DisplayLink EULA: https://www.synaptics.com/products/displaylink-graphics/downloads/ubuntu)"
    curl -fL -A 'Mozilla/5.0' -o "$ZIP" "$DL_URL"
fi
echo "$DL_SHA256  $ZIP" | sha256sum -c --quiet - || die "DisplayLink ZIP checksum mismatch."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q -o "$ZIP" -d "$WORK"
RUN="$(find "$WORK" -name "displaylink-driver-${DL_FULLVER}.run" | head -n1)"
[[ -n "$RUN" ]] || die "The .run file was not found inside the ZIP."

# The .run is a makeself archive. We do NOT execute it (its installer only
# supports Ubuntu): we extract the embedded tar.gz by hand.
SKIP="$(head -n 1000 "$RUN" | grep -a -m1 '^skip=' | tr -dc '0-9')"
SIZE="$(head -n 1000 "$RUN" | grep -a -m1 '^filesizes=' | tr -dc '0-9')"
OFFSET="$(head -n "$SKIP" "$RUN" | wc -c)"
mkdir -p "$WORK/pkg"
tail -c +"$((OFFSET + 1))" "$RUN" | head -c "$SIZE" | tar xz -C "$WORK/pkg"
[[ -x "$WORK/pkg/x64-ubuntu-1604/DisplayLinkManager" ]] || die "Unexpected DisplayLink package layout."

msg "Installing DisplayLinkManager into $PREFIX…"
systemctl stop displaylink-driver.service 2>/dev/null || true
install -d -m755 "$PREFIX" /var/log/displaylink
install -m755 "$WORK/pkg/x64-ubuntu-1604/DisplayLinkManager" "$PREFIX/"
install -m644 "$WORK"/pkg/*.spkg "$PREFIX/"            # chip firmware
install -m644 "$WORK/pkg/LICENSE" "$PREFIX/LICENSE"
install -m755 "$WORK/pkg/DLSupportTool.sh" "$PREFIX/"
# Copy of the official EVDI source code, in case it ever needs to be built
install -m644 "$WORK/pkg/evdi.tar.gz" "$PREFIX/evdi-src.tar.gz"
echo "$DL_FULLVER" > "$PREFIX/VERSION"

# ---------------------------------------------------- 5. systemd service
msg "Creating displaylink-driver.service…"
cat > /etc/systemd/system/displaylink-driver.service <<EOF
[Unit]
Description=DisplayLink Driver Service (ASUS MB168B)
After=display-manager.service
Conflicts=getty@tty7.service

[Service]
ExecStartPre=/sbin/modprobe evdi
ExecStart=$PREFIX/DisplayLinkManager
WorkingDirectory=$PREFIX
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

# Restart the manager after resuming from suspend (avoids a black screen)
install -d /usr/lib/systemd/system-sleep
cat > /usr/lib/systemd/system-sleep/displaylink.sh <<'EOF'
#!/bin/sh
# Created by asus-mb168b-linux-usb-monitor
case "$1" in
  post) systemctl restart --no-block displaylink-driver.service ;;
esac
EOF
chmod 755 /usr/lib/systemd/system-sleep/displaylink.sh

# ---------------------------------------------------------- 6. udev rule
msg "Creating udev rule (start when the USB device is plugged in)…"
cat > /etc/udev/rules.d/99-displaylink.rules <<'EOF'
# Created by asus-mb168b-linux-usb-monitor: DisplayLink devices (17e9) -> start DLM
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="17e9", \
    TAG+="systemd", ENV{SYSTEMD_WANTS}+="displaylink-driver.service"
EOF
udevadm control --reload-rules

systemctl daemon-reload
systemctl enable displaylink-driver.service

# -------------------------------------------- 7. Screen control script (user)
install -m755 "$HERE/usb-screen.sh" /usr/local/bin/usb-screen
rm -f /usr/local/bin/pantalla-usb                      # old (Spanish) name
REAL_USER="${SUDO_USER:-}"
if [[ -n "$REAL_USER" ]]; then
    UHOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
    install -d -o "$REAL_USER" -g "$REAL_USER" "$UHOME/.config/autostart"
    install -m644 -o "$REAL_USER" -g "$REAL_USER" "$HERE/usb-screen-autostart.desktop" \
        "$UHOME/.config/autostart/usb-screen.desktop"
    rm -f "$UHOME/.config/autostart/pantalla-usb.desktop"   # old (Spanish) name
    pkill -f 'pantalla-usb vigilar' 2>/dev/null || true
    msg "Automatic mirroring on login enabled for $REAL_USER."
fi

# ---------------------------------------------------------------- 8. Done
if [[ $NEED_REBOOT -eq 1 ]]; then
    echo
    warn "A new kernel was installed. REBOOT the computer and boot into it."
    warn "After rebooting the service starts by itself. Check with:  ./diagnose.sh"
    exit 0
fi

msg "Loading EVDI and starting DisplayLinkManager…"
modprobe evdi || die "Could not load evdi (Secure Boot? see the README)."
systemctl restart displaylink-driver.service
echo
msg "Done. Plug in the MB168B via USB and run:  usb-screen mirror"
