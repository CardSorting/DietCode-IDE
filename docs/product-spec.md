# DietCode Product Specification

## Product thesis

DietCode is a smaller, calmer, native IDE for beginners, students, artists, workshop attendees, and developers who want a familiar coding environment without the compute tax of modern IDEs.

DietCode should feel instantly familiar to anyone who has seen VSCode, Visual Studio, Xcode, Sublime Text, or a modern code editor. It should remove startup drag, hidden background services, background indexing, telemetry, account systems, cloud defaults, AI defaults, extension-host complexity, and surprise CPU use while idle.

## Core promise

> Open. Code. Run. Save. No jet engine.

## Positioning

- VSCode, but diet.
- A quiet IDE for normal computers.
- Familiar enough for beginners.
- Small enough for one developer to understand.
- Local-first and offline-first.
- A coding workspace that respects attention, battery, RAM, and older laptops.

## Primary users

1. Beginners learning to code.
2. Students with low-powered laptops.
3. Workshop and event attendees who need fast onboarding.
4. Artists and creative coders who want a simple coding space.
5. Developers tired of bloated IDEs.
6. People who want familiar navigation without needing IDE architecture knowledge.
7. People intimidated by terminal-only tools.
8. People who want a local-first coding app.

## Product personality

DietCode is quiet, useful, slightly rebellious, friendly, local-first, anti-surprise-compute, and pro-craft. It is not anti-power-user, but it refuses to make beginners pay for advanced systems before they need them.

## Design principle

Familiar over novel.

DietCode should not invent a strange editor language. It should use proven IDE patterns: welcome screen, menu bar, activity bar, file sidebar, tabs, editor area, bottom panel, status bar, command palette, settings, search, and run controls.

## Hard constraints

- Modern C++20.
- Native desktop app.
- No Electron.
- No Chromium.
- No Qt.
- No SDL.
- No ImGui.
- No third-party dependencies in the MVP.
- No package manager required for MVP build.
- No telemetry.
- No account system.
- No AI by default.
- No extension host in v1.
- No background repo-wide indexing by default.
- No hidden daemons.
- No automatic cloud sync.
- No marketplace.
- No agent mode.
- No surprise CPU use while idle.

## Allowed dependencies

- C++ standard library.
- Operating system APIs.
- Platform-native UI, rendering, file dialogs, menus, fonts, accessibility, and process APIs.
- Platform build tools only.

## Target platforms

### Phase 1: macOS

Objective-C++ bridge using Cocoa/AppKit, native menus, native file dialogs, native text editing for the first vertical slice, and later CoreText/CoreGraphics for custom editor rendering.

### Phase 2: Windows

Win32 shell with DirectWrite text rendering, native menus, native file dialogs, and platform process APIs.

### Phase 3: Linux

Start terminal-first or with a minimal X11/Wayland shell later. Do not pretend true dependency-free cross-platform GUI is free.

## MVP product outcome

A user can launch DietCode, create or open a file, edit it, save it, see whether it is saved, find text, change a basic setting, and quit without losing work.

## Product quality bar

DietCode should feel calm, fast, familiar, clear, trustworthy, recoverable, beginner-safe, and professional enough for daily small-project use.

DietCode should not feel terminal-only, AI-first, cloud-first, enterprise-heavy, over-configured, theatrical, or like a framework demo.
