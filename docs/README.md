# DietCode Documentation Index

Map of all documentation in `docs/`. For a project overview and quick start, see the [root README](../README.md).

```bash
make verify-agent-runtime-full     # docs stay aligned via test-docs-code-drift
rg 'CONTRACT:|INVARIANT:' docs/
```

---

## Start here

| Doc | When to read |
|-----|--------------|
| [Checkpoint Model](checkpoint-model.md) | **Canonical control plane** — six gates, feature map, noise audit |
| [Agent Ergonomics](agent-ergonomics.md) | Checkpoint query API, verify resolution, agent loop |
| [Kernel + Cockpit Architecture](kernel-cockpit-architecture.md) | Wiring diagram for kernel, bridge, cockpit |
| [Getting Started Tutorial](getting-started-tutorial.md) | First build, run, and UI change |
| [Build Instructions](build-instructions.md) | Compile and launch from source |
| [FAQ & Troubleshooting](faq-and-troubleshooting.md) | Build failures, socket issues, agent errors |
| [Agent Integration Cookbook](agent-integration-cookbook.md) | Python automation recipes |
| [Agent Bridge](agent-bridge.md) | Bundled TypeScript agent client (preferred for new agents) |
| [Testing Checklist](testing-checklist.md) | Pre-merge verification |

---

## Agent runtime (Passes I–VI)

The headless control surface is documented as a deterministic local transaction kernel. Start with the audit, then drill into contracts and operations.

| Doc | Contents |
|-----|----------|
| [Agent Runtime Audit](agent-runtime-audit.md) | **Canonical** Pass I–VI record: grep, determinism, transactions, harness realism, semantic removal, failure traps |
| [Headless Agent Control](headless-agent-control.md) | RPC method reference, CLI flags, partial-success model |
| [Agent Tooling](agent-tooling.md) | Grep/diff/patch/retrieval contracts and frozen key sets |
| [Runtime Invariants](runtime-invariants.md) | Stale writes, sort order, symlink policy, revision surfaces |
| [Runtime Contracts](runtime-contracts.md) | Contract IDs (`C-*`), versions, verification commands |
| [Error Codes](error-codes.md) | `string_code` catalog with `recovery_hint` and `nextRecommendedCommand` |
| [Agent Environment](agent-environment.md) | Config precedence and environment variables |
| [Deprecation Policy](deprecation-policy.md) | Quarantined surfaces (`search.semantic`, `analysis.searchRanked`) |

### Agent bridge (bundled TypeScript client)

| Doc | Contents |
|-----|----------|
| [Agent Bridge](agent-bridge.md) | Overview, public API, CLI, quick start |
| [Agent Bridge Architecture](agent-bridge-architecture.md) | Layers, transport, connect lifecycle, workflows |
| [Agent Bridge Integration Guide](agent-bridge-integration-guide.md) | TypeScript recipes, error handling, migration |
| [Agent Bridge Audit](agent-bridge-audit.md) | Pass I–II audit record and verification ladder |
| [Agent Chat Sidebar](agent-chat-sidebar.md) | Native Hermes chat UI; four-authority trust loop (workspace, mutation, diff, verification) |

### Verification and release

| Doc | Contents |
|-----|----------|
| [Build & Test System](build-and-test-system.md) | Makefile targets by pass, verification ladders |
| [Release Upgrade & Rollback](release-upgrade-rollback.md) | Rebuild, socket cleanup, release gates |
| [Maintainer Guide](maintainer-guide.md) | How to add RPC methods, error codes, enrichment, tool registry entries |

---

## Safety and operations

| Doc | Contents |
|-----|----------|
| [Runtime Safety](runtime-safety.md) | Socket hardening, size limits, abuse resistance |
| [Operator Policy](operator-policy.md) | Permission tiers, agent-safe vs internal namespaces |
| [Operator Diagnostics](operator-diagnostics.md) | Request correlation, NDJSON runtime log |
| [Task Server Recovery](task-server-recovery.md) | Socket and task lifecycle recovery |
| [Queue Contract](queue-contract.md) | Read vs execution queue affinity |
| [Trust and Safety Rules](trust-and-safety-rules.md) | Development security guidelines |

---

## Product and UX

| Doc | Contents |
|-----|----------|
| [Product Specification](product-spec.md) | Thesis, positioning, hard constraints |
| [MVP Scope](mvp-scope.md) | Phase 1 features and acceptance criteria |
| [Anti-Scope Checklist](anti-scope-checklist.md) | Features intentionally excluded |
| [UX Navigation Map](ux-navigation-map.md) | IDE layout and navigation flow |
| [Beginner Onboarding Flow](beginner-onboarding-flow.md) | First-run user guidance |
| [Accessibility Checklist](accessibility-checklist.md) | Accessibility standards and goals |
| [Visual Identity](visual-identity.md) | Brand guidelines and design language |
| [Command Catalog](command-catalog.md) | IDE commands and keyboard shortcuts |
| [Phase Roadmap](phase-roadmap.md) | Long-term milestones |

---

## Architecture and engineering

| Doc | Contents |
|-----|----------|
| [Technical Architecture](technical-architecture.md) | Layer model, domain logic, platform shell |
| [Technical Data Flow](technical-data-flow.md) | RPC lifecycle and async events |
| [File Structure](file-structure.md) | Repository layout (`control/`, `scripts/fixtures/`, harnesses) |
| [Editor Internals](editor-internals.md) | Line-based buffer, undo, tokenization |
| [Runtime Mechanics](runtime-mechanics.md) | Chip/Combo architecture, mutation locking |
| [Deterministic Combo Runtime Spec](deterministic-combo-runtime-spec.md) | Combo execution specification |
| [Event Orchestration](event-orchestration.md) | Internal event bus |
| [State & Configuration Management](state-and-config.md) | Preferences and transient state |
| [LSP Integration](lsp-integration.md) | Language server client |
| [Symbol Indexing Strategy](symbol-indexing-strategy.md) | Regex/brace-counting symbol parser |
| [Terminal & Process Management](terminal-process-management.md) | PTY and subprocess execution |
| [Filesystem & Git Integration](filesystem-and-git.md) | File watching and git state |
| [Performance Budget](performance-budget.md) | CPU, RAM, and binary size limits |
| [macOS Implementation Plan](macos-implementation-plan.md) | Platform-specific implementation notes |

---

## Expert deep dives

| Doc | Contents |
|-----|----------|
| [Tokenizer Logic](expert-tokenizer-logic.md) | Greedy regex, line-based tokenization |
| [Search Algorithms](expert-search-algorithms.md) | Substring search strategies |
| [Socket Server Architecture](expert-socket-server.md) | Threading, tokens, socket hardening |
| [Design Patterns & Governance](expert-governance.md) | PIMPL, observers, coding standards |

---

## Historical and planning

| Doc | Contents |
|-----|----------|
| [First Prototype Code Plan](first-prototype-code-plan.md) | Original vertical-slice strategy |
| [Navigation Audit](navigation-audit.md) | Keyboard and mouse navigation review |
| [Runtime release notes template](templates/runtime-release-notes.md) | Template for contract version bumps |

---

## Related resources outside `docs/`

| Path | Contents |
|------|----------|
| [`.wiki/index.md`](../.wiki/index.md) | Sovereign Knowledge Ledger — decision logs |
| [`scripts/agent_contracts.py`](../scripts/agent_contracts.py) | Frozen contract key sets (source of truth) |
| [`scripts/dietcode_agent_client.py`](../scripts/dietcode_agent_client.py) | Python RPC client and CLI |
| [`Makefile`](../Makefile) | Build and verification targets |

---

*When adding documentation for a new agent-runtime surface, update [Agent Runtime Audit](agent-runtime-audit.md), the relevant contract doc, and run `make test-docs-code-drift`.*
