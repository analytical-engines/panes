.PHONY: build run clean release app test help

APP_NAME = Panes
APP_BUNDLE = $(APP_NAME).app
BUILD_DIR = .build
RELEASE_BUILD_DIR = $(BUILD_DIR)/release
DEBUG_BUILD_DIR = $(BUILD_DIR)/debug

help:
	@echo "Panes Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make build      - Debug build"
	@echo "  make run        - Build and run (debug)"
	@echo "  make release    - Release build"
	@echo "  make app        - Create .app bundle (release)"
	@echo "  make test       - Run tests"
	@echo "  make clean      - Clean build artifacts"
	@echo "  make help       - Show this help"

build:
	swift build

run:
	swift run

release:
	swift build -c release

app: release
	@echo "Creating .app bundle..."
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(RELEASE_BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp Info.plist $(APP_BUNDLE)/Contents/ 2>/dev/null || echo "Warning: Info.plist not found, creating minimal version"
	@if [ ! -f $(APP_BUNDLE)/Contents/Info.plist ]; then \
		echo '<?xml version="1.0" encoding="UTF-8"?>' > $(APP_BUNDLE)/Contents/Info.plist; \
		echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '<plist version="1.0">' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '<dict>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <key>CFBundleExecutable</key>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <string>$(APP_NAME)</string>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <key>CFBundleIdentifier</key>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <string>com.example.panes</string>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <key>CFBundleName</key>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <string>$(APP_NAME)</string>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <key>CFBundleVersion</key>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <string>1.0</string>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <key>CFBundleShortVersionString</key>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <string>1.0</string>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <key>LSMinimumSystemVersion</key>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <string>15.0</string>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <key>NSHighResolutionCapable</key>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '    <true/>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '</dict>' >> $(APP_BUNDLE)/Contents/Info.plist; \
		echo '</plist>' >> $(APP_BUNDLE)/Contents/Info.plist; \
	fi
	@echo "Done: $(APP_BUNDLE)"
	@echo "Run with: open $(APP_BUNDLE)"

test:
	swift test

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
	rm -rf $(BUILD_DIR)
