#!/bin/bash
# Unified build script for Sky1 Linux ISO and disk images
#
# Usage: ./scripts/build.sh <desktop> <loadout> <format> [track] [clean]
#
# Desktop choices: gnome, kde, xfce, none
# Package loadouts: minimal, desktop, server, developer
# Output formats: iso, image
# Kernel tracks: main, latest, rc, next (default: main)
#
# Examples:
#   ./scripts/build.sh gnome desktop iso              # GNOME desktop ISO (main kernel)
#   ./scripts/build.sh gnome desktop image             # GNOME desktop disk image
#   ./scripts/build.sh gnome desktop iso rc            # GNOME desktop ISO with RC kernel
#   ./scripts/build.sh kde minimal iso latest clean    # KDE minimal ISO, latest kernel, clean build

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BUILD_DIR"

# Build state tracking
. "$SCRIPT_DIR/build-state-lib.sh"

DESKTOPS="gnome kde xfce none"
LOADOUTS="minimal desktop server developer"
FORMATS="iso image"
TRACKS="main latest rc next"

DESKTOP="${1:-gnome}"
LOADOUT="${2:-desktop}"
FORMAT="${3:-iso}"

# 4th arg: track or "clean"
if [ "${4:-}" = "clean" ]; then
    TRACK="main"
    CLEAN="clean"
elif [ -n "${4:-}" ]; then
    TRACK="$4"
    CLEAN="${5:-}"
else
    TRACK="main"
    CLEAN=""
fi

DATE=$(date +%Y%m%d)
APT_URL="https://sky1-linux.github.io/apt"

usage() {
    echo "Sky1 Linux Build System"
    echo ""
    echo "Usage: $0 <desktop> <loadout> <format> [track] [clean]"
    echo ""
    echo "Desktop choices: $DESKTOPS"
    echo "Package loadouts: $LOADOUTS"
    echo "Output formats: $FORMATS"
    echo "Kernel tracks: $TRACKS (default: main)"
    echo ""
    echo "Options:"
    echo "  clean   - Run lb clean --purge before build"
    echo ""
    echo "Examples:"
    echo "  $0 gnome desktop iso              # GNOME desktop ISO (default)"
    echo "  $0 gnome desktop image             # GNOME desktop disk image"
    echo "  $0 gnome desktop iso rc            # RC kernel ISO"
    echo "  $0 gnome desktop iso latest clean  # Latest kernel, clean build"
    echo "  $0 none server image               # Headless server disk image"
    exit 1
}

# Validate parameters
echo "$DESKTOPS" | grep -qw "$DESKTOP" || { echo "Error: Unknown desktop '$DESKTOP'"; usage; }
echo "$LOADOUTS" | grep -qw "$LOADOUT" || { echo "Error: Unknown loadout '$LOADOUT'"; usage; }
echo "$FORMATS" | grep -qw "$FORMAT" || { echo "Error: Unknown format '$FORMAT'"; usage; }
echo "$TRACKS" | grep -qw "$TRACK" || { echo "Error: Unknown track '$TRACK'"; usage; }

DESKTOP_DIR="desktop-choice/$DESKTOP"
LOADOUT_DIR="package-loadouts/$LOADOUT"

[ -d "$DESKTOP_DIR" ] || { echo "Error: Desktop directory not found: $DESKTOP_DIR"; exit 1; }
[ -d "$LOADOUT_DIR" ] || { echo "Error: Loadout directory not found: $LOADOUT_DIR"; exit 1; }

# Single chroot per desktop — track controls which kernel is installed
CHROOT_DIR="desktop-choice/${DESKTOP}/chroot"

# Track-aware output naming and kernel suffix
if [ "$TRACK" = "main" ]; then
    OUTPUT_NAME="sky1-linux-${DESKTOP}-${LOADOUT}-${DATE}"
    KERNEL_SUFFIX=""
else
    OUTPUT_NAME="sky1-linux-${DESKTOP}-${LOADOUT}-${TRACK}-${DATE}"
    KERNEL_SUFFIX="-${TRACK}"
fi

echo "=== Building Sky1 Linux ==="
echo "Desktop: $DESKTOP"
echo "Loadout: $LOADOUT"
echo "Format:  $FORMAT"
echo "Track:   $TRACK"
echo "Chroot:  $CHROOT_DIR"
echo "Output:  $OUTPUT_NAME.$FORMAT"
echo ""

# Check for root when needed
if [ "$FORMAT" = "image" ] && [ "$(id -u)" -ne 0 ]; then
    echo "Error: Disk image builds require root. Run with sudo."
    exit 1
fi

# Generate sky1 apt sources list based on track
# main: just "main non-free-firmware"
# others: "main <track> non-free-firmware" (always include main for firmware/multimedia)
generate_sky1_sources() {
    if [ "$TRACK" = "main" ]; then
        echo "deb ${APT_URL} sid main non-free-firmware"
    else
        echo "deb ${APT_URL} sid main ${TRACK} non-free-firmware"
    fi
}

# Generate sky1 package list based on track
# Browsers, GStreamer, and ffmpeg are now in static package lists
# (desktop-common.list.chroot and base.list.chroot)
generate_sky1_packages() {
    cat << EOF
# Sky1 Linux packages (from Sky1 apt repo)
# Track: ${TRACK}

# Kernel (meta packages - always pulls latest for this track)
linux-image-sky1${KERNEL_SUFFIX}
linux-headers-sky1${KERNEL_SUFFIX}

# Firmware
sky1-firmware
EOF
}

# Write generated config files (used by lb build for fresh chroots)
echo "Generating sky1 apt sources for track: $TRACK"
generate_sky1_sources > "config/archives/sky1.list.chroot"

echo "Generating sky1 package list for track: $TRACK"
generate_sky1_packages > "config/package-lists/sky1.list.chroot"

# Ensure existing chroot has the right kernel for the requested track
# Updates apt sources inside the chroot and swaps kernel meta packages if needed
ensure_chroot_track() {
    local chroot_dir="$1"
    [ -d "$chroot_dir" ] || return 0

    local sources_file="$chroot_dir/etc/apt/sources.list.d/sky1.list"

    # Determine what meta packages this track needs
    local install_meta
    if [ "$TRACK" = "main" ]; then
        install_meta="linux-image-sky1 linux-headers-sky1"
    else
        install_meta="linux-image-sky1-${TRACK} linux-headers-sky1-${TRACK}"
    fi

    # Check if the right meta package is already installed (fast path)
    local check_pkg
    check_pkg=$(echo "$install_meta" | awk '{print $1}')
    if chroot "$chroot_dir" dpkg-query -W -f='${Status}' "$check_pkg" 2>/dev/null | grep -q "install ok installed"; then
        echo "Chroot already has $check_pkg installed"
        return 0
    fi

    echo "Switching chroot to track: $TRACK"

    # Update apt sources for the track
    cp /etc/resolv.conf "$chroot_dir/etc/resolv.conf"
    generate_sky1_sources > "$sources_file"

    # Ensure Sky1 GPG key is installed in the chroot
    if [ -f "config/archives/sky1.key.chroot" ]; then
        cp "config/archives/sky1.key.chroot" "$chroot_dir/etc/apt/trusted.gpg.d/sky1.asc"
    fi

    # Remove raspi-firmware hooks
    rm -f "$chroot_dir/etc/initramfs/post-update.d/z50-raspi-firmware"
    rm -f "$chroot_dir/etc/kernel/postinst.d/z50-raspi-firmware"
    rm -f "$chroot_dir/etc/kernel/postrm.d/z50-raspi-firmware"

    chroot "$chroot_dir" apt-get update -qq

    # Remove meta packages from other tracks
    local all_meta="linux-image-sky1 linux-headers-sky1 linux-sky1"
    all_meta="$all_meta linux-image-sky1-latest linux-headers-sky1-latest linux-sky1-latest"
    all_meta="$all_meta linux-image-sky1-rc linux-headers-sky1-rc linux-sky1-rc"
    all_meta="$all_meta linux-image-sky1-next linux-headers-sky1-next linux-sky1-next"

    local remove_pkgs=""
    for pkg in $all_meta; do
        echo "$install_meta" | grep -qw "$pkg" && continue
        if chroot "$chroot_dir" dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            remove_pkgs="$remove_pkgs $pkg"
        fi
    done

    if [ -n "$remove_pkgs" ]; then
        echo "  Removing old track packages:$remove_pkgs"
        chroot "$chroot_dir" apt-get remove -y $remove_pkgs
    fi

    echo "  Installing: $install_meta"
    chroot "$chroot_dir" apt-get install -y $install_meta
    chroot "$chroot_dir" apt-get autoremove -y -qq
    chroot "$chroot_dir" update-initramfs -u -k all
    echo "  Track switch complete"
}

# Set up desktop-specific chroot
# live-build expects 'chroot/' directory, so we symlink to the desktop-specific one
setup_chroot_symlink() {
    # Remove existing chroot symlink if present
    if [ -L "chroot" ]; then
        rm -f chroot
    fi

    # Handle orphan chroot directory from interrupted build
    if [ -d "chroot" ] && [ ! -L "chroot" ]; then
        if [ -d "$CHROOT_DIR" ]; then
            echo "Warning: Removing stale 'chroot' directory (real chroot at $CHROOT_DIR)"
            sudo rm -rf chroot
        else
            echo "Recovering orphaned 'chroot' directory to $CHROOT_DIR..."
            mkdir -p "$(dirname "$CHROOT_DIR")"
            mv chroot "$CHROOT_DIR"
        fi
    fi

    # Create symlink to desktop-specific chroot
    if [ -d "$CHROOT_DIR" ]; then
        ln -sf "$CHROOT_DIR" chroot
    fi
}

# Clean if requested
if [ "$CLEAN" = "clean" ]; then
    echo "Cleaning previous build for $DESKTOP (track: $TRACK)..."
    if [ -L "chroot" ]; then
        rm -f chroot
    elif [ -d "chroot" ]; then
        echo "  Removing stale chroot directory..."
        sudo rm -rf chroot
    fi
    if [ -d "$CHROOT_DIR" ]; then
        sudo rm -rf "$CHROOT_DIR"
    fi
    sudo lb clean --purge 2>/dev/null || true
fi

# Set up the chroot symlink
setup_chroot_symlink

# Validate chroot state — detect interrupted builds
validate_chroot_state "$CHROOT_DIR"
echo "Chroot: $CHROOT_ACTION ($CHROOT_ACTION_REASON)"

if [ "$CHROOT_ACTION" = "force_clean" ]; then
    echo ""
    echo "Incomplete or corrupt chroot detected. Forcing clean rebuild..."
    if [ -L "chroot" ]; then rm -f chroot; fi
    if [ -d "chroot" ]; then sudo rm -rf chroot; fi
    if [ -d "$CHROOT_DIR" ]; then sudo rm -rf "$CHROOT_DIR"; fi
    sudo lb clean --purge 2>/dev/null || true
elif [ "$CHROOT_ACTION" = "use_existing" ]; then
    check_chroot_freshness "$CHROOT_DIR"
fi

# Apply desktop choice (use copies, not symlinks, so they survive lb clean)
echo "Applying desktop choice: $DESKTOP..."
if [ -f "$DESKTOP_DIR/package-lists/desktop.list.chroot" ]; then
    cp -f "$DESKTOP_DIR/package-lists/desktop.list.chroot" "config/package-lists/desktop.list.chroot"
fi
if [ -f "$DESKTOP_DIR/hooks/live/0450-${DESKTOP}-config.hook.chroot" ]; then
    cp -f "$DESKTOP_DIR/hooks/live/0450-${DESKTOP}-config.hook.chroot" "config/hooks/live/0450-desktop-config.hook.chroot"
fi

# Filter package lists by @for tag
#
# Package lists in config/package-lists/ can have a "# @for: <target>" tag
# on the first line to control which builds include them:
#
#   # @for: desktop        — any GUI desktop (gnome, kde, xfce), not headless
#   # @for: <name>         — only that specific desktop
#   (no tag)               — always included
#
# Non-matching lists are temporarily renamed to .skip during the build.
filter_package_lists() {
    local desktop="$1"
    for f in config/package-lists/*.list.chroot; do
        [ -f "$f" ] || continue
        local tag
        tag=$(sed -n '1s/^# @for:[[:space:]]*//p' "$f" 2>/dev/null || true)
        [ -z "$tag" ] && continue  # no tag = always included

        local include=false
        if [ "$tag" = "$desktop" ]; then
            include=true
        elif [ "$tag" = "desktop" ] && [ "$desktop" != "none" ]; then
            include=true
        fi

        if ! $include; then
            echo "  Skipping $(basename "$f") (@for: $tag)"
            mv "$f" "${f}.skip"
        fi
    done
}

# Restore any .skip files after build
restore_package_lists() {
    for f in config/package-lists/*.list.chroot.skip; do
        [ -f "$f" ] && mv "$f" "${f%.skip}"
    done
}
trap restore_package_lists EXIT

filter_package_lists "$DESKTOP"

# Copy desktop-specific includes (overlay into config/includes.chroot)
if [ -d "$DESKTOP_DIR/includes.chroot" ]; then
    cp -a "$DESKTOP_DIR/includes.chroot/"* config/includes.chroot/ 2>/dev/null || true
fi

# Copy desktop-specific image overlay (for disk image builds)
if [ -d "$DESKTOP_DIR/includes.chroot.image" ]; then
    cp -a "$DESKTOP_DIR/includes.chroot.image/"* config/includes.chroot.image/ 2>/dev/null || true
fi

# Apply package loadout
echo "Applying package loadout: $LOADOUT..."
if [ -f "$LOADOUT_DIR/package-lists/loadout.list.chroot" ]; then
    cp -f "$LOADOUT_DIR/package-lists/loadout.list.chroot" "config/package-lists/loadout.list.chroot"
fi

# After lb build, move chroot to desktop-specific directory
finalize_chroot() {
    # If lb build created a 'chroot' directory (not symlink), move it
    if [ -d "chroot" ] && [ ! -L "chroot" ]; then
        echo "Moving chroot to $CHROOT_DIR..."
        mkdir -p "$(dirname "$CHROOT_DIR")"
        mv chroot "$CHROOT_DIR"
        ln -sf "$CHROOT_DIR" chroot
    fi
}

# Prepare chroot if it doesn't exist.
# Run lb bootstrap + lb chroot to create the chroot without generating an ISO.
# This is shared by both iso and image builds.
if [ ! -d "$CHROOT_DIR" ] && [ ! -d "chroot" ]; then
    echo ""
    echo "No chroot found for $DESKTOP. Building chroot..."

    sudo lb bootstrap 2>&1 | tee build.log

    # Record bootstrap completion (writes to 'chroot/' which lb just created)
    record_stage_complete "chroot" "BOOTSTRAP"
    write_build_state "chroot" "DESKTOP" "$DESKTOP"

    sudo lb chroot 2>&1 | tee -a build.log

    # Record chroot stage completion
    record_stage_complete "chroot" "CHROOT"
    write_build_state "chroot" "PKGLIST_HASH" "$(compute_pkglist_hash)"

    # Move chroot/ to desktop-specific path
    finalize_chroot
fi

# Ensure symlink is correct
if [ -d "$CHROOT_DIR" ] && [ ! -L "chroot" ]; then
    ln -sf "$CHROOT_DIR" chroot
fi

# Ensure chroot has the right kernel for the requested track
ensure_chroot_track "$CHROOT_DIR"
record_track_state "$CHROOT_DIR" "$TRACK"

# Build based on format
if [ "$FORMAT" = "iso" ]; then
    echo ""
    echo "Building ISO from chroot..."
    sudo lb binary 2>&1 | tee -a build.log

    # Find and rename output
    ISO_FILE=$(ls sky1-linux-*.iso 2>/dev/null | grep -v "$OUTPUT_NAME" | head -1)
    if [ -n "$ISO_FILE" ] && [ -f "$ISO_FILE" ]; then
        mv "$ISO_FILE" "$OUTPUT_NAME.iso"
        echo ""
        echo "=== Build Complete ==="
        ls -lh "$OUTPUT_NAME.iso"
    else
        echo ""
        echo "Warning: Expected ISO file not found"
        ls -lh sky1-linux*.iso 2>/dev/null || echo "No ISO files found"
    fi

elif [ "$FORMAT" = "image" ]; then
    echo ""
    echo "Building disk image..."
    sudo SKIP_COMPRESS="${SKIP_COMPRESS:-}" ./scripts/build-image.sh "$DESKTOP" "$LOADOUT" "$TRACK"
fi

echo ""
echo "Build finished at $(date)"
