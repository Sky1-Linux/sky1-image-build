# Sky1 Image Build

Disk image and live ISO build system for Sky1 Linux.

## Requirements

```bash
sudo apt install live-build
```

## Quick Start

```bash
# Build GNOME desktop ISO (default)
./scripts/build.sh gnome desktop iso

# Build GNOME desktop disk image
sudo ./scripts/build.sh gnome desktop image

# Headless server disk image
sudo ./scripts/build.sh none server image

# Clean build
./scripts/build.sh gnome desktop iso clean
```

## Build Options

```
./scripts/build.sh <desktop> <loadout> <format> [track] [clean]

Desktop:  gnome | kde | xfce | none
Loadout:  minimal | desktop | server | developer
Format:   iso | image
Track:    main | latest | rc | next  (default: main)
```

### Examples

```bash
# GNOME with full desktop apps (LTS kernel)
./scripts/build.sh gnome desktop iso

# KDE desktop disk image (latest kernel)
sudo ./scripts/build.sh kde desktop image latest

# XFCE developer workstation (RC kernel)
./scripts/build.sh xfce developer iso rc

# Headless server disk image
sudo ./scripts/build.sh none server image

# Headless server with latest kernel, skip compression
sudo SKIP_COMPRESS=1 ./scripts/build.sh none server image latest

# Clean rebuild from scratch
sudo ./scripts/build.sh gnome desktop image main clean
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `SKIP_COMPRESS=1` | Skip xz compression, output raw `.img` (faster for testing) |
| `FORCE_UPGRADE=1` | Upgrade chroot packages even if apt-listbugs reports serious bugs |

## Output Files

- **ISO**: `sky1-linux-<desktop>-<loadout>-YYYYMMDD.iso` — Bootable live/installer
- **Disk Image**: `sky1-linux-<desktop>-<loadout>-YYYYMMDD.img.xz` — Direct write to storage

### Writing Disk Images

```bash
# Write compressed image to storage device (replace sdX)
xzcat sky1-linux-gnome-desktop-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
sync

# Write uncompressed image (faster)
sudo dd if=sky1-linux-none-server-*.img of=/dev/sdX bs=4M status=progress
sync
```

## Server Provisioning

After flashing a headless server image, use `sky1-provision` to pre-configure the system
before first boot. See [docs/server-provisioning.md](docs/server-provisioning.md) for the full guide.

```bash
# Interactive provisioning
sudo PATH="$PATH" ./scripts/sky1-provision /dev/sdX

# Non-interactive (all options via CLI)
sudo PATH="$PATH" ./scripts/sky1-provision /dev/sdX \
    --hostname myserver \
    --user admin \
    --ssh-key "ssh-ed25519 AAAA..."
```

## Project Structure

```
sky1-image-build/
├── scripts/
│   ├── build.sh              # Main build script
│   ├── build-image.sh        # Disk image builder
│   ├── build-state-lib.sh    # Build state tracking library
│   ├── update-chroot.sh      # Update existing chroot packages
│   └── sky1-provision        # Pre-boot provisioning tool
├── desktop-choice/           # Desktop environment configs
│   ├── gnome/
│   │   ├── chroot/           # GNOME-specific chroot (isolated)
│   │   ├── package-lists/    # GNOME packages
│   │   ├── hooks/            # GNOME setup hook
│   │   ├── includes.chroot/  # Live-specific overlay
│   │   └── includes.chroot.image/  # Disk image overlay
│   ├── kde/
│   ├── xfce/
│   └── none/                 # Headless server (no GUI)
├── chroot -> desktop-choice/<active>/chroot  # Symlink
├── package-loadouts/         # Package sets
│   ├── minimal/
│   ├── desktop/
│   ├── server/
│   └── developer/
├── config/
│   ├── package-lists/        # Base + desktop-common packages
│   ├── archives/             # APT repos and keys
│   ├── hooks/live/           # Build-time hooks
│   ├── includes.chroot/      # Live filesystem overlay
│   └── includes.chroot.image/  # Disk image overlay
├── docs/
│   └── server-provisioning.md
└── auto/                     # live-build auto scripts
```

## Package Lists

Package lists support conditional inclusion via a `# @for:` tag on the first line:

| Tag | Included when |
|-----|---------------|
| (none) | Always — all builds |
| `# @for: desktop` | Any GUI desktop (gnome, kde, xfce), excluded from headless |
| `# @for: gnome` | Only that specific desktop |

Key lists:
- `base.list.chroot` — All builds (networking, firmware, CLI tools)
- `desktop-common.list.chroot` — GUI desktops only (audio, bluetooth, graphics, browsers)
- `sky1.list.chroot` — Generated per-build (kernel meta, firmware)

## Isolated Chroots

Each desktop environment has its own isolated chroot under `desktop-choice/<desktop>/chroot/`.

- First build creates the chroot via `lb bootstrap` + `lb chroot`
- Subsequent builds reuse the existing chroot (with freshness checks)
- A `.sky1-build-state` file inside each chroot tracks build stages and detects interrupted builds
- Use `clean` to force a fresh chroot: `./scripts/build.sh gnome desktop iso clean`

### Build State Tracking

The build system automatically detects and recovers from interrupted builds:

- **Interrupted bootstrap** → forces clean rebuild
- **Interrupted chroot stage** → forces clean rebuild
- **Complete chroot** → reuses, checks for package updates
- **Desktop mismatch** → forces clean rebuild

On reuse, the system runs `apt-get update`, checks for kernel upgrades, and queries
Debian BTS (via apt-listbugs) for release-critical bugs before upgrading packages.

## Headless Server ("none" desktop)

The `none` desktop builds a minimal server image with no GUI:

- **Default target**: `multi-user.target` (console only)
- **Included**: SSH, NetworkManager, Cockpit (web admin on :9090), Caddy (web server), ufw firewall, Podman
- **Firewall**: ufw enabled, allows SSH (22) and Cockpit (9090), drops everything else
- **Serial console**: Automatically detected from kernel `console=` parameter

## Architecture

The build system uses **separate overlays** for live ISO and disk image:

1. **Hook** creates neutral base config (no autologin, no skip markers)
2. **For live ISO**: `includes.chroot` overlay adds live settings (autologin, skip wizards)
3. **For disk image**: `includes.chroot.image` overlay replaces live settings (no autologin, run setup wizard)

## Kernel Tracks

| Track | Kernel | APT Component |
|-------|--------|---------------|
| main | LTS stable | `main` |
| latest | Latest stable | `latest` |
| rc | Release candidate | `rc` |
| next | Bleeding edge | `next` |

### Updating Chroot Kernel

```bash
# Update existing chroot to latest packages
sudo ./scripts/update-chroot.sh gnome

# Switch tracks
sudo ./scripts/update-chroot.sh gnome latest

# Wait for specific version (after apt push)
sudo ./scripts/update-chroot.sh gnome latest 6.19.2-1
```

## Clean Rebuilds

```bash
# Clean single desktop
./scripts/build.sh gnome desktop iso clean

# Manual deep clean (all artifacts)
sudo rm -rf chroot binary .build cache
sudo lb clean --purge
sudo rm -rf desktop-choice/gnome/chroot
```

## Customization

- **Add packages**: Edit `package-loadouts/<loadout>/package-lists/loadout.list.chroot`
- **Desktop tweaks**: Edit `desktop-choice/<desktop>/hooks/live/0450-*-config.hook.chroot`
- **APT pinning**: Edit `config/archives/*.pref.chroot`
