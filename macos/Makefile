# Blocker macOS App — Swift + SPM
APP_NAME := Blocker
BUILD_DIR := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app

.PHONY: all build app run debug clean kill cpp launch

all: app

build:
	swift build -c release

# Builds .app to /Applications, ChromeExt to ~/Desktop/BlockerChromeExt
app: build
	./scripts/package-app.sh

# Opens the app from /Applications (bypasses Finder Gatekeeper)
launch: app
	open "/Applications/$(APP_NAME).app"

run: build
	swift run -c release

debug:
	swift run

kill:
	pkill -9 -f Blocker 2>/dev/null || true

clean:
	rm -rf $(BUILD_DIR)
	pkill -9 -f Blocker 2>/dev/null || true

# Legacy C++ daemon (kept as reference)
cpp:
	mkdir -p build && cd build && clang++ -std=c++17 -Wall -O2 \
		-framework Foundation -framework AppKit \
		../src/main.cpp ../src/settings_store.cpp -o blocker_cli
