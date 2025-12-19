# Sky1 Linux Live Build Makefile

.PHONY: all config build clean distclean help

all: build

help:
	@echo "Sky1 Linux Live Build"
	@echo ""
	@echo "Targets:"
	@echo "  config    - Configure live-build (run once)"
	@echo "  build     - Build the ISO image"
	@echo "  clean     - Clean build artifacts (keep cache)"
	@echo "  distclean - Full clean including cache"
	@echo ""
	@echo "Usage:"
	@echo "  sudo make config"
	@echo "  sudo make build"

config:
	lb config

build:
	sudo lb build 2>&1 | tee build.log
	@echo ""
	@echo "Build complete. ISO image:"
	@ls -lh *.iso 2>/dev/null || echo "No ISO found - check build.log for errors"

clean:
	sudo lb clean
	rm -f build.log

distclean:
	sudo lb clean --purge
	rm -f build.log
	rm -rf cache/
