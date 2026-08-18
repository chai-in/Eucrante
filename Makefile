.PHONY: check test build app clean

check:
	swift format lint --recursive Sources Tests Package.swift
	swift run EucranteCoreChecks

test:
	swift test

build:
	swift build --product Eucrante

app:
	./Scripts/build-app.sh release

clean:
	swift package clean
