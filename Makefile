APP        := EyeBreak
BUNDLE     := $(APP).app
CONTENTS   := $(BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
RES_DIR    := $(CONTENTS)/Resources
BINARY     := $(MACOS_DIR)/$(APP)

SOURCES    := main.m AppDelegate.m BreakOverlayController.m
CC         := clang
CFLAGS     := -fobjc-arc -Wall -Wextra -O2 -mmacosx-version-min=13.0
FRAMEWORKS := -framework Cocoa -framework CoreGraphics -framework ServiceManagement -framework CoreMediaIO

.PHONY: all run clean

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) AppDelegate.h BreakOverlayController.h Info.plist AppIcon.icns
	@mkdir -p $(MACOS_DIR) $(RES_DIR)
	$(CC) $(CFLAGS) $(FRAMEWORKS) $(SOURCES) -o $(BINARY)
	@cp Info.plist $(CONTENTS)/Info.plist
	@cp AppIcon.icns $(RES_DIR)/AppIcon.icns
	@echo "Built $(BUNDLE)"

run: all
	@open $(BUNDLE)

clean:
	@rm -rf $(BUNDLE)
	@echo "Cleaned"
