# Sky1 Linux Live Build

Live-build configuration for creating Sky1 Linux live/installer ISO images.

## Requirements

```bash
sudo apt install live-build
```

## Building

```bash
# Configure (first time only)
sudo make config

# Build ISO
sudo make build
```

The resulting ISO will be named `sky1-linux-arm64.hybrid.iso`.

## Structure

```
sky1-live-build/
├── auto/
│   ├── config          # lb config options
│   ├── build           # Build wrapper
│   └── clean           # Clean wrapper
├── config/
│   ├── package-lists/  # Packages to install
│   │   ├── desktop.list.chroot   # KDE + base system
│   │   ├── sky1.list.chroot      # Sky1 packages
│   │   └── installer.list.chroot # Calamares
│   ├── archives/       # APT repositories
│   │   ├── sky1.list.chroot      # Sky1 repo
│   │   └── sky1.key.chroot       # GPG key
│   ├── hooks/live/     # Build-time hooks
│   │   ├── 0100-sky1-dkms.hook.chroot    # Pre-build DKMS
│   │   └── 0200-sky1-cleanup.hook.chroot # Cleanup
│   ├── includes.chroot/  # Files for live filesystem
│   └── includes.binary/  # Files for ISO
└── Makefile
```

## Features

- ARM64 UEFI boot with GRUB
- KDE Plasma desktop
- Calamares graphical installer
- Pre-built DKMS modules (r8126, VPU)
- Hardware-accelerated video (Firefox, Chromium, FFmpeg)

## Customization

Edit files in `config/package-lists/` to add or remove packages.

## Boot from USB

```bash
# Write to USB drive (replace sdX)
sudo dd if=sky1-linux-arm64.hybrid.iso of=/dev/sdX bs=4M status=progress
sync
```
