build:
	@brew bundle --no-upgrade
	@mkdir -p BarHide/Other/Generated
	@swiftgen
	@xcodegen
	@xed "."

release:
	@echo "Running Fastlane deploy"
	@bundle exec fastlane release

.PHONY: build release
