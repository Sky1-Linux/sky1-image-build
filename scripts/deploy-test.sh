#!/bin/bash
# Deploy Sky1 Linux ISO to test partition
# Usage: ./scripts/deploy-test.sh [iso-file]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# Configuration
TEST_PARTITION="${TEST_PARTITION:-/dev/nvme0n1p4}"
EFI_MOUNT="${EFI_MOUNT:-/boot/efi}"

# Find ISO
ISO_FILE="${1:-$(ls -t sky1-linux-*.iso 2>/dev/null | head -1)}"
if [ -z "$ISO_FILE" ] || [ ! -f "$ISO_FILE" ]; then
    echo "ERROR: No ISO file found"
    echo "Usage: $0 [iso-file]"
    echo ""
    echo "Available ISOs:"
    ls -lh sky1-linux-*.iso 2>/dev/null || echo "  (none)"
    exit 1
fi

echo "=== Sky1 Linux Test Deployment ==="
echo "ISO:       $ISO_FILE ($(du -h "$ISO_FILE" | cut -f1))"
echo "Partition: $TEST_PARTITION"
echo "EFI:       $EFI_MOUNT"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges."
    echo "Run: sudo $0 $*"
    exit 1
fi

# Check partition exists
if [ ! -b "$TEST_PARTITION" ]; then
    echo "ERROR: Partition $TEST_PARTITION not found"
    exit 1
fi

# Unmount if mounted
MOUNT_POINT=$(findmnt -n -o TARGET "$TEST_PARTITION" 2>/dev/null || true)
if [ -n "$MOUNT_POINT" ]; then
    echo "Unmounting $TEST_PARTITION from $MOUNT_POINT..."
    umount -l "$TEST_PARTITION" || true
    sleep 1
fi

# Write ISO to partition
echo ""
echo "Writing ISO to $TEST_PARTITION..."
dd if="$ISO_FILE" of="$TEST_PARTITION" bs=4M status=progress conv=fsync

# Copy boot files to EFI partition
echo ""
echo "Copying boot files to EFI partition..."

if [ ! -d "$EFI_MOUNT" ]; then
    echo "ERROR: EFI mount point $EFI_MOUNT not found"
    exit 1
fi

# Extract boot files from binary/ if available, else mount ISO
if [ -f "binary/live/vmlinuz" ]; then
    cp binary/live/vmlinuz "$EFI_MOUNT/LIVE-VMLINUZ"
    cp binary/live/initrd.img "$EFI_MOUNT/LIVE-INITRD"

    # Find DTB
    DTB_FILE=$(find binary/boot/dtbs -name "sky1-orion-o6.dtb" 2>/dev/null | head -1)
    if [ -n "$DTB_FILE" ]; then
        cp "$DTB_FILE" "$EFI_MOUNT/LIVE-DTB.dtb"
    fi
else
    # Mount ISO temporarily
    TMPDIR=$(mktemp -d)
    mount -o loop,ro "$ISO_FILE" "$TMPDIR"

    cp "$TMPDIR/live/vmlinuz" "$EFI_MOUNT/LIVE-VMLINUZ"
    cp "$TMPDIR/live/initrd.img" "$EFI_MOUNT/LIVE-INITRD"

    DTB_FILE=$(find "$TMPDIR/boot/dtbs" -name "sky1-orion-o6.dtb" 2>/dev/null | head -1)
    if [ -n "$DTB_FILE" ]; then
        cp "$DTB_FILE" "$EFI_MOUNT/LIVE-DTB.dtb"
    fi

    umount "$TMPDIR"
    rmdir "$TMPDIR"
fi

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "EFI boot files:"
ls -lh "$EFI_MOUNT/LIVE-"* 2>/dev/null || echo "  (not found)"
echo ""
echo "Reboot and select 'Sky1 Linux Live' from GRUB to test."
