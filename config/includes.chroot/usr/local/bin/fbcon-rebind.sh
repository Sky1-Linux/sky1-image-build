#!/bin/bash
# /usr/local/bin/fbcon-rebind.sh
# Switch to VT2 (on fb1) when linlondp DRM framebuffer becomes available
#
# With fbcon=map:01, VT1 is on fb0 (EFI), VT2 is on fb1 (linlondp)
# When DRM loads, fb0 becomes inactive, so we switch to VT2 to keep
# boot log visible on the linlondp display.

exec &>/dev/null  # Silence output for udev

# Small delay for display to initialize
sleep 0.2

# Switch to VT2 (which is mapped to fb1/linlondp)
/usr/bin/chvt 2

logger -t "fbcon-rebind" "Switched to VT2 for linlondp display"
