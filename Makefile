# Cappuccino — macOS menubar app. No Xcode: SwiftPM builds the binary, this Makefile
# assembles the .app bundle and codesigns. Standard: ~/.kilo/skills/macos-cli-dev.
APP_NAME     := Cappuccino
BUNDLE_ID    := tw.zyx.cappuccino
BIN_PATH     := .build/release/$(APP_NAME)
APP_BUNDLE   := build/$(APP_NAME).app
CONTENTS     := $(APP_BUNDLE)/Contents
ENTITLEMENTS := Resources/$(APP_NAME).entitlements
VERSION      := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG          := build/$(APP_NAME)-$(VERSION).dmg

# 開發態簽名 —— 預設 ad-hoc；要 TCC 權限跨 rebuild 不失效，就在 Makefile.local（gitignored）設 Apple Development cert hash。
SIGN_ID ?= -
# 分發 —— Developer ID Application cert 全名 + notarytool keychain profile。本機放 Makefile.local；CI 走 secret override。
DEV_ID_APP ?=
NOTARY_PROFILE ?= cappuccino-notary
-include Makefile.local

.PHONY: all build bundle run rebuild install icon dmg release publish verify logs clean

all: bundle

# 純 SwiftPM build —— Command Line Tools 即可，不需完整 Xcode。
# 要 universal（arm64+x86_64）需完整 Xcode：swift build -c release --arch arm64 --arch x86_64。
build:
	swift build -c release

# 組 .app + 簽名（開發態）。
bundle: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	@cp $(BIN_PATH) $(CONTENTS)/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	@cp Resources/MenubarIcon.png $(CONTENTS)/Resources/MenubarIcon.png
	@cp scripts/grant.sh $(CONTENTS)/Resources/ && chmod +x $(CONTENTS)/Resources/grant.sh
	@cp scripts/cappuccino.sudoers.template $(CONTENTS)/Resources/
	@codesign --force --options runtime --entitlements $(ENTITLEMENTS) --sign $(SIGN_ID) $(APP_BUNDLE)
	@echo "[OK] $(APP_BUNDLE) signed with $(SIGN_ID)"

run: bundle
	open $(APP_BUNDLE)

rebuild: clean bundle

# 安裝到 /Applications（SMAppService 開機自啟 + 穩定 TCC 都需要 app 在這裡）。
install: bundle
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "[OK] installed to /Applications/$(APP_NAME).app"

# 重生 app icon：zyx 品牌標 → 深色 squircle 漸層 → Resources/AppIcon.icns（需 Pillow，經 uv 取）。
icon:
	@./scripts/generate-icon.py
	@echo "[OK] Resources/AppIcon.icns regenerated"

dmg: bundle
	@bash scripts/make-dmg.sh $(APP_BUNDLE) $(DMG)

# 完整分發：Developer ID 簽 + notarize + staple + DMG。本機前置見 Makefile.local.example；CI 見 .github/workflows/release.yml。
release: build
	@test -n "$(DEV_ID_APP)" || { echo "✗ 需設 DEV_ID_APP（Makefile.local 或 make release DEV_ID_APP=...）"; exit 1; }
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	@cp $(BIN_PATH) $(CONTENTS)/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns
	@cp Resources/MenubarIcon.png $(CONTENTS)/Resources/MenubarIcon.png
	@cp scripts/grant.sh $(CONTENTS)/Resources/ && chmod +x $(CONTENTS)/Resources/grant.sh
	@cp scripts/cappuccino.sudoers.template $(CONTENTS)/Resources/
	@codesign --force --options runtime --timestamp --entitlements $(ENTITLEMENTS) --sign "$(DEV_ID_APP)" $(APP_BUNDLE)
	@codesign --verify --strict --verbose=2 $(APP_BUNDLE)
	@echo "→ notarizing app（首次數分鐘）…"
	@ditto -c -k --keepParent $(APP_BUNDLE) build/$(APP_NAME)-notarize.zip
	@xcrun notarytool submit build/$(APP_NAME)-notarize.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple $(APP_BUNDLE)   # ticket 釘進 app，離線也過 Gatekeeper
	@rm -f build/$(APP_NAME)-notarize.zip
	@bash scripts/make-dmg.sh $(APP_BUNDLE) $(DMG)
	@echo "→ notarizing dmg…"
	@xcrun notarytool submit $(DMG) --keychain-profile "$(NOTARY_PROFILE)" --wait   # DMG 也要 notarize 才能 staple
	@xcrun stapler staple $(DMG)
	@echo "[OK] notarized + stapled（app + dmg）：$(DMG)"

# 本機發版（簽名私鑰不出本機）。CI 發版走 .github/workflows/release.yml（tag 觸發）。
publish: release
	gh release create v$(VERSION) $(DMG) --title "v$(VERSION)" --generate-notes

verify:
	@codesign -dvvv $(APP_BUNDLE) 2>&1 | grep -E 'Authority|TeamIdentifier|flags' || true
	@spctl -a -vvv $(APP_BUNDLE) 2>&1 || true

logs:
	log stream --predicate 'process == "$(APP_NAME)"' --style compact

clean:
	rm -rf .build build
