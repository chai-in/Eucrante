.PHONY: check test coverage build app verify-app notarize publish-source-release publish-release clean

check:
	swift format lint --strict --recursive Sources Tests Package.swift Scripts/render-app-icon.swift
	swift run EucranteCoreChecks

test:
	swift test -Xswiftc -warnings-as-errors

coverage:
	./Scripts/check-coverage.sh 92 83

build:
	swift build --product Eucrante

app:
	./Scripts/build-app.sh release

verify-app:
	./Scripts/verify-app.sh

notarize: app
	./Scripts/notarize-app.sh

publish-source-release:
	./Scripts/publish-release.sh --source-only "$(NOTES)"

publish-release:
	./Scripts/publish-release.sh "$(NOTES)"

clean:
	swift package clean
