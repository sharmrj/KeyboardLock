.PHONY: build app clean

build:
	swift build

app:
	./build-app.sh

clean:
	swift package clean
	rm -rf dist
