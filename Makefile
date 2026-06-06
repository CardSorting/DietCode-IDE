CXX := clang++
CXXFLAGS := -std=c++20 -Wall -Wextra -Wpedantic -I./src -I./src/platform/macos/control -I./src/platform/macos/ui -I./src/platform/macos/services
OBJCXXFLAGS := -std=c++20 -Wall -Wextra -I./src -I./src/platform/macos/control -I./src/platform/macos/ui -I./src/platform/macos/services -fobjc-arc
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
	src/filesystem/FileService.cpp \
	src/syntax/Tokenizer.cpp

MACOS_MM := \
	src/platform/macos/main.mm \
	src/platform/macos/ui/MacAppDelegate.mm \
	src/platform/macos/ui/MacWindow.mm \
	src/platform/macos/ui/MacWindow+Layout.mm \
	src/platform/macos/ui/MacWindow+Tabs.mm \
	src/platform/macos/ui/MacWindow+Files.mm \
	src/platform/macos/ui/MacWindow+Search.mm \
	src/platform/macos/ui/MacWindow+Git.mm \
	src/platform/macos/ui/MacWindow+Language.mm \
	src/platform/macos/ui/MacWindow+Diagnostics.mm \
	src/platform/macos/ui/MacWindow+RunTerminal.mm \
	src/platform/macos/ui/MacWindow+Settings.mm \
	src/platform/macos/ui/MacWindow+Recovery.mm \
	src/platform/macos/ui/MacWindow+AgentAPI.mm \
	src/platform/macos/ui/MacWindow+CommandPalette.mm \
	src/platform/macos/ui/MacWindowUtilities.mm \
	src/platform/macos/ui/MacEditorComponents.mm \
	src/platform/macos/ui/MacMenu.mm \
	src/platform/macos/ui/MacFileDialog.mm \
	src/platform/macos/ui/MacClipboard.mm \
	src/platform/macos/ui/MacTextRendering.mm \
	src/platform/macos/control/MacControlServer.mm \
	src/platform/macos/control/MacControlSupport.mm \
	src/platform/macos/control/MacControlPathSecurity.mm \
	src/platform/macos/control/MacControlSerialization.mm \
	src/platform/macos/control/MacControlDiffParsing.mm \
	src/platform/macos/control/MacControlRecoveryStore.mm \
	src/platform/macos/control/MacControlSearchService.mm \
	src/platform/macos/control/MacControlPatchService.mm \
	src/platform/macos/control/MacControlTaskRuntime.mm \
	src/platform/macos/control/MacControlComboRuntime.mm \
	src/platform/macos/control/MacControlRoutingPolicy.mm \
	src/platform/macos/control/MacControlMethodCatalog.mm \
	src/platform/macos/control/MacControlWindowBridge.mm \
	src/platform/macos/services/SymbolIndexService.mm \
	src/platform/macos/services/DiffAnalysisService.mm \
	src/platform/macos/services/WorkspaceAnalysisService.mm \
	src/platform/macos/services/BufferStateService.mm \
	src/platform/macos/services/SubprocessRunner.mm \
	src/filesystem/GitService.mm \
	src/filesystem/FileWatcher.mm \
	src/core/LSPClient.mm

.PHONY: all app run headless ensure-socket agent-ready agent-status agent-ping agent-methods agent-capabilities agent-self-test control-smoke test clean

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

headless: app
	$(APP_MACOS)/$(APP_NAME) --headless

ensure-socket: app
	$(APP_MACOS)/$(APP_NAME) --ensure-socket

agent-ready: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact

agent-status: app
	python3 scripts/dietcode_agent_client.py --status --compact

agent-ping: app
	python3 scripts/dietcode_agent_client.py --compact rpc.ping

agent-methods: app
	python3 scripts/dietcode_agent_client.py --list-methods --compact

agent-capabilities: app
	python3 scripts/dietcode_agent_client.py --capabilities --compact

agent-self-test:
	python3 scripts/dietcode_agent_client.py --self-test --compact

control-smoke: app
	python3 scripts/control_smoke_test.py

$(TEST_BIN): $(BUILD_DIR) $(CORE_CPP) tests/test_editor.cpp
	$(CXX) $(CXXFLAGS) $(CORE_CPP) tests/test_editor.cpp -o $(TEST_BIN)

test: $(TEST_BIN) agent-self-test
	$(TEST_BIN)

clean:
	rm -rf $(BUILD_DIR)
