# Sky1 Linux Build System
# Supports both ISO and disk image builds with multiple desktop/loadout combinations

.PHONY: all iso image clean distclean help

DATE := $(shell date +%Y%m%d)

# Default: GNOME desktop ISO
all: iso

# ===== ISO Targets =====
iso:
	./scripts/build.sh gnome desktop iso

iso-gnome-desktop:
	./scripts/build.sh gnome desktop iso

iso-gnome-minimal:
	./scripts/build.sh gnome minimal iso

iso-kde-desktop:
	./scripts/build.sh kde desktop iso

iso-kde-minimal:
	./scripts/build.sh kde minimal iso

iso-xfce-desktop:
	./scripts/build.sh xfce desktop iso

iso-xfce-minimal:
	./scripts/build.sh xfce minimal iso

# ===== Disk Image Targets =====
image:
	sudo ./scripts/build.sh gnome desktop image

image-gnome-desktop:
	sudo ./scripts/build.sh gnome desktop image

image-gnome-minimal:
	sudo ./scripts/build.sh gnome minimal image

image-kde-desktop:
	sudo ./scripts/build.sh kde desktop image

image-none-server:
	sudo ./scripts/build.sh none server image

image-gnome-developer:
	sudo ./scripts/build.sh gnome developer image

# ===== Clean Targets =====
iso-clean:
	./scripts/build.sh gnome desktop iso clean

image-clean:
	sudo ./scripts/build.sh gnome desktop image clean

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
	@echo "Usage: make <target>"
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
	@echo "Or use build.sh directly for more options:"
	@echo "  ./scripts/build.sh <desktop> <loadout> <format> [clean]"
	@echo ""
	@echo "Desktop choices: gnome, kde, xfce, none"
	@echo "Package loadouts: minimal, desktop, server, developer"
	@echo "Output formats: iso, image"
