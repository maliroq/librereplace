.PHONY: test validate safety project-config harness-test generate build-macos check

test:
	swift test

validate:
	python3 Scripts/validate_catalog.py
	swift run libreplace validate Catalog/catalog.json

safety:
	python3 Scripts/check_repo_safety.py

project-config:
	python3 Scripts/validate_xcodegen_config.py

harness-test:
	python3 Scripts/test_dev_harness.py
	bash -n Scripts/check_distribution_prereqs.sh
	bash -n Scripts/install_local.sh

check: test validate safety project-config harness-test

generate:
	@command -v xcodegen >/dev/null || (echo "Install XcodeGen: brew install xcodegen" && exit 1)
	xcodegen generate

build-macos: generate
	xcodebuild -project LibreReplace.xcodeproj -scheme LibreReplace -configuration Debug CODE_SIGNING_ALLOWED=NO build
