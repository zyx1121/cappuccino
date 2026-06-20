APP_NAME    := lidlatte
BUNDLE_ID   := dev.zyx1121.lidlatte
BIN_PATH    := .build/release/$(APP_NAME)
APP_BUNDLE  := build/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents

# Apple Development: yongxiang.zhan@outlook.com (FJW6JALJHP)
SIGN_ID := 53522E3FA5C4B3895923E59B64C70D38ECEF6FBC

.PHONY: all build bundle run clean rebuild verify

all: bundle

build:
	swift build -c release

bundle: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	@cp $(BIN_PATH) $(CONTENTS)/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp scripts/grant.sh scripts/lidlatte.sudoers.template $(CONTENTS)/Resources/
	@chmod +x $(CONTENTS)/Resources/grant.sh
	@codesign --force --deep --options runtime --sign $(SIGN_ID) $(APP_BUNDLE)
	@echo "[OK] $(APP_BUNDLE) built and signed"

run: bundle
	open $(APP_BUNDLE)

rebuild: clean bundle

verify:
	@codesign -dvvv $(APP_BUNDLE) 2>&1 | grep -E 'Authority|TeamIdentifier|flags'
	@echo "--- SleepDisabled ---" && pmset -g | grep -i SleepDisabled || echo "(off)"

clean:
	rm -rf .build build
