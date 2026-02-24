# StayCell — Development Guide

## What This Is
A native macOS menubar app for deep work and distraction blocking. Unsandboxed, no Apple Developer account.

## Build
```bash
cd StayCell
xcodebuild -scheme StayCell -configuration Debug build
```

Two targets:
- **StayCell** — the main menubar app (SwiftUI + AppKit hybrid)
- **StayCellHelper** — privileged LaunchDaemon for /etc/hosts writes (runs as root, XPC)

## Architecture Decisions
- **NSStatusItem** (AppKit) for menubar — NOT SwiftUI `MenuBarExtra`
- **GRDB.swift** for persistence — NOT SwiftData
- **LaunchDaemon + XPC** for hosts writes — NOT osascript per mode switch
- **Native NSWindow overlay** for interception — NOT HTTP server
- **DispatchSource VNODE** for file monitoring — NOT polling
- **NSWorkspace notifications** for process detection — NOT polling
- **`0.0.0.0`** for blocked domains — NOT `127.0.0.1`
- **os.log / Logger** for logging — NOT print()

## Code Conventions
- Swift 6.2, strict concurrency (`complete`)
- macOS 15.0+ deployment target
- All errors use `StayCellError` enum with AI-debuggable format
- All system interactions event-driven (zero polling)
- Views < 200 lines; extract subviews
- `@MainActor` on all UI and state classes
- Shared types between targets go in `Shared/`

## Project Structure
```
StayCell/
├── StayCell/        — Main app target
│   ├── Core/        — AppState, engines (Mode, Timer, Blocking, Schedule)
│   ├── Models/      — GRDB records, Mode enum
│   ├── Views/       — MenuBarManager, popover, overlays, dashboard
│   ├── Services/    — XPCClient, watchers, location, audio
│   └── Utilities/   — Constants, errors, database, solar calculator
├── StayCellHelper/  — Privileged daemon target (root, XPC)
├── Shared/          — Types shared between both targets
└── Tests/           — Unit tests (Swift Testing framework)
```

## Key Files
- `StayCellApp.swift` — @main, AppDelegate with NSStatusItem
- `AppState.swift` — @Observable central state, UserDefaults persisted
- `Mode.swift` — Mode enum with blocking rules per category
- `Constants.swift` — Blocked domains, timer durations, override phrases
- `SharedConstants.swift` — Constants shared between app and daemon
- `XPCProtocol.swift` — @objc protocol for app↔daemon XPC
- `HostsFileManager.swift` — Atomic /etc/hosts writes with backup
- `MenuBarManager.swift` — NSStatusItem with colored dot + mode label
- `BlockingEngine.swift` — Coordinates mode→hosts via XPC

## Regenerating Xcode Project
```bash
cd StayCell && xcodegen generate
```
Uses `project.yml` (XcodeGen spec). Re-run after adding/removing files.
**IMPORTANT:** xcodegen overwrites `StayCell/StayCell.entitlements` to an empty dict every time. Restore the mach-lookup entitlement after each regeneration.

## Testing
Swift Testing framework (`@Suite`, `@Test`, `#expect`).
```bash
xcodebuild -scheme StayCell -configuration Debug test
```
