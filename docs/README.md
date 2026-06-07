# DietCode Documentation Index

Welcome to the DietCode documentation. This directory contains detailed specifications, architectural overviews, and guides for the project.

## 🚀 Getting Started

- **[First Contribution Tutorial](getting-started-tutorial.md)**: A hands-on guide to building, running, and modifying DietCode.
- **[Agent Integration Cookbook](agent-integration-cookbook.md)**: Practical recipes and Python examples for building autonomous agents.
- **[Visual Identity](visual-identity.md)**: Brand guidelines and design language.
- **[FAQ & Troubleshooting](faq-and-troubleshooting.md)**: Solutions to common hurdles in setup and development.

## 📋 Product & UX
...
- **[Product Specification](product-spec.md)**: The core thesis, positioning, and hard constraints of DietCode.
- **[MVP Scope](mvp-scope.md)**: Defines what is included in the Minimum Viable Product.
- **[Anti-Scope Checklist](anti-scope-checklist.md)**: A list of features we intentionally exclude to maintain a "diet" footprint.
- **[UX Navigation Map](ux-navigation-map.md)**: The layout and flow of the IDE's interface.
- **[Beginner Onboarding Flow](beginner-onboarding-flow.md)**: How we guide new users through their first experience.
- **[Accessibility Checklist](accessibility-checklist.md)**: Standards and goals for making DietCode usable by everyone.

## 🏗️ Architecture & Engineering

- **[Technical Architecture](technical-architecture.md)**: Layer models, domain logic, and platform shell strategy.
- **[Technical Data Flow](technical-data-flow.md)**: Visualizing the lifecycle of RPC calls and asynchronous events.
- **[Editor Internals](editor-internals.md)**: Deep dive into the line-based buffer, undo stack, and tokenization.
- **[Runtime Mechanics](runtime-mechanics.md)**: Details on the Chip/Combo architecture, mutation locking, and safety rollbacks.
- **[LSP Integration](lsp-integration.md)**: How the custom client manages Language Servers for diagnostics and navigation.
- **[Event Orchestration](event-orchestration.md)**: The asynchronous Event Bus for decoupled internal communication.
- **[State & Configuration Management](state-and-config.md)**: Persistence of user preferences and transient application state.
- **[Symbol Indexing Strategy](symbol-indexing-strategy.md)**: The "diet" regex/brace-counting parser and reference scoring.
- **[Terminal & Process Management](terminal-process-management.md)**: Native PTY integration and subprocess execution.
- **[Filesystem & Git Integration](filesystem-and-git.md)**: Native file watching and git repository state tracking.
- **[File Structure](file-structure.md)**: Detailed breakdown of the repository's directory layout.
- **[Performance Budget](performance-budget.md)**: Constraints on CPU, RAM, and binary size.
- **[MacOS Implementation Plan](macos-implementation-plan.md)**: Platform-specific details for the primary target.
- **[Headless Agent Control](headless-agent-control.md)**: Deep dive into the JSON-RPC socket interface for automation.
- **[Deterministic Combo Runtime Spec](deterministic-combo-runtime-spec.md)**: Specification for the command execution runtime.

## 🎓 Expert-Tier Deep Dives

- **[Tokenizer Logic](expert-tokenizer-logic.md)**: Greedy regex matching and stateless line-based tokenization.
- **[Search Algorithms](expert-search-algorithms.md)**: Optimized substring search and case-insensitivity strategies.
- **[Socket Server Architecture](expert-socket-server.md)**: Threading models, security tokens, and socket hardening.
- **[Design Patterns & Governance](expert-governance.md)**: PIMPL, asynchronous observers, and project coding standards.

## 🛠️ Developer Guides

- **[Build Instructions](build-instructions.md)**: How to compile, test, and run DietCode from source.
- **[Build & Test System](build-and-test-system.md)**: Detailed overview of the Makefile targets and zero-dependency testing.
- **[Command Catalog](command-catalog.md)**: A list of supported IDE commands and their keyboard shortcuts.
- **[Testing Checklist](testing-checklist.md)**: How to verify changes and maintain the stability of the core.
- **[Phase Roadmap](phase-roadmap.md)**: The long-term plan for project milestones.
- **[Trust and Safety Rules](trust-and-safety-rules.md)**: Security guidelines for development.

## 💡 Other Resources

- **[First Prototype Code Plan](first-prototype-code-plan.md)**: The original implementation strategy for the vertical slice.
- **[Navigation Audit](navigation-audit.md)**: A review of the keyboard and mouse navigation patterns.

---

*For historical context and internal decision logs, see the [Sovereign Knowledge Ledger](../.wiki/index.md) in the `.wiki` directory.*
