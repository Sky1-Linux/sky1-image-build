#!/bin/bash
# Build GRUB EFI binary for Sky1 Linux Live ISO
# This creates a GRUB with embedded early config that looks in the EFI partition
#
# Tested with GRUB 2.14~rc1 built from source (~/grub-source)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$SCRIPT_DIR/config/includes.chroot/usr/share/sky1/grubaa64-sky1.efi"
GRUB_MODULES_DIR="/usr/local/lib/grub/arm64-efi"

# Check for grub-mkimage
if ! command -v grub-mkimage &> /dev/null; then
    echo "ERROR: grub-mkimage not found"
    echo "Install grub-common or build GRUB from source"
    exit 1
fi

# Check for modules directory
if [ ! -d "$GRUB_MODULES_DIR" ]; then
    echo "ERROR: GRUB modules not found at $GRUB_MODULES_DIR"
    exit 1
fi

# Create early config pointing to EFI partition in ISO
EARLY_CFG=$(mktemp)
cat > "$EARLY_CFG" << 'EOF'
set root=cd0,msdos2
set prefix=($root)/GRUB
configfile $prefix/grub.cfg
EOF

echo "Building GRUB EFI binary..."
echo "Modules dir: $GRUB_MODULES_DIR"
echo "Output: $OUTPUT"

grub-mkimage -O arm64-efi \
    -o "$OUTPUT" \
    -p /GRUB \
    -c "$EARLY_CFG" \
    -d "$GRUB_MODULES_DIR" \
    part_gpt part_msdos fat iso9660 loopback \
    linux fdt gzio normal configfile echo test ls cat boot

rm -f "$EARLY_CFG"

echo "Done: $(ls -lh "$OUTPUT")"
