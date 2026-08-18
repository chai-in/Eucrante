.PHONY: check test build app notarize clean

check:
	swift format lint --recursive Sources Tests Package.swift
	swift run EucranteCoreChecks

test:
	swift test

build:
	swift build --product Eucrante

app:
	./Scripts/build-app.sh release

notarize: app
	./Scripts/notarize-app.sh

clean:
	swift package clean
