#!/bin/bash
# Sky1 Linux first-boot configuration (Stage 1)
# Runs once before display manager on disk image installations
#
# This script handles:
# - Partition expansion to fill disk
# - Machine-id generation
# - SSH host key generation
# - Board detection and GRUB cleanup
# - Optional pre-configuration from EFI partition

set -e

FIRSTBOOT_MARKER="/var/lib/sky1/.firstboot-done"
FIRSTBOOT_CONFIG="/boot/efi/sky1-config.txt"
LOG="/var/log/sky1-firstboot.log"

exec >> "$LOG" 2>&1
echo "=== Sky1 First Boot: $(date) ==="

# Exit if already completed
[ -f "$FIRSTBOOT_MARKER" ] && exit 0

# Expand root partition to fill disk
expand_rootfs() {
    echo "Expanding root filesystem..."
    ROOT_PART=$(findmnt -n -o SOURCE /)
    ROOT_DISK=$(lsblk -no PKNAME "$ROOT_PART")
    ROOT_PARTNUM=$(cat /sys/class/block/$(basename "$ROOT_PART")/partition)

    # Expand partition
    if command -v growpart >/dev/null 2>&1; then
        growpart "/dev/$ROOT_DISK" "$ROOT_PARTNUM" || true
    else
        echo "Warning: growpart not available, skipping partition expansion"
    fi

    # Resize filesystem
    resize2fs "$ROOT_PART" || true
    echo "Root filesystem expanded: $(df -h / | tail -1)"
}

# Generate fresh machine-id (required for systemd/dbus)
generate_machine_id() {
    echo "Generating machine-id..."
    rm -f /etc/machine-id /var/lib/dbus/machine-id
    systemd-machine-id-setup
    if [ -f /var/lib/dbus ]; then
        ln -sf /etc/machine-id /var/lib/dbus/machine-id
    fi
    echo "Machine ID: $(cat /etc/machine-id)"
}

# Generate SSH host keys (security: must not be shared between installations)
generate_ssh_keys() {
    echo "Generating SSH host keys..."
    rm -f /etc/ssh/ssh_host_*

    if command -v dpkg-reconfigure >/dev/null 2>&1; then
        dpkg-reconfigure openssh-server 2>/dev/null || ssh-keygen -A
    else
        ssh-keygen -A
    fi

    echo "SSH host keys generated:"
    ls -la /etc/ssh/ssh_host_*.pub 2>/dev/null || true
}

# Detect board and clean up GRUB entries
detect_board_and_cleanup_grub() {
    echo "Detecting board type..."

    # Detect board from device tree
    if [ -f /sys/firmware/devicetree/base/compatible ]; then
        BOARD_COMPATIBLE=$(cat /sys/firmware/devicetree/base/compatible 2>/dev/null | tr '\0' '\n' | head -1)
    else
        echo "No device tree found, skipping board detection"
        return
    fi

    case "$BOARD_COMPATIBLE" in
        xunlong,orangepi-6-plus*)
            BOARD="orangepi-6-plus"
            KEEP_DTB="sky1-orangepi-6-plus.dtb"
            ;;
        *orion-o6n*|*radxa,orion-o6n*)
            BOARD="o6n"
            KEEP_DTB="sky1-orion-o6n.dtb"
            ;;
        *orion-o6*|*radxa,orion-o6*)
            BOARD="o6"
            KEEP_DTB="sky1-orion-o6.dtb"
            ;;
        *)
            echo "Unknown board: $BOARD_COMPATIBLE, keeping all GRUB entries"
            return
            ;;
    esac

    echo "Detected board: $BOARD (compatible: $BOARD_COMPATIBLE)"
    echo "Board DTB: $KEEP_DTB"

    # Set GRUB default to the detected board's entry (keep all entries for flexibility)
    GRUB_CFG="/boot/efi/GRUB/grub.cfg"
    if [ -f "$GRUB_CFG" ]; then
        echo "Setting GRUB default for $BOARD..."

        # Find the index of the first menuentry containing our DTB
        local idx=0
        local found=-1
        while IFS= read -r line; do
            if echo "$line" | grep -q "^menuentry"; then
                if echo "$line" | grep -q "$KEEP_DTB" || \
                   grep -A5 "^${line}$" "$GRUB_CFG" | grep -q "$KEEP_DTB"; then
                    found=$idx
                    break
                fi
                idx=$((idx + 1))
            fi
        done < "$GRUB_CFG"

        if [ "$found" -ge 0 ]; then
            # Update default and set a normal timeout (replaces timeout=-1 from build-image)
            sed -i "s/^set default=.*/set default=$found/" "$GRUB_CFG"
            sed -i "s/^set timeout=.*/set timeout=5/" "$GRUB_CFG"
            echo "GRUB default set to entry $found ($BOARD)"
        else
            echo "Warning: Could not find GRUB entry for $KEEP_DTB, setting default=0"
            sed -i "s/^set default=.*/set default=0/" "$GRUB_CFG"
            sed -i "s/^set timeout=.*/set timeout=5/" "$GRUB_CFG"
        fi
    else
        echo "GRUB config not found at $GRUB_CFG"
    fi
}

# Apply pre-configuration from EFI partition (if present)
apply_preconfig() {
    if [ ! -f "$FIRSTBOOT_CONFIG" ]; then
        echo "No pre-configuration file found at $FIRSTBOOT_CONFIG"
        return
    fi

    echo "Applying pre-configuration from $FIRSTBOOT_CONFIG..."

    # Source the config file safely
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        # Remove quotes from value
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "$key=$value"
    done < "$FIRSTBOOT_CONFIG"

    # Set hostname if provided
    if [ -n "$HOSTNAME" ]; then
        echo "Setting hostname to: $HOSTNAME"
        hostnamectl set-hostname "$HOSTNAME"
        echo "$HOSTNAME" > /etc/hostname
        sed -i "s/Sky1-Desktop/$HOSTNAME/g" /etc/hosts 2>/dev/null || true
    fi

    # Create user if provided (skip wizard later)
    if [ -n "$USERNAME" ]; then
        echo "Creating user: $USERNAME"
        useradd -m -G users,sudo,audio,video,netdev,plugdev,input,render \
                -s /bin/bash "$USERNAME" 2>/dev/null || true

        if [ -n "$PASSWORD_HASH" ]; then
            echo "$USERNAME:$PASSWORD_HASH" | chpasswd -e
        elif [ -n "$PASSWORD" ]; then
            echo "$USERNAME:$PASSWORD" | chpasswd
        fi

        # Update autologin to new user
        if [ -f /etc/gdm3/custom.conf ]; then
            sed -i "s/AutomaticLogin=sky1/AutomaticLogin=$USERNAME/" /etc/gdm3/custom.conf
        fi
        if [ -f /etc/sddm.conf.d/10-wayland.conf ]; then
            sed -i "s/User=sky1/User=$USERNAME/" /etc/sddm.conf.d/10-wayland.conf
        fi
        if [ -f /etc/lightdm/lightdm.conf.d/50-autologin.conf ]; then
            sed -i "s/autologin-user=sky1/autologin-user=$USERNAME/" /etc/lightdm/lightdm.conf.d/50-autologin.conf
        fi

        # Mark wizard as not needed
        mkdir -p /var/lib/sky1
        touch /var/lib/sky1/.wizard-done
        echo "User $USERNAME created, wizard will be skipped"
    fi

    # Secure delete config file (contains password)
    echo "Removing pre-configuration file..."
    if command -v shred >/dev/null 2>&1; then
        shred -u "$FIRSTBOOT_CONFIG" 2>/dev/null || rm -f "$FIRSTBOOT_CONFIG"
    else
        rm -f "$FIRSTBOOT_CONFIG"
    fi
}

# Main execution
echo "Starting first-boot configuration..."

expand_rootfs
generate_machine_id
generate_ssh_keys
detect_board_and_cleanup_grub
apply_preconfig

# Note: User creation is handled by plasma-setup.service which runs after this
# and before SDDM. plasma-setup provides a graphical wizard for account creation.

# Mark stage 1 complete
mkdir -p /var/lib/sky1
touch "$FIRSTBOOT_MARKER"

echo "=== First boot stage 1 complete ==="
