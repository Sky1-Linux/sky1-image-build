# Sky1 Linux Build System
# Supports both ISO and disk image builds with multiple desktop/loadout combinations
# Optional TRACK parameter: main (default), latest, rc, next

.PHONY: all iso image clean distclean help

DATE := $(shell date +%Y%m%d)
TRACK ?= main

# Default: GNOME desktop ISO
all: iso

# ===== ISO Targets =====
iso:
	./scripts/build.sh gnome desktop iso $(TRACK)

iso-gnome-desktop:
	./scripts/build.sh gnome desktop iso $(TRACK)

iso-gnome-minimal:
	./scripts/build.sh gnome minimal iso $(TRACK)

iso-kde-desktop:
	./scripts/build.sh kde desktop iso $(TRACK)

iso-kde-minimal:
	./scripts/build.sh kde minimal iso $(TRACK)

iso-xfce-desktop:
	./scripts/build.sh xfce desktop iso $(TRACK)

iso-xfce-minimal:
	./scripts/build.sh xfce minimal iso $(TRACK)

# ===== Disk Image Targets =====
image:
	sudo ./scripts/build.sh gnome desktop image $(TRACK)

image-gnome-desktop:
	sudo ./scripts/build.sh gnome desktop image $(TRACK)

image-gnome-minimal:
	sudo ./scripts/build.sh gnome minimal image $(TRACK)

image-kde-desktop:
	sudo ./scripts/build.sh kde desktop image $(TRACK)

image-none-server:
	sudo ./scripts/build.sh none server image $(TRACK)

image-gnome-developer:
	sudo ./scripts/build.sh gnome developer image $(TRACK)

# ===== Clean Targets =====
iso-clean:
	./scripts/build.sh gnome desktop iso $(TRACK) clean

image-clean:
	sudo ./scripts/build.sh gnome desktop image $(TRACK) clean

clean:
	sudo lb clean
	rm -f build.log

distclean:
	sudo lb clean --purge
	rm -f build.log
	rm -f sky1-linux-*.iso sky1-linux-*.img sky1-linux-*.img.xz

# ===== Help =====
help:
	@echo "Sky1 Linux Build System"
	@echo ""
	@echo "Usage: make <target> [TRACK=main|latest|rc|next]"
	@echo ""
	@echo "Kernel Tracks (default: main):"
	@echo "  main     - LTS kernel (production)"
	@echo "  latest   - Latest stable kernel"
	@echo "  rc       - Release candidate kernel"
	@echo "  next     - Bleeding-edge (Linus master)"
	@echo ""
	@echo "ISO Targets:"
	@echo "  iso                    - Build GNOME desktop ISO (default)"
	@echo "  iso-gnome-desktop      - Build GNOME desktop ISO"
	@echo "  iso-gnome-minimal      - Build GNOME minimal ISO"
	@echo "  iso-kde-desktop        - Build KDE desktop ISO"
	@echo "  iso-kde-minimal        - Build KDE minimal ISO"
	@echo "  iso-xfce-desktop       - Build XFCE desktop ISO"
	@echo "  iso-xfce-minimal       - Build XFCE minimal ISO"
	@echo ""
	@echo "Disk Image Targets:"
	@echo "  image                  - Build GNOME desktop disk image"
	@echo "  image-gnome-desktop    - Build GNOME desktop disk image"
	@echo "  image-gnome-minimal    - Build GNOME minimal disk image"
	@echo "  image-kde-desktop      - Build KDE desktop disk image"
	@echo "  image-none-server      - Build headless server disk image"
	@echo "  image-gnome-developer  - Build GNOME developer disk image"
	@echo ""
	@echo "Clean Targets:"
	@echo "  clean                  - Clean build artifacts (keep cache)"
	@echo "  distclean              - Full clean including cache and images"
	@echo ""
	@echo "Examples:"
	@echo "  make iso                        # Main kernel GNOME ISO"
	@echo "  make iso TRACK=rc               # RC kernel GNOME ISO"
	@echo "  make image TRACK=latest         # Latest kernel GNOME disk image"
	@echo "  make image-kde-desktop TRACK=rc # RC kernel KDE disk image"
	@echo ""
	@echo "Or use build.sh directly for more options:"
	@echo "  ./scripts/build.sh <desktop> <loadout> <format> [track] [clean]"
	@echo ""
	@echo "Desktop choices: gnome, kde, xfce, none"
	@echo "Package loadouts: minimal, desktop, server, developer"
	@echo "Output formats: iso, image"
