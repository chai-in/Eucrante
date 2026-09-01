.PHONY: check test coverage cloudflare-check build app dmg-development dmg-public verify-app notarize publish-source-release publish-public-dmg-release publish-release clean

check:
	zsh -n Scripts/*.sh
	swift format lint --strict --recursive Sources Tests Package.swift Scripts/render-app-icon.swift Scripts/render-dmg-background.swift
	swift run EucranteCoreChecks

test:
	swift test -Xswiftc -warnings-as-errors

coverage:
	./Scripts/check-coverage.sh 92 83

cloudflare-check:
	npm run build

build:
	swift build --product Eucrante

app:
	./Scripts/build-app.sh release

dmg-development: app
	./Scripts/create-dmg.sh development

dmg-public: app
	./Scripts/create-dmg.sh public

verify-app:
	./Scripts/verify-app.sh

notarize: app
	./Scripts/notarize-app.sh

publish-source-release:
	./Scripts/publish-release.sh --source-only "$(NOTES)"

publish-public-dmg-release:
	./Scripts/publish-release.sh --public-dmg "$(NOTES)"

publish-release:
	./Scripts/publish-release.sh "$(NOTES)"

clean:
	swift package clean
