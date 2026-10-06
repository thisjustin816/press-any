PROJECT_NAME ?= PressAny
DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro

.PHONY: bootstrap generate build test test-share-ui test-package-ios test-core test-sameboy-bridge bootroms known-dumps

bootstrap:
	./Scripts/bootstrap.sh

bootroms:
	./Scripts/generate-sameboy-bootroms.sh

generate:
	xcodegen generate

build:
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(PROJECT_NAME) -destination '$(DESTINATION)' build

test:
	xcodebuild -project $(PROJECT_NAME).xcodeproj -scheme $(PROJECT_NAME) -destination '$(DESTINATION)' test

test-share-ui:
	./Scripts/test-share-ui.sh

test-package-ios:
	cd Packages/EmulatorKit && xcodebuild -scheme EmulatorKit-Package -destination '$(DESTINATION)' test

test-core:
	swift test --package-path Packages/EmulatorKit

test-sameboy-bridge:
	./Scripts/test-sameboy-bridge-linux.sh

# Refresh the bundled No-Intro data from DB exports downloaded in a browser:
#   make known-dumps GB=<Game Boy .zip or .xml> GBC=<Game Boy Color .zip or .xml>
known-dumps:
	./Scripts/generate-known-dumps.py "$(GB)" "$(GBC)" Packages/EmulatorKit/Sources/GameIdentity/Resources/KnownDumps.json
