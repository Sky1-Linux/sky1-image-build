#!/bin/bash
# Build state tracking library for Sky1 image builds
#
# Manages a .sky1-build-state file inside each desktop's chroot to track
# build progress, detect interrupted builds, and validate chroot reuse.
#
# Usage: source this file from build.sh and update-chroot.sh

# Compute hash of active package list files (change detection)
compute_pkglist_hash() {
    cat config/package-lists/*.list.chroot 2>/dev/null | sort | md5sum | awk '{print $1}'
}

# Write a field to the build state file (atomic via temp+mv)
# Usage: write_build_state <chroot_dir> <field> <value>
write_build_state() {
    local chroot_dir="$1" field="$2" value="$3"
    local state_file="$chroot_dir/.sky1-build-state"
    local tmp_file="${state_file}.tmp"

    if [ ! -f "$state_file" ]; then
        printf '%s\n' "# Sky1 build state -- auto-generated, do not edit" \
                       "BUILD_STATE_VERSION=1" > "$tmp_file"
        mv "$tmp_file" "$state_file"
    fi

    if grep -q "^${field}=" "$state_file" 2>/dev/null; then
        sed "s|^${field}=.*|${field}=${value}|" "$state_file" > "$tmp_file"
        mv "$tmp_file" "$state_file"
    else
        echo "${field}=${value}" >> "$state_file"
    fi
}

# Read a field from the build state file
# Usage: value=$(read_build_state <chroot_dir> <field>) || true
read_build_state() {
    local chroot_dir="$1" field="$2"
    local state_file="$chroot_dir/.sky1-build-state"
    [ -f "$state_file" ] || return 1
    local value
    value=$(grep "^${field}=" "$state_file" 2>/dev/null | head -1 | cut -d= -f2-) || true
    [ -n "$value" ] || return 1
    echo "$value"
}

# Record that a build stage completed
# Usage: record_stage_complete <chroot_dir> <STAGE_NAME>
record_stage_complete() {
    local chroot_dir="$1" stage="$2"
    write_build_state "$chroot_dir" "STAGE_${stage}" "$(date --iso-8601=seconds)"
}

# Record track and kernel info in state file
# Usage: record_track_state <chroot_dir> <track>
record_track_state() {
    local chroot_dir="$1" track="$2"
    local meta_pkg kernel_version

    if [ "$track" = "main" ]; then
        meta_pkg="linux-image-sky1"
    else
        meta_pkg="linux-image-sky1-${track}"
    fi

    kernel_version=$(chroot "$chroot_dir" dpkg-query -W -f='${Version}' "$meta_pkg" 2>/dev/null) || true

    write_build_state "$chroot_dir" "TRACK" "$track"
    write_build_state "$chroot_dir" "KERNEL_META" "$meta_pkg"
    if [ -n "$kernel_version" ]; then
        write_build_state "$chroot_dir" "KERNEL_VERSION" "$kernel_version"
    fi
    record_stage_complete "$chroot_dir" "TRACK_SWITCH"
}

# Validate chroot and decide action: build_fresh | use_existing | force_clean
# Sets global: CHROOT_ACTION, CHROOT_ACTION_REASON
# Requires global: DESKTOP (current desktop being built)
validate_chroot_state() {
    local chroot_dir="$1"

    if [ ! -d "$chroot_dir" ]; then
        CHROOT_ACTION="build_fresh"
        CHROOT_ACTION_REASON="no chroot directory"
        return 0
    fi

    local state_file="$chroot_dir/.sky1-build-state"

    # No state file — try to adopt if chroot looks complete
    if [ ! -f "$state_file" ]; then
        if [ -x "$chroot_dir/usr/bin/apt-get" ] && [ -d "$chroot_dir/etc/apt" ]; then
            echo "  Adopting pre-existing chroot (no state file)"
            write_build_state "$chroot_dir" "DESKTOP" "$DESKTOP"
            write_build_state "$chroot_dir" "STAGE_BOOTSTRAP" "adopted"
            write_build_state "$chroot_dir" "STAGE_CHROOT" "adopted"
            write_build_state "$chroot_dir" "PKGLIST_HASH" "$(compute_pkglist_hash)"
            CHROOT_ACTION="use_existing"
            CHROOT_ACTION_REASON="adopted pre-existing chroot"
            return 0
        fi
        CHROOT_ACTION="force_clean"
        CHROOT_ACTION_REASON="no state file and chroot looks incomplete"
        return 0
    fi

    # Check version compatibility
    local state_version
    state_version=$(read_build_state "$chroot_dir" "BUILD_STATE_VERSION") || true
    if [ "${state_version:-0}" -gt 1 ]; then
        CHROOT_ACTION="force_clean"
        CHROOT_ACTION_REASON="state version $state_version newer than supported (1)"
        return 0
    fi

    # Check desktop matches
    local saved_desktop
    saved_desktop=$(read_build_state "$chroot_dir" "DESKTOP") || true
    if [ -n "$saved_desktop" ] && [ "$saved_desktop" != "$DESKTOP" ]; then
        CHROOT_ACTION="force_clean"
        CHROOT_ACTION_REASON="built for '$saved_desktop', not '$DESKTOP'"
        return 0
    fi

    # Check stage completeness
    local stage_bootstrap stage_chroot
    stage_bootstrap=$(read_build_state "$chroot_dir" "STAGE_BOOTSTRAP") || true
    stage_chroot=$(read_build_state "$chroot_dir" "STAGE_CHROOT") || true

    if [ -z "$stage_bootstrap" ]; then
        CHROOT_ACTION="force_clean"
        CHROOT_ACTION_REASON="bootstrap never completed"
        return 0
    fi

    if [ -z "$stage_chroot" ]; then
        CHROOT_ACTION="force_clean"
        CHROOT_ACTION_REASON="chroot stage interrupted (bootstrap done at $stage_bootstrap)"
        return 0
    fi

    # Both stages complete — warn if package lists changed
    local saved_hash current_hash
    saved_hash=$(read_build_state "$chroot_dir" "PKGLIST_HASH") || true
    current_hash=$(compute_pkglist_hash)
    if [ -n "$saved_hash" ] && [ "$saved_hash" != "$current_hash" ]; then
        echo "  Warning: Package lists changed since chroot was built"
        echo "    Saved:   $saved_hash"
        echo "    Current: $current_hash"
        echo "    (Pass 'clean' to rebuild with updated lists)"
    fi

    CHROOT_ACTION="use_existing"
    CHROOT_ACTION_REASON="complete (bootstrap: $stage_bootstrap, chroot: $stage_chroot)"
}

# Check chroot freshness — apt staleness and kernel upgrades
# Call after validate_chroot_state when CHROOT_ACTION=use_existing
# Requires globals: TRACK, CHROOT_DIR
# If apt is stale (>24h), runs apt-get update and checks for kernel upgrades.
# Upgrades the chroot in-place if packages are outdated.
check_chroot_freshness() {
    local chroot_dir="$1"
    [ -d "$chroot_dir" ] || return 0

    local meta_pkg
    if [ "$TRACK" = "main" ]; then
        meta_pkg="linux-image-sky1"
    else
        meta_pkg="linux-image-sky1-${TRACK}"
    fi

    # Ensure DNS works for all apt operations
    cp /etc/resolv.conf "$chroot_dir/etc/resolv.conf" 2>/dev/null || true

    # Mount /proc so apt-listbugs can work (needs ProcTable)
    local proc_mounted=false
    if [ ! -d "$chroot_dir/proc/1" ]; then
        mount -t proc proc "$chroot_dir/proc"
        proc_mounted=true
    fi

    # Always refresh apt lists — ensures we see latest packages
    local apt_lists="$chroot_dir/var/lib/apt/lists"
    if [ -d "$apt_lists" ]; then
        local age_seconds
        age_seconds=$(( $(date +%s) - $(stat -c %Y "$apt_lists" 2>/dev/null || echo 0) ))
        local age_hours=$(( age_seconds / 3600 ))
        if [ "$age_hours" -ge 1 ]; then
            echo "  Apt lists are ${age_hours}h old — refreshing..."
        fi
    fi
    chroot "$chroot_dir" apt-get update -qq

    # Check if kernel is at latest available version
    local installed candidate
    installed=$(chroot "$chroot_dir" dpkg-query -W -f='${Version}' "$meta_pkg" 2>/dev/null) || true
    candidate=$(chroot "$chroot_dir" apt-cache policy "$meta_pkg" 2>/dev/null \
        | grep 'Candidate:' | awk '{print $2}') || true

    if [ -n "$installed" ] && [ -n "$candidate" ] && [ "$installed" != "$candidate" ]; then
        echo "  Kernel upgrade available: $meta_pkg $installed -> $candidate"
        echo "  Upgrading kernel..."
        chroot "$chroot_dir" apt-get install -y $meta_pkg 2>&1 | tail -3
        chroot "$chroot_dir" update-initramfs -u -k all
        echo "  Kernel upgraded"
    elif [ -n "$installed" ]; then
        echo "  Kernel: $meta_pkg $installed (up to date)"
    fi

    # Run apt-listbugs report on upgradeable packages before upgrading
    local upgradeable_pkgs
    upgradeable_pkgs=$(chroot "$chroot_dir" apt list --upgradable 2>/dev/null \
        | grep upgradable | cut -d/ -f1) || true
    local upgradeable_count
    upgradeable_count=$(echo "$upgradeable_pkgs" | grep -c . 2>/dev/null) || true

    if [ "${upgradeable_count:-0}" -gt 0 ]; then
        # Check for known serious bugs before upgrading
        local has_serious_bugs=false
        if [ -x "$chroot_dir/usr/bin/apt-listbugs" ]; then
            echo "  Checking Debian BTS for bugs in $upgradeable_count upgradeable package(s)..."
            local bug_report
            bug_report=$(chroot "$chroot_dir" apt-listbugs -s critical,grave,serious list \
                $upgradeable_pkgs 2>/dev/null) || true
            if [ -n "$bug_report" ] && ! echo "$bug_report" | grep -q "no bugs found"; then
                has_serious_bugs=true
                echo ""
                echo "  *** SERIOUS BUGS FOUND IN UPGRADEABLE PACKAGES ***"
                echo ""
                echo "$bug_report" | sed 's/^/  /'
                echo ""
            else
                echo "  No critical/grave/serious bugs found"
            fi
        fi

        if $has_serious_bugs && [ "${FORCE_UPGRADE:-}" != "1" ]; then
            echo "  SKIPPING upgrade — review bugs above before proceeding."
            echo "  To upgrade anyway: FORCE_UPGRADE=1 ./scripts/build.sh ..."
            echo "  Building image from existing (non-upgraded) chroot."
            echo ""
        else
            if $has_serious_bugs; then
                echo "  FORCE_UPGRADE=1 set — upgrading despite known bugs."
            fi
            echo "  $upgradeable_count package(s) upgradeable — running dist-upgrade..."
            chroot "$chroot_dir" apt-get -o APT::ListBugs::Force=yes dist-upgrade -y 2>&1 | tail -5
            chroot "$chroot_dir" apt-get autoremove -y -qq
        fi
    fi

    # Unmount /proc
    if $proc_mounted; then
        umount "$chroot_dir/proc" 2>/dev/null || true
    fi
}
