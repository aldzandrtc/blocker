# Convenience targets for building the macOS app from the repository root.

.PHONY: all build app launch run debug clean kill cpp

all build app launch run debug clean kill cpp:
	$(MAKE) -C macos $@
