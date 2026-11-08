# ASUS MB168B on Linux: plug-and-play USB second screen

![License: MIT](https://img.shields.io/badge/license-MIT-green.svg) ![Kali Linux](https://img.shields.io/badge/tested-Kali%20Linux-557C94.svg)

Scripts to get a **portable USB monitor with a DisplayLink chip**, such as the **ASUS MB168B**, working on Linux. When you plug it in via USB it **mirrors your screen automatically**.

> ✅ **Tested and working on Kali Linux** (XFCE, X11, kernel 7.2.x).

### 🖥️ Built for the ASUS MB168B

This project was created and tested specifically for the **ASUS MB168B** 15.6" portable USB monitor:

| | |
|---|---|
| Monitor | **ASUS MB168B** (USB-powered, single cable) |
| USB ID | `17e9:ff03` (DisplayLink) |
| Chip | DisplayLink **DL-3xxx** (USB 3.0, protocol 3) |
| Native resolution | 1366x768 |

Other monitors and docks with a **DisplayLink** chip (USB vendor `17e9`) will most likely work too, since the driver stack is the same, but only the MB168B has been tested.

---

## Table of contents

1. [Does it work on my distribution?](#-does-it-work-on-my-distribution)
2. [Requirements](#-requirements)
3. [Step-by-step installation](#-step-by-step-installation)
4. [Daily use](#-daily-use)
5. [How it works](#-how-it-works)
6. [Troubleshooting](#-troubleshooting)
7. [Uninstall](#-uninstall)
8. [Repository layout](#-repository-layout)
9. [License and legal notice](#-license-and-legal-notice)

---

## 🐧 Does it work on my distribution?

**Not on all of them.** The installer uses `apt` and Debian's `evdi-dkms` and `libevdi1` packages, so it only works on the **Debian family**.

| Distribution | Status | Notes |
|---|---|---|
| **Kali Linux** (rolling) | ✅ **Tested** | Works great. This is what it was built for. |
| Debian 12 / 13 | 🟡 Should work | Same packages as Kali (`evdi-dkms`, `linux-headers-amd64`). |
| Parrot OS | 🟡 Should work | Based on Debian. |
| Ubuntu 22.04+ / Linux Mint / Pop!_OS / Zorin | 🟡 Should work | `evdi-dkms` is in *universe*. On Ubuntu you can also use the official Synaptics installer. |
| Fedora / RHEL | ❌ No | Uses `dnf`. Alternative: the DisplayLink RPM from [displaylink-rpm](https://github.com/displaylink-rpm/displaylink-rpm). |
| Arch / Manjaro / EndeavourOS | ❌ No | Uses `pacman`. Alternative: `evdi` and `displaylink` from the AUR ([wiki](https://wiki.archlinux.org/title/DisplayLink)). |
| openSUSE | ❌ No | Uses `zypper`. Alternative: the `X11:Utilities` repository or the DisplayLink RPM. |

The installer **detects your distro**: if `apt` is missing it stops with a message, and if it isn't Kali it shows a warning but keeps going.

**Desktop:** automatic mirroring (`usb-screen`) uses `xrandr`, so it needs an **X11 session** (XFCE, MATE, Cinnamon, LXQt, or GNOME/KDE "on Xorg"). On **Wayland** the driver still works, but you configure the screen from your desktop's display settings.

---

## 📋 Requirements

- An **x86_64** (64-bit) PC.
- A Debian-family distro (see the table).
- An Internet connection (to download dependencies and the Synaptics driver).
- `sudo` privileges.
- A USB monitor with a **DisplayLink** chip (USB vendor `17e9`). To check:
  ```bash
  lsusb | grep -i 17e9
  ```
- If **Secure Boot** is enabled, see [Troubleshooting](#-troubleshooting).

---

## 🚀 Step-by-step installation

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/asus-mb168b-linux-usb-monitor.git
cd asus-mb168b-linux-usb-monitor/kali
```

### 2. Make the scripts executable (in case permissions were lost)

```bash
chmod +x *.sh
```

### 3. Run the installer

```bash
sudo ./install.sh
```

> By installing you accept the [DisplayLink EULA](https://www.synaptics.com/products/displaylink-graphics/downloads/ubuntu). The installer **downloads the official driver from synaptics.com** and checks its SHA-256 before using it.

What it does, in order:

1. Checks that your distro is supported.
2. Installs the dependencies: `dkms`, `curl`, `unzip`, `libusb-1.0-0`, `x11-xserver-utils`…
3. Checks the **kernel headers**. If your distro no longer publishes them for the kernel you're running (common on Kali), it installs the latest kernel with its headers and **asks you to reboot**.
4. Installs **EVDI** (`evdi-dkms`, `libevdi1`), the kernel module that creates the virtual display.
5. Downloads **DisplayLink 6.4**, extracts `DisplayLinkManager` and the firmware **without running** the `.run` file (it only supports Ubuntu), and copies them to `/opt/displaylink`.
6. Creates the `displaylink-driver.service` service, a **udev** rule that starts it when the USB device is plugged in, and a hook that restarts it after suspend.
7. Installs the `usb-screen` command into `/usr/local/bin` and an **autostart** entry that mirrors the screen when you log in.

### 4. Reboot

```bash
sudo reboot
```

You **must** reboot if the installer installed a new kernel, and it's always a good idea. In the GRUB menu, boot the newest kernel (usually the default).

### 5. Check that everything is OK

```bash
cd asus-mb168b-linux-usb-monitor/kali
./diagnose.sh
```

Everything should be **green `[OK]`**.

### 6. Plug in the screen

Plug the monitor in via USB. After you log in, it **mirrors by itself**. If it doesn't, run:

```bash
usb-screen mirror
```

### Quick summary (copy and paste)

```bash
git clone https://github.com/<your-username>/asus-mb168b-linux-usb-monitor.git
cd asus-mb168b-linux-usb-monitor/kali
chmod +x *.sh
sudo ./install.sh
sudo reboot
# after rebooting:
cd asus-mb168b-linux-usb-monitor/kali && ./diagnose.sh
usb-screen mirror
```

---

## 🖥️ Daily use

```bash
usb-screen mirror     # mirror the laptop screen (default)
usb-screen extend     # extended desktop (USB screen on the right)
usb-screen off        # turn off the USB output
usb-screen status     # show providers, outputs and service status
usb-screen --help     # show help
```

Optional variables:

```bash
USB_SCREEN_POSITION=left-of usb-screen extend    # left-of | right-of | above | below
USB_SCREEN_OUTPUT=DVI-I-1-1 usb-screen mirror    # force the USB output name
USB_SCREEN_INTERNAL=eDP-1   usb-screen mirror    # force the main screen
```

If the resolutions don't match, `mirror` **scales** the image automatically.

Want the screen to **extend** instead of mirror when plugged in? Edit `~/.config/autostart/usb-screen.desktop` and change `watch mirror` to `watch extend`.

---

## ⚙️ How it works

Modern DisplayLink chips (DL-3xxx/DL-5xxx, USB 3 protocol) use a **proprietary, encrypted** protocol, so the kernel's free `udl` module doesn't work with them. The only way to drive them is:

```
 Apps ─► Xorg ─► EVDI (free module, DKMS) ─► DisplayLinkManager (Synaptics) ─► USB ─► Monitor
                 "virtual DRM display"        compresses and sends the image
```

| Option considered | Works? | Reason |
|---|---|---|
| Free `udl` module | ❌ | Only for old DL-1x0/1x5 chips (protocol 0). |
| Writing a driver from scratch | ❌ | The DL-3 protocol is undocumented and encrypted. |
| **EVDI + DisplayLinkManager** | ✅ | The official solution. This is what's used here. |
| Official `.run` installer | ⚠️ | Only supports Ubuntu. Its contents are extracted by hand here. |

For the USB output to receive an image, `usb-screen` links the providers:

```bash
xrandr --setprovideroutputsource <EVDI-provider> <provider-0>
xrandr --output DVI-I-1-1 --mode 1366x768 --same-as eDP-1
```

**Test hardware:** ASUS MB168B (`17e9:ff03`, 1366x768), Intel UHD 620 + AMD Radeon 540, Kali with XFCE/X11, kernel 7.2.15.

---

## 🛠️ Troubleshooting

Always start with:

```bash
./diagnose.sh
systemctl status displaylink-driver
journalctl -u displaylink-driver -b
ls /var/log/displaylink/
```

| Problem | Solution |
|---|---|
| **Black screen / no `DVI-I-*` output** | Replug the cable and run `usb-screen mirror`. Check `systemctl status displaylink-driver`. |
| **`modprobe evdi` → "Key was rejected by service"** | **Secure Boot** is enabled. Enroll the DKMS key with `sudo mokutil --import /var/lib/dkms/mok.pub`, reboot, choose *Enroll MOK* on the blue screen and enter the password. Or disable Secure Boot in the BIOS. |
| **"Missing kernel headers"** | Run `sudo ./install.sh` again, reboot and boot the **newest** kernel. |
| **Stops working after a kernel update** | Make sure the headers metapackage is installed (`linux-headers-amd64` on Kali/Debian, `linux-headers-generic` on Ubuntu). DKMS rebuilds EVDI automatically. Check with `dkms status`. |
| **Laggy / slow** | You're on a **USB 2.0** port. Use a USB 3 (blue) port and the original cable. |
| **Tearing (lines when moving windows) on Intel** | Create `/etc/X11/xorg.conf.d/20-modesetting.conf` with `Option "PageFlip" "false"` in the `Device` section for the `modesetting` driver. |
| **Black screen after suspend** | The hook already restarts the service. If it still happens: `sudo systemctl restart displaylink-driver && usb-screen mirror`. |
| **I'm on Wayland** | Log out and choose "Xorg"/"X11" on the login screen, or configure the screen from your desktop's display settings. |
| **Download fails or checksum doesn't match** | Synaptics may have changed the URL. Manually download *DisplayLink USB Graphics Software for Ubuntu 6.4* from their website and save it as `kali/downloads/displaylink-6.4.zip`. |

---

## 🗑️ Uninstall

```bash
cd asus-mb168b-linux-usb-monitor/kali
sudo ./uninstall.sh           # removes the service, rules, autostart and /opt/displaylink
sudo ./uninstall.sh --purge   # also removes evdi-dkms and libevdi1
```

---

## 📁 Repository layout

```
asus-mb168b-linux-usb-monitor/
├── README.md                        ← this file
├── LICENSE                          ← MIT license
├── GITHUB_INFO.txt                  ← title/description to paste on GitHub
├── .gitignore                       ← excludes the DisplayLink binaries
└── kali/                            ← everything needed for Kali / Debian family
    ├── install.sh                   ← installer (sudo)
    ├── uninstall.sh                 ← uninstaller (sudo)
    ├── diagnose.sh                  ← checks every component (no sudo)
    ├── usb-screen.sh                ← mirror / extend / off / status / watch
    ├── usb-screen-autostart.desktop ← autostart: mirrors on login
    └── downloads/                   ← (created automatically, NOT uploaded to GitHub)
```

---

## ⚖️ License and legal notice

- The **scripts** in this repository are released under the **[MIT license](LICENSE)**: you can use, modify and redistribute them freely, as long as you keep the copyright notice.
- **EVDI** is free software (GPL/LGPL) and is installed from your distro's repositories.
- **DisplayLinkManager** and its firmware are **proprietary Synaptics software**. They are **not included** in this repository: `install.sh` downloads them from the official website, and by installing them you accept their [EULA](https://www.synaptics.com/products/displaylink-graphics/downloads/ubuntu).
- This project is not affiliated with ASUS, Synaptics or DisplayLink.
