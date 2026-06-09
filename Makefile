CXX := clang++

# Header search paths
INC_FLAGS := -I./src \
             -I./src/kernel \
             -I./src/kernel/workspace \
             -I./legacy_ui/macos/control \
             -I./src/platform/macos \
             -I./src/platform/macos/control \
             -I./src/platform/macos/control/categories \
             -I./src/platform/macos/control/services \
             -I./src/platform/macos/control/utils \
             -I./legacy_ui/macos \
             -I./legacy_ui/macos/ui \
             -I./legacy_ui/macos/ui/app \
             -I./legacy_ui/macos/ui/controllers \
             -I./legacy_ui/macos/ui/controllers/categories \
             -I./legacy_ui/macos/ui/views \
             -I./legacy_ui/macos/ui/utils \
             -I./src/platform/macos/services

CXXFLAGS := -std=c++20 -Wall -Wextra -Wpedantic $(INC_FLAGS)
OBJCXXFLAGS := -std=c++20 -Wall -Wextra $(INC_FLAGS) -fobjc-arc

BUILD_DIR := build
KERNEL_NAME := dietcode-kernel
KERNEL_BINARY := $(BUILD_DIR)/$(KERNEL_NAME)
KERNEL_RESOURCES := $(BUILD_DIR)/resources
KERNEL_BIN := $(KERNEL_RESOURCES)/bin
APP_NAME := DietCode
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_BINARY := $(APP_MACOS)/$(APP_NAME)
APP_RESOURCES := $(APP_CONTENTS)/Resources
APP_BIN := $(APP_RESOURCES)/bin
AGENT_BRIDGE_DIR := agent-bridge
AGENT_BRIDGE_DIST := $(AGENT_BRIDGE_DIR)/dist
PACKAGED_BRIDGE := $(KERNEL_RESOURCES)/agent-bridge
PACKAGED_BRIDGE_CLI := $(KERNEL_BIN)/dietcode-agent-client
LEGACY_PACKAGED_BRIDGE := $(APP_RESOURCES)/agent-bridge
LEGACY_PACKAGED_BRIDGE_CLI := $(APP_BIN)/dietcode-agent-client
HERMES_PLUGIN_SRC := integrations/hermes-dietcode-plugin
PACKAGED_HERMES_PLUGIN := $(KERNEL_RESOURCES)/integrations/hermes/dietcode
LEGACY_PACKAGED_HERMES_PLUGIN := $(APP_RESOURCES)/integrations/hermes/dietcode
PACKAGED_ENABLE_AGENT := $(KERNEL_BIN)/dietcode-enable-agent
PACKAGED_ENABLE_AGENT_PY := $(KERNEL_BIN)/dietcode-enable-agent.py
PACKAGED_AGENT_CHAT := $(KERNEL_BIN)/dietcode-agent-chat
PACKAGED_AGENT_CHAT_PY := $(KERNEL_BIN)/dietcode-agent-chat.py
PACKAGED_AGENT_BUNDLE_PY := $(KERNEL_BIN)/dietcode_agent_bundle.py
PACKAGED_MUTATION_AUTHORITY_PY := $(KERNEL_BIN)/dietcode_mutation_authority.py
PACKAGED_DIFF_AUTHORITY_PY := $(KERNEL_BIN)/dietcode_diff_authority.py
PACKAGED_VERIFICATION_AUTHORITY_PY := $(KERNEL_BIN)/dietcode_verification_authority.py
PACKAGED_BUNDLE_MANIFEST := $(KERNEL_RESOURCES)/dietcode-agent-bundle.manifest.json
LEGACY_PACKAGED_BUNDLE_MANIFEST := $(APP_RESOURCES)/dietcode-agent-bundle.manifest.json
BUNDLE_MANIFEST_SRC := resources/dietcode-agent-bundle.manifest.json
TEST_BIN := $(BUILD_DIR)/test_editor

CORE_CPP := \
	src/editor/TextBuffer.cpp \
	src/editor/EditorDocument.cpp \
	src/search/FindInFile.cpp \
	src/filesystem/FileService.cpp \
	src/syntax/Tokenizer.cpp

WORKSPACE_MM := \
	legacy_ui/macos/ui/controllers/MacWindow.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Layout.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Tabs.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Files.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Search.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Git.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Language.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Diagnostics.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+RunTerminal.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Settings.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+Recovery.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+AgentAPI.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+AgentSidebar.mm \
	legacy_ui/macos/MacAgentSidebar.mm \
	legacy_ui/macos/ui/controllers/categories/MacWindow+CommandPalette.mm \
	legacy_ui/macos/ui/utils/MacWindowUtilities.mm \
	legacy_ui/macos/ui/views/MacEditorComponents.mm \
	legacy_ui/macos/ui/app/MacFileDialog.mm \
	legacy_ui/macos/ui/app/MacClipboard.mm \
	legacy_ui/macos/ui/views/MacTextRendering.mm

LEGACY_UI_MM := \
	legacy_ui/macos/main.mm \
	legacy_ui/macos/ui/app/MacAppDelegate.mm \
	legacy_ui/macos/ui/app/MacMenu.mm

KERNEL_WORKSPACE_CPP := \
	src/kernel/workspace/WorkspaceFileOps.cpp \
	src/kernel/workspace/WorkspacePatchOps.cpp \
	src/kernel/workspace/WorkspaceVerifyOps.cpp \
	src/kernel/workspace/WorkspaceIndex.cpp \
	src/kernel/workspace/WorkspaceSession.cpp

KERNEL_RUNTIME_MM := \
	src/kernel/KernelAppDelegate.mm \
	src/kernel/KernelRuntime.mm \
	src/kernel/workspace/WorkspaceSessionBridge.mm

KERNEL_APP_MM := \
	src/kernel/main.mm \
	$(KERNEL_RUNTIME_MM)

LEGACY_CONTROL_MM := \
	legacy_ui/macos/control/DietCodeLegacyWindowBridge.mm

CONTROL_MM := \
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
	src/platform/macos/control/services/MacControlCoherenceTokens.mm \
	src/platform/macos/control/services/MacControlMemoryService.mm \
	src/platform/macos/control/services/MacControlApprovalService.mm \
	src/platform/macos/control/categories/MacControlServer+Approval.mm \
	src/platform/macos/control/categories/MacControlServer+WorkspaceDrift.mm \
	src/platform/macos/control/categories/MacControlServer+Coherence.mm \
	src/platform/macos/control/categories/MacControlServer+VerifyGate.mm \
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

KERNEL_OBJCXXFLAGS := $(OBJCXXFLAGS) -DDIETCODE_KERNEL_BUILD
KERNEL_SOURCES := $(KERNEL_WORKSPACE_CPP) src/filesystem/FileService.cpp $(CONTROL_MM) $(KERNEL_APP_MM)
LEGACY_SOURCES := $(KERNEL_WORKSPACE_CPP) $(CORE_CPP) $(WORKSPACE_MM) $(CONTROL_MM) $(KERNEL_RUNTIME_MM) $(LEGACY_UI_MM) $(LEGACY_CONTROL_MM)

KERNEL_BUNDLE := $(KERNEL_BINARY) $(PACKAGED_BRIDGE) $(PACKAGED_BRIDGE_CLI) $(PACKAGED_HERMES_PLUGIN) $(PACKAGED_ENABLE_AGENT) $(PACKAGED_ENABLE_AGENT_PY) $(PACKAGED_AGENT_CHAT) $(PACKAGED_AGENT_CHAT_PY) $(PACKAGED_AGENT_BUNDLE_PY) $(PACKAGED_MUTATION_AUTHORITY_PY) $(PACKAGED_DIFF_AUTHORITY_PY) $(PACKAGED_VERIFICATION_AUTHORITY_PY) $(PACKAGED_BUNDLE_MANIFEST)
AGENT_CHAT_BUNDLE := $(KERNEL_BUNDLE)
LEGACY_AGENT_CHAT_BUNDLE := $(APP_BINARY) $(LEGACY_PACKAGED_BRIDGE) $(LEGACY_PACKAGED_BRIDGE_CLI) $(LEGACY_PACKAGED_HERMES_PLUGIN) $(LEGACY_PACKAGED_BUNDLE_MANIFEST)

.PHONY: all kernel app legacy-app agent-chat-bundle agent-bridge agent-bridge-fast cockpit cockpit-dev run headless ensure-socket restart-agent-server restart-agent-server-fast agent-ready agent-status agent-ping agent-methods agent-capabilities agent-self-test test-agent-offline control-smoke cockpit-smoke checkpoint-core test-checkpoint-core-unit test-task-health test-rpc-transaction test-ergonomics test-grep-diff-tooling test-runtime-determinism test-transaction-kernel test-harness-realism test-deterministic-retrieval test-agent-workflow-smoke test-agent-shell-tooling test-agent-shell-tooling-fast test-agent-shell-workflows test-agent-shell-workflows-fast test-authority-boundaries test-authority-boundaries-fast test-agent-bridge-authority test-cli-agent-failures test-docs-code-drift test-partial-success-closure test-broccoliq-runtime-memory test-broccoliq-runtime-memory-fast test-runtime-native-integration test-runtime-native-integration-fast test-agent-bridge test-agent-bridge-fast test-agent-integration sync-hermes-plugin enable-hermes-agent test-dietcode-enable-agent test-dietcode-agent-chat test-agent-chat-workspace-switch verify-agent-chat-sidebar smoke-agent-chat-live setup-hermes-bridge test-hermes-bridge-audit test-hermes-bridge-workflows hermes-ide-watchdog verify-hermes-bridge agent-integration verify-agent-runtime verify-agent-runtime-fast verify-agent-runtime-full verify-agent-runtime-full-fast benchmark-agent-success benchmark-agent-success-fast benchmark-agent-success-report test-agent-success-report test clean

all: kernel test

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(APP_MACOS):
	mkdir -p $(APP_MACOS)

$(APP_RESOURCES):
	mkdir -p $(APP_RESOURCES)

$(APP_BIN):
	mkdir -p $(APP_BIN)

$(KERNEL_RESOURCES):
	mkdir -p $(KERNEL_RESOURCES)

$(KERNEL_BIN):
	mkdir -p $(KERNEL_BIN)

agent-bridge-fast:
	cd $(AGENT_BRIDGE_DIR) && npm install --silent && npm run build

agent-bridge: agent-bridge-fast

$(PACKAGED_BRIDGE): agent-bridge-fast $(KERNEL_RESOURCES)
	rm -rf $(PACKAGED_BRIDGE)
	mkdir -p $(PACKAGED_BRIDGE)
	cp -R $(AGENT_BRIDGE_DIR)/dist $(PACKAGED_BRIDGE)/
	cp $(AGENT_BRIDGE_DIR)/package.json $(PACKAGED_BRIDGE)/

$(PACKAGED_BRIDGE_CLI): $(KERNEL_BIN) resources/bin/dietcode-agent-client
	cp resources/bin/dietcode-agent-client $(PACKAGED_BRIDGE_CLI)
	chmod +x $(PACKAGED_BRIDGE_CLI)

$(LEGACY_PACKAGED_BRIDGE): agent-bridge-fast $(APP_RESOURCES)
	rm -rf $(LEGACY_PACKAGED_BRIDGE)
	mkdir -p $(LEGACY_PACKAGED_BRIDGE)
	cp -R $(AGENT_BRIDGE_DIR)/dist $(LEGACY_PACKAGED_BRIDGE)/
	cp $(AGENT_BRIDGE_DIR)/package.json $(LEGACY_PACKAGED_BRIDGE)/

$(LEGACY_PACKAGED_BRIDGE_CLI): $(APP_BIN) resources/bin/dietcode-agent-client
	cp resources/bin/dietcode-agent-client $(LEGACY_PACKAGED_BRIDGE_CLI)
	chmod +x $(LEGACY_PACKAGED_BRIDGE_CLI)

$(PACKAGED_HERMES_PLUGIN): $(KERNEL_RESOURCES)
	@if [ ! -f "$(HERMES_PLUGIN_SRC)/plugin.yaml" ]; then \
		echo "→ Syncing Hermes plugin (first build)"; \
		./scripts/sync-hermes-plugin.sh; \
	fi
	rm -rf $(PACKAGED_HERMES_PLUGIN)
	mkdir -p $(PACKAGED_HERMES_PLUGIN)
	rsync -a --exclude broccolidb/node_modules --exclude broccolidb/scratch --exclude '__pycache__' --exclude '*.pyc' \
		$(HERMES_PLUGIN_SRC)/ $(PACKAGED_HERMES_PLUGIN)/

$(LEGACY_PACKAGED_HERMES_PLUGIN): $(APP_RESOURCES)
	@if [ ! -f "$(HERMES_PLUGIN_SRC)/plugin.yaml" ]; then \
		./scripts/sync-hermes-plugin.sh; \
	fi
	rm -rf $(LEGACY_PACKAGED_HERMES_PLUGIN)
	mkdir -p $(LEGACY_PACKAGED_HERMES_PLUGIN)
	rsync -a --exclude broccolidb/node_modules --exclude broccolidb/scratch --exclude '__pycache__' --exclude '*.pyc' \
		$(HERMES_PLUGIN_SRC)/ $(LEGACY_PACKAGED_HERMES_PLUGIN)/

$(LEGACY_PACKAGED_BUNDLE_MANIFEST): $(BUNDLE_MANIFEST_SRC) $(APP_RESOURCES)
	cp $(BUNDLE_MANIFEST_SRC) $(LEGACY_PACKAGED_BUNDLE_MANIFEST)

$(PACKAGED_ENABLE_AGENT): $(KERNEL_BIN) resources/bin/dietcode-enable-agent
	cp resources/bin/dietcode-enable-agent $(PACKAGED_ENABLE_AGENT)
	chmod +x $(PACKAGED_ENABLE_AGENT)

$(BUNDLE_MANIFEST_SRC): resources/Info.plist agent-bridge/package.json integrations/hermes-dietcode-plugin/plugin.yaml
	python3 scripts/generate_bundle_manifest.py -o $(BUNDLE_MANIFEST_SRC)

$(PACKAGED_BUNDLE_MANIFEST): $(BUNDLE_MANIFEST_SRC) $(KERNEL_RESOURCES)
	cp $(BUNDLE_MANIFEST_SRC) $(PACKAGED_BUNDLE_MANIFEST)

$(PACKAGED_ENABLE_AGENT_PY): scripts/dietcode_enable_agent.py $(KERNEL_BIN)
	cp scripts/dietcode_enable_agent.py $(PACKAGED_ENABLE_AGENT_PY)

$(PACKAGED_AGENT_CHAT): $(KERNEL_BIN) resources/bin/dietcode-agent-chat
	cp resources/bin/dietcode-agent-chat $(PACKAGED_AGENT_CHAT)
	chmod +x $(PACKAGED_AGENT_CHAT)

$(PACKAGED_AGENT_CHAT_PY): scripts/dietcode_agent_chat.py $(KERNEL_BIN)
	cp scripts/dietcode_agent_chat.py $(PACKAGED_AGENT_CHAT_PY)

$(PACKAGED_AGENT_BUNDLE_PY): scripts/dietcode_agent_bundle.py $(KERNEL_BIN)
	cp scripts/dietcode_agent_bundle.py $(PACKAGED_AGENT_BUNDLE_PY)

$(PACKAGED_MUTATION_AUTHORITY_PY): scripts/dietcode_mutation_authority.py $(KERNEL_BIN)
	cp scripts/dietcode_mutation_authority.py $(PACKAGED_MUTATION_AUTHORITY_PY)

$(PACKAGED_DIFF_AUTHORITY_PY): scripts/dietcode_diff_authority.py $(KERNEL_BIN)
	cp scripts/dietcode_diff_authority.py $(PACKAGED_DIFF_AUTHORITY_PY)

$(PACKAGED_VERIFICATION_AUTHORITY_PY): scripts/dietcode_verification_authority.py $(KERNEL_BIN)
	cp scripts/dietcode_verification_authority.py $(PACKAGED_VERIFICATION_AUTHORITY_PY)

sync-hermes-plugin:
	./scripts/sync-hermes-plugin.sh

enable-hermes-agent:
	./scripts/enable-hermes-agent.sh

$(KERNEL_BINARY): $(BUILD_DIR) $(KERNEL_SOURCES)
	$(CXX) $(KERNEL_OBJCXXFLAGS) $(KERNEL_SOURCES) -framework Cocoa -lsqlite3 -o $(KERNEL_BINARY)

$(APP_BINARY): $(APP_MACOS) $(LEGACY_SOURCES)
	$(CXX) $(OBJCXXFLAGS) $(LEGACY_SOURCES) -framework Cocoa -lsqlite3 -o $(APP_BINARY)

kernel: $(KERNEL_RESOURCES) $(KERNEL_BIN) $(KERNEL_BUNDLE)

agent-chat-bundle: $(KERNEL_BUNDLE)

app: kernel

legacy-app: $(APP_RESOURCES) $(APP_BIN) $(LEGACY_AGENT_CHAT_BUNDLE)
	cp resources/Info.plist $(APP_CONTENTS)/Info.plist
	if [ -f resources/AppIcon.icns ]; then cp resources/AppIcon.icns $(APP_RESOURCES)/AppIcon.icns; fi

cockpit-dev:
	cd cockpit && npm install && npm run dev

cockpit:
	cd cockpit && npm install && npm run build

run: legacy-app
	open $(APP_BUNDLE)

headless: kernel
	$(KERNEL_BINARY)

ensure-socket: kernel
	$(KERNEL_BINARY) --ensure-socket

restart-agent-server: kernel
	-pkill -f "$(KERNEL_BINARY)" 2>/dev/null || true
	-pkill -f "$(APP_MACOS)/$(APP_NAME)" 2>/dev/null || true
	sleep 0.5
	DIETCODE_REPO_ROOT=$(CURDIR) $(KERNEL_BINARY) --ensure-socket

# Restart agent server without rebuilding — assumes binary already matches HEAD.
restart-agent-server-fast:
	-pkill -f "$(KERNEL_BINARY)" 2>/dev/null || true
	-pkill -f "$(APP_MACOS)/$(APP_NAME)" 2>/dev/null || true
	sleep 0.5
	DIETCODE_REPO_ROOT=$(CURDIR) $(KERNEL_BINARY) --ensure-socket

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

test-coherence-tokens: restart-agent-server
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/test_coherence_tokens.py --compact

test-coherence-tokens-fast:
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/test_coherence_tokens.py --compact

coherence-recovery-smoke: restart-agent-server
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	DIETCODE_REPO_ROOT=$(CURDIR) PYTHONUNBUFFERED=1 python3 scripts/coherence_recovery_smoke.py --compact

coherence-recovery-smoke-fast:
	DIETCODE_REPO_ROOT=$(CURDIR) PYTHONUNBUFFERED=1 python3 scripts/coherence_recovery_smoke.py --compact

hermes-coherence-recovery-smoke: agent-bridge-fast restart-agent-server
	DIETCODE_REPO_ROOT=$(CURDIR) python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	DIETCODE_REPO_ROOT=$(CURDIR) PYTHONUNBUFFERED=1 python3 scripts/hermes_coherence_recovery_smoke.py --compact

hermes-coherence-recovery-smoke-fast: agent-bridge-fast
	DIETCODE_REPO_ROOT=$(CURDIR) PYTHONUNBUFFERED=1 python3 scripts/hermes_coherence_recovery_smoke.py --compact

coherence-core-v0.1: agent-bridge-fast
	$(MAKE) test-coherence-tokens
	$(MAKE) coherence-recovery-smoke-fast
	$(MAKE) hermes-coherence-recovery-smoke-fast
	$(MAKE) cockpit-smoke

test-ergonomics: app
	python3 scripts/dietcode_agent_client.py --wait-ready --compact --error-json --quiet
	python3 scripts/test_ergonomics.py --compact

test-agent-bridge-fast: agent-bridge-fast
	cd $(AGENT_BRIDGE_DIR) && npm run test:fast

test-agent-bridge-audit: app
	python3 scripts/test_agent_bridge_audit.py --compact

setup-hermes-bridge:
	./scripts/setup-hermes-bridge.sh

test-hermes-bridge-audit: agent-bridge-fast
	python3 scripts/test_hermes_bridge_audit.py --compact

test-hermes-bridge-workflows: agent-bridge-fast app
	python3 scripts/test_hermes_bridge_workflows.py --compact

hermes-ide-watchdog:
	chmod +x scripts/hermes-ide-watchdog.sh
	./scripts/hermes-ide-watchdog.sh

test-dietcode-enable-agent: agent-chat-bundle
	python3 scripts/test_dietcode_enable_agent.py

test-dietcode-agent-chat: agent-chat-bundle
	python3 scripts/test_dietcode_agent_chat.py

verify-agent-chat-sidebar: agent-chat-bundle
	python3 scripts/verify_agent_chat_sidebar.py

smoke-agent-chat-live: agent-bridge-fast $(PACKAGED_BRIDGE) $(KERNEL_BINARY) $(PACKAGED_AGENT_CHAT) $(PACKAGED_AGENT_CHAT_PY) $(PACKAGED_AGENT_BUNDLE_PY) $(PACKAGED_MUTATION_AUTHORITY_PY) $(PACKAGED_DIFF_AUTHORITY_PY) $(PACKAGED_VERIFICATION_AUTHORITY_PY) $(PACKAGED_ENABLE_AGENT_PY) $(PACKAGED_BUNDLE_MANIFEST) $(PACKAGED_BRIDGE_CLI)
	PYTHONUNBUFFERED=1 python3 scripts/smoke_agent_chat_live.py --compact

cockpit-smoke: kernel restart-agent-server-fast agent-bridge-fast cockpit
	DIETCODE_REPO_ROOT=$(CURDIR) DIETCODE_SESSION_DIR=$(CURDIR)/build/cockpit-smoke-session PYTHONUNBUFFERED=1 python3 scripts/cockpit_vertical_slice.py --compact

test-checkpoint-core-unit: cockpit
	python3 scripts/test_checkpoint_resolver.py
	cd cockpit && npx tsx --test server/checkpoints.test.ts server/sessionStore.test.ts

checkpoint-core: kernel agent-bridge-fast cockpit cockpit-smoke test-checkpoint-core-unit test-docs-code-drift
	@echo "checkpoint-core v0.1 — kernel, bridge, cockpit, vertical slice, unit tests, docs drift: OK"

test-agent-chat-workspace-switch: agent-bridge-fast $(PACKAGED_BRIDGE) $(KERNEL_BINARY) $(PACKAGED_AGENT_BUNDLE_PY) $(PACKAGED_BRIDGE_CLI)
	python3 scripts/test_agent_chat_workspace_switch.py

test-mutation-authority:
	python3 scripts/test_mutation_authority.py

test-diff-authority:
	python3 scripts/test_diff_authority.py

test-verification-authority:
	python3 scripts/test_verification_authority.py

verify-hermes-bridge: setup-hermes-bridge
	python3 scripts/test_hermes_bridge_audit.py --compact
	python3 scripts/test_hermes_bridge_workflows.py --compact
	python3 scripts/test_dietcode_enable_agent.py
	python3 scripts/test_dietcode_agent_chat.py
	python3 scripts/test_agent_chat_workspace_switch.py
	python3 scripts/test_mutation_authority.py
	python3 scripts/test_diff_authority.py
	python3 scripts/test_verification_authority.py
	python3 scripts/verify_agent_chat_sidebar.py
	python3 scripts/smoke_agent_chat_live.py --skip-live

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

# Runtime Contract Evaluation Ladder — nightmare tasks × agent profiles.
benchmark-contract-ladder: agent-bridge-fast
	DIETCODE_REPO_ROOT=$(CURDIR) python3 benchmarks/agent_success/run_contract_ladder.py --assume-server-ready

test-contract-ladder:
	python3 benchmarks/agent_success/test_contract_ladder.py

test-contract-orchestrator:
	python3 benchmarks/agent_success/test_contracts.py
	python3 benchmarks/agent_success/test_execution_protocols.py
	python3 benchmarks/agent_success/test_semantic_repair.py
	python3 benchmarks/agent_success/test_release_gates.py
	python3 benchmarks/agent_success/test_benchmark_schema.py
	python3 benchmarks/agent_success/test_isolation_audit.py
	python3 benchmarks/agent_success/test_security_boundaries.py
	python3 benchmarks/agent_success/test_external_agent_jail.py
	python3 benchmarks/agent_success/test_release_gate_negative.py

benchmark-contract-orchestrator: agent-bridge-fast
	DIETCODE_REPO_ROOT=$(CURDIR) python3 benchmarks/agent_success/run_orchestrator_benchmark.py --assume-server-ready

# Phase 4 — release gates: reference + orchestrated nightmare, mutation traces, escalation proofs.
benchmark-contract-release-check: agent-bridge-fast
	DIETCODE_REPO_ROOT=$(CURDIR) python3 benchmarks/agent_success/release_check.py --assume-server-ready

test-contract-release-gates:
	python3 benchmarks/agent_success/test_release_gates.py

# Phase 4.1 — schema stability, isolation, security, negative gates, replay verifier.
test-agent-benchmark-schema:
	python3 benchmarks/agent_success/test_benchmark_schema.py
	python3 benchmarks/agent_success/test_isolation_audit.py
	python3 benchmarks/agent_success/test_security_boundaries.py
	python3 benchmarks/agent_success/test_external_agent_jail.py
	python3 benchmarks/agent_success/test_release_gate_negative.py
	python3 benchmarks/agent_success/test_replay_trace.py

test-release-gate-negative:
	python3 benchmarks/agent_success/test_release_gate_negative.py

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
