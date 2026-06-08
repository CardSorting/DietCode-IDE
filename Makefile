CXX := clang++

# Header search paths
INC_FLAGS := -I./src \
             -I./src/platform/macos/control \
             -I./src/platform/macos/control/categories \
             -I./src/platform/macos/control/services \
             -I./src/platform/macos/control/utils \
             -I./src/platform/macos/ui \
             -I./src/platform/macos/ui/app \
             -I./src/platform/macos/ui/controllers \
             -I./src/platform/macos/ui/controllers/categories \
             -I./src/platform/macos/ui/views \
             -I./src/platform/macos/ui/utils \
             -I./src/platform/macos/services

CXXFLAGS := -std=c++20 -Wall -Wextra -Wpedantic $(INC_FLAGS)
OBJCXXFLAGS := -std=c++20 -Wall -Wextra $(INC_FLAGS) -fobjc-arc

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
	src/platform/macos/ui/app/MacAppDelegate.mm \
	src/platform/macos/ui/controllers/MacWindow.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Layout.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Tabs.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Files.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Search.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Git.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Language.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Diagnostics.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+RunTerminal.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Settings.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+Recovery.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+AgentAPI.mm \
	src/platform/macos/ui/controllers/categories/MacWindow+CommandPalette.mm \
	src/platform/macos/ui/utils/MacWindowUtilities.mm \
	src/platform/macos/ui/views/MacEditorComponents.mm \
	src/platform/macos/ui/app/MacMenu.mm \
	src/platform/macos/ui/app/MacFileDialog.mm \
	src/platform/macos/ui/app/MacClipboard.mm \
	src/platform/macos/ui/views/MacTextRendering.mm \
	src/platform/macos/control/MacControlServer.mm \
	src/platform/macos/control/categories/MacControlServer+File.mm \
	src/platform/macos/control/categories/MacControlServer+Editor.mm \
	src/platform/macos/control/categories/MacControlServer+Git.mm \
	src/platform/macos/control/categories/MacControlServer+Terminal.mm \
	src/platform/macos/control/categories/MacControlServer+Context.mm \
	src/platform/macos/control/utils/MacControlSupport.mm \
	src/platform/macos/control/utils/MacControlPathSecurity.mm \
	src/platform/macos/control/utils/MacControlSerialization.mm \
	src/platform/macos/control/utils/MacControlRuntimeDiagnostics.mm \
	src/platform/macos/control/utils/MacControlSocketSafety.mm \
	src/platform/macos/control/utils/MacControlReleaseVersions.mm \
	src/platform/macos/control/utils/MacControlDiffParsing.mm \
	src/platform/macos/control/services/MacControlRecoveryStore.mm \
	src/platform/macos/control/services/MacControlSearchService.mm \
	src/platform/macos/control/services/MacControlPatchService.mm \
	src/platform/macos/control/services/MacControlWorkspaceState.mm \
	src/platform/macos/control/services/MacControlTaskRuntime.mm \
	src/platform/macos/control/services/MacControlComboRuntime.mm \
	src/platform/macos/control/services/MacControlRoutingPolicy.mm \
	src/platform/macos/control/services/MacControlMethodCatalog.mm \
	src/platform/macos/control/services/MacControlToolRegistry.mm \
	src/platform/macos/control/services/MacControlWindowBridge.mm \
	src/platform/macos/services/SymbolIndexService.mm \
	src/platform/macos/services/DiffAnalysisService.mm \
	src/platform/macos/services/WorkspaceAnalysisService.mm \
	src/platform/macos/services/BufferStateService.mm \
	src/platform/macos/services/SubprocessRunner.mm \
	src/filesystem/GitService.mm \
	src/filesystem/FileWatcher.mm \
	src/core/LSPClient.mm

.PHONY: all app run headless ensure-socket restart-agent-server agent-ready agent-status agent-ping agent-methods agent-capabilities agent-self-test test-agent-offline control-smoke test-task-health test-rpc-transaction test-ergonomics test-grep-diff-tooling test-runtime-determinism test-transaction-kernel test-harness-realism test-deterministic-retrieval test-agent-workflow-smoke test-cli-agent-failures test-docs-code-drift test-agent-integration agent-integration verify-agent-runtime verify-agent-runtime-full test clean

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

restart-agent-server: app
	-pkill -f "$(APP_MACOS)/$(APP_NAME)" 2>/dev/null || true
	sleep 0.5
	$(APP_MACOS)/$(APP_NAME) --ensure-socket

agent-ready: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json

agent-status: app
	python3 scripts/dietcode_agent_client.py --status --compact --error-json

agent-ping: app
	python3 scripts/dietcode_agent_client.py --compact --error-json rpc.ping

agent-methods: app
	python3 scripts/dietcode_agent_client.py --list-methods --compact --error-json

agent-capabilities: app
	python3 scripts/dietcode_agent_client.py --capabilities --compact --error-json

agent-self-test:
	python3 scripts/dietcode_agent_client.py --self-test --compact

test-agent-offline: agent-self-test
	python3 scripts/test_contract_lockdown.py --compact

control-smoke: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/control_smoke_test.py --compact

test-task-health: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_task_server_health.py --compact

test-rpc-transaction: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_rpc_transaction_health.py --compact

test-operator-diagnostics: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_operator_diagnostics.py --compact

test-runtime-safety: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_runtime_safety.py --compact

test-grep-diff-tooling: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_grep_diff_tooling.py --compact

test-runtime-determinism: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_runtime_determinism.py --compact

test-transaction-kernel: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_transaction_kernel.py --compact

test-harness-realism: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_harness_realism.py --compact

test-deterministic-retrieval: restart-agent-server
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_deterministic_retrieval.py --compact

test-agent-workflow-smoke: restart-agent-server
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_agent_workflow_smoke.py --compact

test-cli-agent-failures: restart-agent-server
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_cli_agent_failures.py --compact

test-docs-code-drift:
	python3 scripts/test_docs_code_drift.py --compact

test-ergonomics: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_ergonomics.py --compact

agent-integration: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/run_agent_integration_tests.py --compact

test-agent-integration: agent-integration

verify-agent-runtime:
	python3 scripts/verify_agent_runtime.py --compact

verify-agent-runtime-full:
	python3 scripts/verify_agent_runtime_full.py --compact

release-check-agent-runtime:
	python3 scripts/release_check_agent_runtime.py --compact

$(TEST_BIN): $(BUILD_DIR) $(CORE_CPP) tests/test_editor.cpp
	$(CXX) $(CXXFLAGS) $(CORE_CPP) tests/test_editor.cpp -o $(TEST_BIN)

test: $(TEST_BIN) agent-self-test
	$(TEST_BIN)

clean:
	rm -rf $(BUILD_DIR)
