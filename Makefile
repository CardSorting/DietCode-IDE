CXX := clang++
CXXFLAGS := -std=c++20 -Wall -Wextra -Wpedantic -I./src
OBJCXXFLAGS := -std=c++20 -Wall -Wextra -I./src -fobjc-arc
BUILD_DIR := build
APP_NAME := DietCode
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_RESOURCES := $(APP_CONTENTS)/Resources
TEST_BIN := $(BUILD_DIR)/test_editor

CORE_CPP := \
	src/editor/TextBuffer.cpp \
	src/editor/EditorDocument.cpp \
	src/search/FindInFile.cpp \
	src/filesystem/FileService.cpp

MACOS_MM := \
	src/platform/macos/main.mm \
	src/platform/macos/MacAppDelegate.mm \
	src/platform/macos/MacWindow.mm \
	src/platform/macos/MacMenu.mm \
	src/platform/macos/MacFileDialog.mm \
	src/platform/macos/MacClipboard.mm \
	src/platform/macos/MacTextRendering.mm \
	src/platform/macos/MacControlServer.mm \
	src/platform/macos/SymbolIndexService.mm \
	src/platform/macos/DiffAnalysisService.mm \
	src/platform/macos/WorkspaceAnalysisService.mm \
	src/platform/macos/BufferStateService.mm \
	src/filesystem/GitService.mm \
	src/core/LSPClient.mm

.PHONY: all app run test clean

all: app test

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(APP_MACOS):
	mkdir -p $(APP_MACOS)

$(APP_RESOURCES):
	mkdir -p $(APP_RESOURCES)

app: $(APP_MACOS) $(APP_RESOURCES)
	cp resources/Info.plist $(APP_CONTENTS)/Info.plist
	if [ -f resources/AppIcon.icns ]; then cp resources/AppIcon.icns $(APP_RESOURCES)/AppIcon.icns; fi
	$(CXX) $(OBJCXXFLAGS) $(CORE_CPP) $(MACOS_MM) -framework Cocoa -o $(APP_MACOS)/$(APP_NAME)

run: app
	open $(APP_BUNDLE)

$(TEST_BIN): $(BUILD_DIR) $(CORE_CPP) tests/test_editor.cpp
	$(CXX) $(CXXFLAGS) $(CORE_CPP) tests/test_editor.cpp -o $(TEST_BIN)

test: $(TEST_BIN)
	$(TEST_BIN)

clean:
	rm -rf $(BUILD_DIR)
