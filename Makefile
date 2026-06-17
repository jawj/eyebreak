APP        := EyeBreak
BUNDLE     := $(APP).app
CONTENTS   := $(BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
BINARY     := $(MACOS_DIR)/$(APP)

SOURCES    := main.m AppDelegate.m BreakOverlayController.m
CC         := clang
CFLAGS     := -fobjc-arc -Wall -Wextra -O2 -mmacosx-version-min=13.0
FRAMEWORKS := -framework Cocoa -framework CoreGraphics -framework ServiceManagement

.PHONY: all run clean

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) AppDelegate.h BreakOverlayController.h Info.plist
	@mkdir -p $(MACOS_DIR)
	$(CC) $(CFLAGS) $(FRAMEWORKS) $(SOURCES) -o $(BINARY)
	@cp Info.plist $(CONTENTS)/Info.plist
	@echo "Built $(BUNDLE)"

run: all
	@open $(BUNDLE)

clean:
	@rm -rf $(BUNDLE)
	@echo "Cleaned"
