#!/usr/bin/env bash
# Control the ASUS MB168B USB display (DisplayLink/EVDI) on X11.
#
#   usb-screen mirror    -> mirror the built-in screen (default)
#   usb-screen extend    -> extended desktop (USB screen on the right)
#   usb-screen off       -> turn off the USB output
#   usb-screen status    -> show providers and outputs
#   usb-screen watch     -> stay in the background and mirror every time
#                           the display is plugged in (used by autostart)
#
# Optional variables:
#   USB_SCREEN_OUTPUT=DVI-I-1-1     force the USB output name
#   USB_SCREEN_INTERNAL=eDP-1       force the main (built-in) screen
#   USB_SCREEN_POSITION=right-of    (extend) left-of|right-of|above|below
set -uo pipefail

log() { printf '[usb-screen] %s\n' "$*"; }

[[ -n "${DISPLAY:-}" ]] || { log "No DISPLAY found (run it inside your graphical session)."; exit 1; }
[[ "${XDG_SESSION_TYPE:-x11}" == "wayland" ]] && \
    log "Warning: Wayland session. Use your desktop's display settings; xrandr only works on X11."

# Link the EVDI (DisplayLink) providers to the main GPU.
# Without this the USB output exists but receives no image.
link_providers() {
    local providers primary
    providers="$(xrandr --listproviders 2>/dev/null)"
    primary="$(sed -n 's/^Provider 0: id: \(0x[0-9a-f]*\).*/\1/p' <<<"$providers")"
    [[ -n "$primary" ]] || return 0
    # EVDI shows up as a "modesetting" provider with 1 output that is not provider 0;
    # real GPUs (AMD/NVIDIA/Intel) with their own driver name are excluded.
    while read -r id; do
        xrandr --setprovideroutputsource "$id" "$primary" 2>/dev/null || true
    done < <(grep -E '^Provider [1-9]' <<<"$providers" \
             | grep -E 'name:modesetting' | grep -vE 'outputs: 0 ' \
             | sed -n 's/^Provider [0-9]*: id: \(0x[0-9a-f]*\).*/\1/p')
}

internal_output() {
    if [[ -n "${USB_SCREEN_INTERNAL:-}" ]]; then echo "$USB_SCREEN_INTERNAL"; return; fi
    local o
    o="$(xrandr | awk '/ connected primary/{print $1; exit}')"
    [[ -z "$o" ]] && o="$(xrandr | awk '/^(eDP|LVDS)[^ ]* connected/{print $1; exit}')"
    [[ -z "$o" ]] && o="$(xrandr | awk '/ connected/{print $1; exit}')"
    echo "$o"
}

usb_output() {
    if [[ -n "${USB_SCREEN_OUTPUT:-}" ]]; then echo "$USB_SCREEN_OUTPUT"; return; fi
    # EVDI creates outputs named DVI-I-<n>-<m> (or DVI-I-<n>) with the modesetting driver
    xrandr | awk '/^DVI-I[-0-9]* connected/{print $1; exit}'
}

preferred_mode() {   # $1 = output -> preferred mode (marked with +)
    # Mode marked with "+"; if none, the first one listed
    xrandr | awk -v o="$1" '
        $1==o {f=1; next}
        f && /^[^ ]/ {exit}
        f && !first {first=$1}
        f && /\+/ {pref=$1; exit}
        END {print (pref ? pref : first)}'
}

current_mode() {     # $1 = output -> current resolution WxH
    xrandr | awk -v o="$1" '$1==o {
        for (i=3;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+/) {split($i,a,"+"); print a[1]; exit}}'
}

wait_usb() {   # wait up to $1 seconds for the USB output to appear
    local t="${1:-15}" out
    for ((i=0; i<t; i++)); do
        link_providers
        out="$(usb_output)"
        [[ -n "$out" ]] && { echo "$out"; return 0; }
        sleep 1
    done
    return 1
}

do_mirror() {
    local usb int imode umode
    usb="$(wait_usb 15)" || { log "USB display not detected. Is it plugged in and is displaylink-driver running? (./diagnose.sh)"; exit 1; }
    int="$(internal_output)"
    imode="$(current_mode "$int")"
    [[ -z "$imode" ]] && imode="$(preferred_mode "$int")"
    umode="$(preferred_mode "$usb")"
    [[ -z "$umode" ]] && umode="1366x768"
    if [[ "$imode" == "$umode" ]]; then
        log "Mirroring $int ($imode) -> $usb ($umode)"
        xrandr --output "$usb" --mode "$umode" --scale 1x1 --same-as "$int"
    else
        # Different resolutions: the USB screen scales the built-in screen's image
        log "Mirroring $int ($imode) -> $usb ($umode, scaled)"
        xrandr --output "$usb" --mode "$umode" --scale-from "$imode" --same-as "$int"
    fi
}

do_extend() {
    local usb int pos
    usb="$(wait_usb 15)" || { log "USB display not detected."; exit 1; }
    int="$(internal_output)"
    pos="${USB_SCREEN_POSITION:-right-of}"
    log "Extending: $usb $pos $int"
    xrandr --output "$usb" --auto --scale 1x1 "--$pos" "$int"
}

do_off() {
    local usb; usb="$(usb_output)"
    [[ -n "$usb" ]] && xrandr --output "$usb" --off && log "Output $usb turned off."
}

do_status() {
    xrandr --listproviders
    echo
    xrandr | grep -E ' connected|\*'
    echo
    log "Internal: $(internal_output)   USB: $(usb_output || true)"
    systemctl is-active displaylink-driver.service >/dev/null 2>&1 \
        && log "displaylink-driver service: active" \
        || log "displaylink-driver service: INACTIVE"
}

do_watch() {
    local mode="${1:-mirror}" last="" now
    log "Watching for USB display connections (mode: $mode)…"
    while true; do
        link_providers
        now="$(usb_output)"
        if [[ -n "$now" && "$now" != "$last" ]]; then
            sleep 2   # give EVDI time to publish the modes
            if [[ "$mode" == "extend" || "$mode" == "extender" ]]; then do_extend; else do_mirror; fi
        fi
        last="$now"
        sleep 3
    done
}

# Spanish aliases (duplicar, extender, …) are kept for older installs.
case "${1:-mirror}" in
    mirror|duplicar)  do_mirror ;;
    extend|extender)  do_extend ;;
    off|apagar)       do_off ;;
    status|estado)    do_status ;;
    watch|vigilar)    do_watch "${2:-mirror}" ;;
    -h|--help|help)   sed -n '2,15p' "$0" ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
esac
