XCODEGEN ?= xcodegen
BUILD_DIR := $(CURDIR)/build
PROJECT := Dozer.xcodeproj
APP_NAME := Dozer.app
DESTINATION ?= /Applications/Dozer.app

.PHONY: project build release test test-runtime test-window-shortcuts test-window-adjustment test-rectangle-updates rectangle-check rectangle-stage rectangle-verify install run clean

project:
	@command -v "$(XCODEGEN)" >/dev/null || { echo 'Install XcodeGen first: brew install xcodegen'; exit 1; }
	@"$(XCODEGEN)" generate --spec project.yml

build: project
	xcodebuild -quiet -project "$(PROJECT)" -scheme Dozer -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath "$(BUILD_DIR)" build CODE_SIGNING_ALLOWED=NO
	@Scripts/SignApp.sh "$(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)"

release: project
	xcodebuild -quiet -project "$(PROJECT)" -scheme Dozer -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$(BUILD_DIR)" build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO
	@Scripts/SignApp.sh "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME)"

test:
	swift test

test-rectangle-updates:
	python3 -m unittest discover -s Tests/RectangleReleaseTests -v

rectangle-check:
	python3 Scripts/rectangle_release.py check

rectangle-stage:
	python3 Scripts/rectangle_release.py update

rectangle-verify:
	python3 Scripts/rectangle_release.py verify

test-runtime:
	@Scripts/TestRuntime.sh

test-window-shortcuts:
	@Scripts/TestWindowShortcuts.sh

test-window-adjustment:
	@Scripts/TestWindowAdjustment.sh

install: release
	@Scripts/InstallApp.sh "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME)" "$(DESTINATION)"

run: build
	open "$(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)"

clean:
	xcodebuild -quiet -project "$(PROJECT)" -scheme Dozer -destination 'generic/platform=macOS' -derivedDataPath "$(BUILD_DIR)" clean
	swift package clean
