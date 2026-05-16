CXX = clang++
CXXFLAGS = -std=c++17 -Wall -O2
LDFLAGS = -framework Foundation -framework AppKit -framework CoreFoundation

SRC_DIR = src
BUILD_DIR = build
INSTALL_DIR = $(HOME)/.local/bin
PLIST_SRC = com.blocker.blockerd.plist
PLIST_DST = $(HOME)/Library/LaunchAgents/com.blocker.blockerd.plist

# CLI sources (minimal dependencies)
CLI_SRCS = $(SRC_DIR)/main.cpp $(SRC_DIR)/settings_store.cpp
CLI_OBJS = $(patsubst $(SRC_DIR)/%.cpp,$(BUILD_DIR)/%.o,$(CLI_SRCS))

# Daemon sources (full dependencies)
DAEMON_SRCS = $(SRC_DIR)/blockerd.cpp \
              $(SRC_DIR)/settings_store.cpp \
              $(SRC_DIR)/ai_client.cpp \
              $(SRC_DIR)/blocklist_judge.cpp \
              $(SRC_DIR)/problem_generator.cpp \
              $(SRC_DIR)/app_blocker.cpp \
              $(SRC_DIR)/workspace_bridge.mm
DAEMON_OBJS = $(patsubst $(SRC_DIR)/%.cpp,$(BUILD_DIR)/%.o,$(filter %.cpp,$(DAEMON_SRCS))) \
              $(patsubst $(SRC_DIR)/%.mm,$(BUILD_DIR)/%.o,$(filter %.mm,$(DAEMON_SRCS)))

.PHONY: all install clean

all: $(BUILD_DIR)/blocker $(BUILD_DIR)/blockerd

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# CLI
$(BUILD_DIR)/blocker: $(CLI_OBJS) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $(CLI_OBJS)

# Daemon
$(BUILD_DIR)/blockerd: $(DAEMON_OBJS) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $(DAEMON_OBJS) $(LDFLAGS)

# C++ compilation
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

# Objective-C++ compilation (with ARC)
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.mm | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -fobjc-arc -c -o $@ $<

install: all
	mkdir -p $(INSTALL_DIR)
	mkdir -p $(HOME)/.local/log
	mkdir -p $(HOME)/Library/LaunchAgents
	cp $(BUILD_DIR)/blocker $(INSTALL_DIR)/blocker
	cp $(BUILD_DIR)/blockerd $(INSTALL_DIR)/blockerd
	sed 's|$$HOME|$(HOME)|g' $(PLIST_SRC) > $(PLIST_DST)
	@echo "Installed blocker and blockerd to $(INSTALL_DIR)"
	@echo "LaunchAgent installed to $(PLIST_DST)"
	@echo "Run 'blocker setup' to configure, then 'blocker start'."

clean:
	rm -rf $(BUILD_DIR)
