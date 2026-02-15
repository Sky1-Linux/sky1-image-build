#!/bin/bash
# Enable full ASPM for RTL8126 NICs after driver init
# Driver uses aspm=0 to avoid init errors, this script enables kernel ASPM afterward

for dev in /sys/bus/pci/devices/*; do
    if [[ -f "$dev/vendor" && -f "$dev/device" ]]; then
        vendor=$(cat "$dev/vendor")
        device=$(cat "$dev/device")
        if [[ "$vendor" == "0x10ec" && "$device" == "0x8126" ]]; then
            echo 1 > "$dev/link/l1_aspm" 2>/dev/null || true
            echo 1 > "$dev/link/l1_1_aspm" 2>/dev/null || true
            echo 1 > "$dev/link/l1_2_aspm" 2>/dev/null || true
            echo 1 > "$dev/link/l0s_aspm" 2>/dev/null || true
        fi
    fi
done
