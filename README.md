# Sky1 Linux Live Build

Live-build configuration for creating Sky1 Linux live ISOs and installable disk images.

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

# Clean build
./scripts/build.sh gnome desktop iso clean
```

## Build Options

```
./scripts/build.sh <desktop> <loadout> <format> [clean]

Desktop:  gnome | kde | xfce | none
Loadout:  minimal | desktop | server | developer
Format:   iso | image
```

### Examples

```bash
# GNOME with full desktop apps
./scripts/build.sh gnome desktop iso

# KDE minimal (no extra apps)
./scripts/build.sh kde minimal iso

# XFCE developer workstation
./scripts/build.sh xfce developer iso

# Headless server disk image
sudo ./scripts/build.sh none server image
```

## Output Files

- **ISO**: `sky1-linux-<desktop>-<loadout>-YYYYMMDD.iso` - Bootable live/installer
- **Disk Image**: `sky1-linux-<desktop>-<loadout>-YYYYMMDD.img.xz` - Direct write to storage

### Writing Disk Images

```bash
# Write to storage device (replace sdX)
xzcat sky1-linux-gnome-desktop-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
sync
```

## Project Structure

```
sky1-live-build/
├── scripts/
│   ├── build.sh              # Main build script
│   └── build-image.sh        # Disk image builder
├── desktop-choice/           # Desktop environment configs
│   ├── gnome/
│   │   ├── package-lists/    # GNOME packages
│   │   ├── hooks/            # GNOME setup hook
│   │   ├── includes.chroot/  # Live-specific overlay
│   │   └── includes.chroot.image/  # Disk image overlay
│   ├── kde/
│   ├── xfce/
│   └── none/
├── package-loadouts/         # Package sets
│   ├── minimal/
│   ├── desktop/
│   ├── server/
│   └── developer/
├── config/
│   ├── package-lists/        # Base packages
│   ├── archives/             # APT repos and pinning
│   ├── hooks/live/           # Build-time hooks
│   ├── includes.chroot/      # Live filesystem overlay
│   └── includes.chroot.image/  # Disk image overlay
└── auto/                     # live-build auto scripts
```

## Architecture

The build system uses **separate overlays** for live ISO and disk image:

1. **Hook** creates neutral base config (no autologin, no skip markers)
2. **For live ISO**: `includes.chroot` overlay adds live settings (autologin, skip wizards)
3. **For disk image**: `includes.chroot.image` overlay replaces live settings (no autologin, run setup wizard)

This avoids having to undo live-specific settings when building disk images.

## Features

- ARM64 UEFI boot with patched GRUB
- Multiple desktop environments (GNOME, KDE, XFCE)
- Automatic first-boot configuration (partition expansion, user setup)
- Hardware-accelerated video (V4L2M2M, AV1)
- Pre-built DKMS modules (r8126, VPU)
- Mesa pinned for Panthor stability

## Customization

- **Add packages**: Edit `package-loadouts/<loadout>/package-lists/loadout.list.chroot`
- **Desktop tweaks**: Edit `desktop-choice/<desktop>/hooks/live/0450-*-config.hook.chroot`
- **APT pinning**: Edit `config/archives/*.pref.chroot`
