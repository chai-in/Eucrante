.PHONY: check test coverage build app verify-app notarize clean

check:
	swift format lint --strict --recursive Sources Tests Package.swift Scripts/render-app-icon.swift
	swift run EucranteCoreChecks

test:
	swift test -Xswiftc -warnings-as-errors

coverage:
	./Scripts/check-coverage.sh 47 8

build:
	swift build --product Eucrante

app:
	./Scripts/build-app.sh release

verify-app:
	./Scripts/verify-app.sh

notarize: app
	./Scripts/notarize-app.sh

clean:
	swift package clean
