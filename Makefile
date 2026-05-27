# MarkdownQL — macOS QuickLook Preview Extension for Markdown files
# Uses the modern App Extension approach (macOS 12+), builds with CLT only.

APP_NAME    = MarkdownQL
EXT_NAME    = MarkdownQLPreview
APP_BUNDLE  = $(APP_NAME).app
EXT_BUNDLE  = $(EXT_NAME).appex
BUILD_DIR   = build
APP_PATH    = $(BUILD_DIR)/$(APP_BUNDLE)
EXT_PATH    = $(APP_PATH)/Contents/PlugIns/$(EXT_BUNDLE)
INSTALL_DIR = $(HOME)/Applications

SDK     = $(shell xcrun --sdk macosx --show-sdk-path)
TARGET  = arm64-apple-macosx12.0
SWIFT   = swiftc
SWIFT_FLAGS = -sdk $(SDK) -target $(TARGET)

MARKED_URL = https://cdn.jsdelivr.net/npm/marked/marked.min.js
HLJS_URL   = https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js
HLJS_YAML  = https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/yaml.min.js

.PHONY: all deps build install uninstall test clean

all: build

deps: Resources/marked.min.js Resources/highlight.min.js

Resources/marked.min.js:
	curl -fsSL "$(MARKED_URL)" -o Resources/marked.min.js
	@echo "Downloaded marked.min.js ($$(wc -c < Resources/marked.min.js | tr -d ' ') bytes)"

Resources/highlight.min.js:
	curl -fsSL "$(HLJS_URL)" -o Resources/highlight.min.js
	curl -fsSL "$(HLJS_YAML)" >> Resources/highlight.min.js
	@echo "Downloaded highlight.min.js ($$(wc -c < Resources/highlight.min.js | tr -d ' ') bytes)"

build: deps
	# --- Extension binary ---
	@mkdir -p $(EXT_PATH)/Contents/MacOS
	@mkdir -p $(EXT_PATH)/Contents/Resources
	$(SWIFT) $(SWIFT_FLAGS) \
	  -framework QuickLookUI \
	  -framework Foundation \
	  -framework Cocoa \
	  -framework WebKit \
	  -framework JavaScriptCore \
	  -module-name $(EXT_NAME) \
	  -Xlinker -e -Xlinker _NSExtensionMain \
	  AppSources/ext/PreviewProvider.swift \
	  -o $(EXT_PATH)/Contents/MacOS/$(EXT_NAME)
	cp AppSources/ext/Info.plist $(EXT_PATH)/Contents/Info.plist
	cp Resources/marked.min.js      $(EXT_PATH)/Contents/Resources/
	cp Resources/highlight.min.js   $(EXT_PATH)/Contents/Resources/
	cp Resources/preview.css        $(EXT_PATH)/Contents/Resources/

	# --- Host app binary ---
	@mkdir -p $(APP_PATH)/Contents/MacOS
	@mkdir -p $(APP_PATH)/Contents/Resources
	$(SWIFT) $(SWIFT_FLAGS) \
	  -framework Cocoa \
	  -framework WebKit \
	  -framework JavaScriptCore \
	  AppSources/app/AppMain.swift \
	  -o $(APP_PATH)/Contents/MacOS/$(APP_NAME)
	cp AppSources/app/Info.plist  $(APP_PATH)/Contents/Info.plist
	cp Resources/marked.min.js       $(APP_PATH)/Contents/Resources/
	cp Resources/highlight.min.js    $(APP_PATH)/Contents/Resources/
	cp Resources/preview.css         $(APP_PATH)/Contents/Resources/

	# --- Sign (ad-hoc with entitlements) ---
	codesign --force --sign - \
	  --entitlements AppSources/ext/ext.entitlements \
	  $(EXT_PATH)
	codesign --force --sign - \
	  --entitlements AppSources/app/app.entitlements \
	  $(APP_PATH)

	@echo ""
	@echo "Built: $(APP_PATH)"
	@file $(EXT_PATH)/Contents/MacOS/$(EXT_NAME)

install: build
	@mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_BUNDLE)"
	cp -r $(APP_PATH) "$(INSTALL_DIR)/$(APP_BUNDLE)"
	@echo ""
	@echo "Installed: $(INSTALL_DIR)/$(APP_BUNDLE)"
	@echo ""
	@echo "Next steps:"
	@echo "  1) Open Finder → go to ~/Applications"
	@echo "  2) Right-click MarkdownQL.app → Open"
	@echo "  3) Click 'Open Anyway' in the security dialog"
	@echo "  4) The app will show a confirmation window — close it"
	@echo "  5) Press Space on any .md file in Finder"

uninstall:
	rm -rf "$(INSTALL_DIR)/$(APP_BUNDLE)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	  -u "$(INSTALL_DIR)/$(APP_BUNDLE)" 2>/dev/null || true
	@echo "Uninstalled $(APP_BUNDLE)"

test: build
	qlmanage -p -g $(EXT_PATH) -c net.daringfireball.markdown test/sample.md

open-app:
	open "$(INSTALL_DIR)/$(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleaned build directory"
