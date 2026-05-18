.PHONY: app daemon

app:
	xcodegen generate
	open NookApp.xcodeproj

daemon:
	swift build
