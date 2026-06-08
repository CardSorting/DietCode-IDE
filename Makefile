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
APP_BIN := $(APP_RESOURCES)/bin
AGENT_BRIDGE_DIR := agent-bridge
AGENT_BRIDGE_DIST := $(AGENT_BRIDGE_DIR)/dist
PACKAGED_BRIDGE := $(APP_RESOURCES)/agent-bridge
PACKAGED_BRIDGE_CLI := $(APP_BIN)/dietcode-agent-client
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
	src/platform/macos/control/services/MacControlMemoryService.mm \
	src/platform/macos/control/categories/MacControlServer+Memory.mm \
	src/platform/macos/control/categories/MacControlServer+Runtime.mm \
	src/platform/macos/control/services/MacControlTaskRuntime.mm \
	src/platform/macos/control/services/MacControlComboRuntime.mm \
	src/platform/macos/control/services/MacControlRoutingPolicy.mm \
	src/platform/macos/control/services/MacControlMethodCatalog.mm \
	src/platform/macos/control/services/MacControlToolRegistry.mm \
	src/platform/macos/control/services/MacControlShellService.mm \
	src/platform/macos/control/categories/MacControlServer+Shell.mm \
	src/platform/macos/control/services/MacControlWindowBridge.mm \
	src/platform/macos/services/SymbolIndexService.mm \
	src/platform/macos/services/DiffAnalysisService.mm \
	src/platform/macos/services/WorkspaceAnalysisService.mm \
	src/platform/macos/services/BufferStateService.mm \
	src/platform/macos/services/SubprocessRunner.mm \
	src/filesystem/GitService.mm \
	src/filesystem/FileWatcher.mm \
	src/core/LSPClient.mm

.PHONY: all app agent-bridge agent-bridge-fast run headless ensure-socket restart-agent-server restart-agent-server-fast agent-ready agent-status agent-ping agent-methods agent-capabilities agent-self-test test-agent-offline control-smoke test-task-health test-rpc-transaction test-ergonomics test-grep-diff-tooling test-runtime-determinism test-transaction-kernel test-harness-realism test-deterministic-retrieval test-agent-workflow-smoke test-agent-shell-tooling test-agent-shell-tooling-fast test-agent-shell-workflows test-agent-shell-workflows-fast test-authority-boundaries test-authority-boundaries-fast test-agent-bridge-authority test-cli-agent-failures test-docs-code-drift test-partial-success-closure test-broccoliq-runtime-memory test-broccoliq-runtime-memory-fast test-runtime-native-integration test-runtime-native-integration-fast test-agent-bridge test-agent-bridge-fast test-agent-integration agent-integration verify-agent-runtime verify-agent-runtime-fast verify-agent-runtime-full verify-agent-runtime-full-fast benchmark-agent-success benchmark-agent-success-fast benchmark-agent-success-report test-agent-success-report test clean

all: app test

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(APP_MACOS):
	mkdir -p $(APP_MACOS)

$(APP_RESOURCES):
	mkdir -p $(APP_RESOURCES)

$(APP_BIN):
	mkdir -p $(APP_BIN)

agent-bridge-fast:
	cd $(AGENT_BRIDGE_DIR) && npm install --silent && npm run build

agent-bridge: agent-bridge-fast

$(PACKAGED_BRIDGE): agent-bridge-fast
	rm -rf $(PACKAGED_BRIDGE)
	mkdir -p $(PACKAGED_BRIDGE)
	cp -R $(AGENT_BRIDGE_DIR)/dist $(PACKAGED_BRIDGE)/
	cp $(AGENT_BRIDGE_DIR)/package.json $(PACKAGED_BRIDGE)/

$(PACKAGED_BRIDGE_CLI): $(APP_BIN) resources/bin/dietcode-agent-client
	cp resources/bin/dietcode-agent-client $(PACKAGED_BRIDGE_CLI)
	chmod +x $(PACKAGED_BRIDGE_CLI)

app: $(APP_MACOS) $(APP_RESOURCES) $(APP_BIN) $(PACKAGED_BRIDGE) $(PACKAGED_BRIDGE_CLI)
	cp resources/Info.plist $(APP_CONTENTS)/Info.plist
	if [ -f resources/AppIcon.icns ]; then cp resources/AppIcon.icns $(APP_RESOURCES)/AppIcon.icns; fi
	$(CXX) $(OBJCXXFLAGS) $(CORE_CPP) $(MACOS_MM) -framework Cocoa -lsqlite3 -o $(APP_MACOS)/$(APP_NAME)

run: app
	open $(APP_BUNDLE)

headless: app
	$(APP_MACOS)/$(APP_NAME) --headless

ensure-socket: app
	$(APP_MACOS)/$(APP_NAME) --ensure-socket

restart-agent-server: app
	-pkill -f "$(APP_MACOS)/$(APP_NAME)" 2>/dev/null || true
	sleep 0.5
	DIETCODE_REPO_ROOT=$(CURDIR) $(APP_MACOS)/$(APP_NAME) --ensure-socket

# Restart agent server without rebuilding — assumes binary already matches HEAD.
restart-agent-server-fast:
	-pkill -f "$(APP_MACOS)/$(APP_NAME)" 2>/dev/null || true
	sleep 0.5
	DIETCODE_REPO_ROOT=$(CURDIR) $(APP_MACOS)/$(APP_NAME) --ensure-socket

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

test-agent-shell-tooling: restart-agent-server
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_agent_shell_tooling.py --compact

test-agent-shell-tooling-fast:
	python3 scripts/test_agent_shell_tooling.py --compact

test-agent-shell-workflows: restart-agent-server
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_agent_shell_workflows.py --compact

test-agent-shell-workflows-fast:
	python3 scripts/test_agent_shell_workflows.py --compact

test-authority-boundaries: restart-agent-server
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_authority_boundaries.py --compact

test-authority-boundaries-fast:
	python3 scripts/test_authority_boundaries.py --compact

test-agent-bridge-authority:
	cd $(AGENT_BRIDGE_DIR) && npm run build && npm run test:authority

test-cli-agent-failures: restart-agent-server
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_cli_agent_failures.py --compact

test-docs-code-drift:
	python3 scripts/test_docs_code_drift.py --compact

test-partial-success-closure: restart-agent-server
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_partial_success_closure.py --compact

# BroccoliQ runtime memory: full target rebuilds app + restarts agent server before live harness.
test-broccoliq-runtime-memory: restart-agent-server
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/test_broccoliq_runtime_memory.py --compact

# BroccoliQ runtime memory: fast iteration — no rebuild/restart; assumes server/binary already match HEAD.
test-broccoliq-runtime-memory-fast:
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/test_broccoliq_runtime_memory.py --compact

# Pass VIII: native runtime integration — full rebuild/restart before live harness.
test-runtime-native-integration: restart-agent-server
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/test_runtime_native_integration.py --compact

# Pass VIII: fast iteration — assumes server/binary already match HEAD.
test-runtime-native-integration-fast:
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/test_runtime_native_integration.py --compact

test-ergonomics: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_ergonomics.py --compact

test-agent-bridge-fast: agent-bridge-fast
	cd $(AGENT_BRIDGE_DIR) && npm run test:fast

test-agent-bridge-audit: app
	python3 scripts/test_agent_bridge_audit.py --compact

test-agent-bridge: restart-agent-server
	cd $(AGENT_BRIDGE_DIR) && npm test
	cd $(AGENT_BRIDGE_DIR) && BRIDGE_LIVE=1 npm run test:live
	python3 scripts/test_agent_bridge_audit.py --compact

agent-integration: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/run_agent_integration_tests.py --compact

test-agent-integration: agent-integration

verify-agent-runtime:
	python3 scripts/verify_agent_runtime.py --compact

# Fast runtime ladder — no rebuild/restart; assumes server/binary already match HEAD.
verify-agent-runtime-fast:
	python3 scripts/verify_agent_runtime.py --compact --assume-server-ready

verify-agent-runtime-full:
	python3 scripts/verify_agent_runtime_full.py --compact

# Fast full ladder — single restart without rebuild; nested verify skips second restart.
verify-agent-runtime-full-fast:
	python3 scripts/verify_agent_runtime_full.py --compact --assume-server-ready

release-check-agent-runtime:
	python3 scripts/release_check_agent_runtime.py --compact

# Agent success benchmark: full rebuild/restart before live harness.
benchmark-agent-success: restart-agent-server agent-bridge-fast
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	DIETCODE_REPO_ROOT=$(CURDIR) python3 benchmarks/agent_success/run_benchmark.py --assume-server-ready

# Agent success benchmark report from latest JSONL results.
benchmark-agent-success-report:
	python3 benchmarks/agent_success/report_results.py

test-agent-success-report:
	python3 benchmarks/agent_success/test_report_results.py

# Agent success benchmark: fast iteration — assumes server/binary/bridge already match HEAD.
benchmark-agent-success-fast: agent-bridge-fast
	DIETCODE_REPO_ROOT=$(CURDIR) python3 benchmarks/agent_success/run_benchmark.py --assume-server-ready
	python3 benchmarks/agent_success/report_results.py

$(TEST_BIN): $(BUILD_DIR) $(CORE_CPP) tests/test_editor.cpp
	$(CXX) $(CXXFLAGS) $(CORE_CPP) tests/test_editor.cpp -o $(TEST_BIN)

test: $(TEST_BIN) agent-self-test
	$(TEST_BIN)

clean:
	rm -rf $(BUILD_DIR)
