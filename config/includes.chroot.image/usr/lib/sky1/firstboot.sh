#!/bin/bash
# Sky1 Linux first-boot configuration (Stage 1)
# Runs once before display manager on disk image installations
#
# This script handles:
# - Partition expansion to fill disk
# - Machine-id generation
# - SSH host key generation
# - Board detection and GRUB cleanup
# - Pre-configuration from /boot/efi/sky1-config.txt:
#   HOSTNAME, USERNAME, PASSWORD[_HASH], SSH_AUTHORIZED_KEYS,
#   SSH_ENABLED, SSH_PASSWORD_AUTH, WIFI_SSID, WIFI_PSK or WIFI_PASSWORD,
#   WIFI_COUNTRY, TIMEZONE, LOCALE, KEYMAP
#
# Security: Use PASSWORD_HASH and WIFI_PSK to avoid storing plaintext
# secrets on the EFI partition. The config file is shredded after use.

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

# Parse sky1-config.txt into shell variables
# Handles KEY=VALUE, KEY="VALUE", and values containing '='
parse_config() {
    local file="$1"
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        # Split on first '=' only
        local key="${line%%=*}"
        local value="${line#*=}"
        key="${key// }"
        # Remove surrounding quotes
        value="${value#\"}" ; value="${value%\"}"
        value="${value#\'}" ; value="${value%\'}"
        export "$key=$value"
    done < "$file"
}

# Apply pre-configuration from EFI partition (if present)
apply_preconfig() {
    if [ ! -f "$FIRSTBOOT_CONFIG" ]; then
        echo "No pre-configuration file found at $FIRSTBOOT_CONFIG"
        return
    fi

    echo "Applying pre-configuration from $FIRSTBOOT_CONFIG..."
    parse_config "$FIRSTBOOT_CONFIG"

    # --- Hostname ---
    if [ -n "$HOSTNAME" ]; then
        echo "Setting hostname to: $HOSTNAME"
        hostnamectl set-hostname "$HOSTNAME"
        echo "$HOSTNAME" > /etc/hostname
        if grep -q "^127\.0\.1\.1" /etc/hosts 2>/dev/null; then
            sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
        else
            echo "127.0.1.1	$HOSTNAME" >> /etc/hosts
        fi
    fi

    # --- Timezone ---
    if [ -n "$TIMEZONE" ]; then
        echo "Setting timezone to: $TIMEZONE"
        timedatectl set-timezone "$TIMEZONE" 2>/dev/null || \
            ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    fi

    # --- Locale ---
    if [ -n "$LOCALE" ]; then
        echo "Setting locale to: $LOCALE"
        sed -i "s/^# *${LOCALE}/${LOCALE}/" /etc/locale.gen 2>/dev/null || true
        locale-gen 2>/dev/null || true
        localectl set-locale "LANG=$LOCALE" 2>/dev/null || \
            echo "LANG=$LOCALE" > /etc/default/locale
    fi

    # --- Keymap ---
    if [ -n "$KEYMAP" ]; then
        echo "Setting keymap to: $KEYMAP"
        localectl set-keymap "$KEYMAP" 2>/dev/null || true
    fi

    # --- User creation ---
    if [ -n "$USERNAME" ]; then
        echo "Creating user: $USERNAME"
        useradd -m -G users,sudo,audio,video,netdev,plugdev,input,render \
                -s /bin/bash "$USERNAME" 2>/dev/null || true

        if [ -n "$PASSWORD_HASH" ]; then
            usermod -p "$PASSWORD_HASH" "$USERNAME"
        elif [ -n "$PASSWORD" ]; then
            echo "$USERNAME:$PASSWORD" | chpasswd
        fi

        # Install SSH authorized keys
        if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
            local user_home
            user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
            if [ -n "$user_home" ]; then
                echo "Installing SSH authorized keys for $USERNAME"
                mkdir -p "$user_home/.ssh"
                # Decode escaped newlines and append
                printf '%b\n' "$SSH_AUTHORIZED_KEYS" > "$user_home/.ssh/authorized_keys"
                chmod 700 "$user_home/.ssh"
                chmod 600 "$user_home/.ssh/authorized_keys"
                chown -R "$USERNAME:$USERNAME" "$user_home/.ssh"
            fi
        fi

        # Update autologin to new user (desktop images)
        if [ -f /etc/gdm3/custom.conf ]; then
            sed -i "s/AutomaticLogin=sky1/AutomaticLogin=$USERNAME/" /etc/gdm3/custom.conf
        fi
        if [ -f /etc/sddm.conf.d/10-wayland.conf ]; then
            sed -i "s/User=sky1/User=$USERNAME/" /etc/sddm.conf.d/10-wayland.conf
        fi

        # Mark wizard as not needed
        mkdir -p /var/lib/sky1
        touch /var/lib/sky1/.wizard-done
        echo "User $USERNAME created"
    fi

    # --- SSH configuration ---
    if [ "$SSH_ENABLED" = "yes" ]; then
        echo "Enabling SSH server"
        systemctl enable ssh.service 2>/dev/null || true
    fi
    if [ "$SSH_PASSWORD_AUTH" = "no" ]; then
        echo "Disabling SSH password authentication"
        mkdir -p /etc/ssh/sshd_config.d
        echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/90-sky1-provision.conf
    fi

    # --- WiFi ---
    # Accepts WIFI_PSK (pre-computed 256-bit hex from wpa_passphrase) or
    # WIFI_PASSWORD (plaintext, converted to PSK here then discarded).
    # Pre-computed PSK is preferred — avoids storing plaintext on the EFI partition.
    if [ -n "$WIFI_SSID" ]; then
        echo "Configuring WiFi: $WIFI_SSID"

        # Derive PSK from plaintext password if no pre-computed PSK provided
        local psk="$WIFI_PSK"
        if [ -z "$psk" ] && [ -n "$WIFI_PASSWORD" ]; then
            if command -v wpa_passphrase >/dev/null 2>&1; then
                psk=$(wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" 2>/dev/null | \
                      grep -oP '^\s+psk=\K[0-9a-f]{64}')
            fi
            # Fall back to plaintext if wpa_passphrase unavailable
            [ -z "$psk" ] && psk="$WIFI_PASSWORD"
        fi

        local conn_file="/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection"
        mkdir -p /etc/NetworkManager/system-connections
        cat > "$conn_file" << NMEOF
[connection]
id=${WIFI_SSID}
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${psk}

[ipv4]
method=auto

[ipv6]
method=auto
NMEOF
        chmod 600 "$conn_file"

        # Set regulatory domain
        if [ -n "$WIFI_COUNTRY" ]; then
            echo "Setting WiFi regulatory domain: $WIFI_COUNTRY"
            iw reg set "$WIFI_COUNTRY" 2>/dev/null || true
            mkdir -p /etc/default
            echo "REGDOMAIN=$WIFI_COUNTRY" > /etc/default/crda
        fi
    fi

    # --- Secure delete config file (contains passwords/keys) ---
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
