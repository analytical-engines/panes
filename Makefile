.PHONY: build run clean release app test dmg help

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
	@echo "  make dmg        - Create DMG for distribution"
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
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@echo "✅ $(APP_BUNDLE) created successfully!"
	@echo "Run with: open $(APP_BUNDLE)"

test:
	swift test

dmg: app
	@echo "Creating DMG..."
	@rm -f $(APP_NAME).dmg
	@hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(APP_BUNDLE) \
		-ov -format UDZO \
		$(APP_NAME).dmg
	@echo "Done: $(APP_NAME).dmg"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
	rm -rf $(BUILD_DIR)
	rm -f $(APP_NAME).dmg
