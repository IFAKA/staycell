# Focus

A distraction-blocking app for macOS. Blocks websites when you're working, times your deep work sessions, tracks your financial independence progress, and enforces bedtime.

Lives in your menu bar. No account needed. All data stays on your Mac.

## Requirements

- macOS 15.0 or later
- Xcode 16.2 (to build from source — no App Store release)

## Install

Focus is not signed with an Apple Developer certificate. You'll need to build it yourself.

### 1. Build the app

```bash
cd Focus
xcodegen generate       # generates the Xcode project
```

Open `Focus/Focus.xcodeproj` in Xcode, select the **Focus** scheme, and press **Cmd+R** to build and run.

Or build from the terminal:

```bash
xcodebuild -scheme Focus -configuration Release build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/Focus-*/Build/Products/Release/Focus.app`. Copy it to `/Applications/`.

### 2. First launch — Gatekeeper warning

Because Focus is unsigned, macOS will block it on first launch:

1. Double-click Focus.app — you'll see "Focus can't be opened because it is from an unidentified developer"
2. Open **System Settings → Privacy & Security**
3. Scroll down — you'll see "Focus was blocked from use because it is not from an identified developer"
4. Click **Open Anyway**
5. Enter your password
6. Focus will launch and the onboarding wizard will start

You only need to do this once.

### 3. Onboarding

The app walks you through setup:

1. **Welcome** — explains what Focus does
2. **Install Helper** — Focus needs a background service to manage website blocking. You'll enter your Mac password once — Focus never asks again
3. **Browser DNS Check** — checks if your browser has "Secure DNS" enabled (this bypasses blocking). If it does, step-by-step instructions show you how to turn it off
4. **Location** — optional. Used to calculate sunrise/sunset for prayer time notifications and automatic bedtime. Skip if you don't want this
5. **Schedule** — set your work start time and work days

After setup, look for the colored dot in your menu bar (top-right corner of your screen).

## How it works

### Modes

Focus has four modes. Click the menu bar icon to switch between them:

| Mode | What's blocked | When to use |
|------|---------------|-------------|
| **Deep Work** (red) | Social, video, news, porn, gore | Focused coding/writing/thinking |
| **Shallow Work** (orange) | Same as deep work | Email, admin, meetings |
| **Personal** (green) | Porn and gore only | Browsing, YouTube, social media |
| **Offline** (purple) | Everything | Wind-down, sleep, total disconnect |

Blocked websites show a "cannot connect" error in your browser. This is normal — it means blocking is working.

### Sessions

Click the menu bar icon → **Deep Work** to start a 90-minute session. You'll be asked what you're working on (optional). The timer appears in your menu bar.

When the session ends, Focus automatically starts a 15-minute break. After the break, you choose when to start the next session.

### Override gate

If you try to visit a blocked site during a work session, a full-screen overlay appears with the Jesus Prayer and a prompt to do 10 pushups. After 5 seconds, a "Back to Work" button appears. After 30 seconds, an override option appears that requires typing a phrase and waiting 30+ seconds.

The app is designed to make distraction inconvenient, not impossible.

### Sleep enforcement

At night, Focus progressively:
- 60 min before bedtime: tightens blocking to Offline rules
- 30 min before: dims your screen
- At bedtime: full Offline mode, screen dimmed further
- 30 min after: persistent overlay

Bedtime = the earlier of (wake time + 16 hours) or 1:00 AM.

### FIRE tracker

Dashboard → FIRE tab. Enter monthly income, expenses, invested amount, and net worth. Focus calculates your savings rate, FIRE number (25x annual expenses), months to FIRE, and Coast FIRE number.

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+Opt+Cmd+D | Switch to Deep Work |
| Ctrl+Opt+Cmd+S | Switch to Shallow Work |
| Ctrl+Opt+Cmd+P | Switch to Personal |
| Ctrl+Opt+Cmd+O | Switch to Offline |

### Data export

Dashboard → Settings → Export All Data (JSON). Exports all sessions, overrides, and FIRE data.

## Known limitations

1. **Browser DNS bypass**: If your browser uses DNS-over-HTTPS (Secure DNS), website blocking won't work. The onboarding wizard checks for this and tells you how to fix it, but you have to do it manually.

2. **VPN bypass**: If you use a VPN, DNS requests go through the VPN and bypass /etc/hosts blocking. Focus can't prevent this without a Network Extension (which requires an Apple Developer account). Focus is a commitment device, not a security tool.

3. **Only works on Mac**: No phone app. Your phone is a separate problem.

4. **Unsigned app**: Gatekeeper will warn you on first launch. See install instructions above.

5. **Single Mac user**: The blocking helper runs system-wide, but session tracking is per-user.

## Uninstall

Dashboard → Settings → **Uninstall Focus Completely**.

This removes:
- The Focus helper daemon
- Restores your original /etc/hosts file
- Deletes all app data (database, logs, preferences)
- Removes Focus from login items

Then drag Focus.app to the Trash.

Focus stores data in exactly these locations:
- `~/Library/Application Support/Focus/` (database)
- `~/Library/Logs/Focus/` (logs)
- `~/Library/Preferences/com.focus.app.plist` (preferences)
- `/Library/LaunchDaemons/com.focus.helper.plist` (daemon config)
- `/Library/PrivilegedHelperTools/com.focus.helper` (daemon binary)

## Project structure

```
Focus/
├── Focus/           App target (menubar + SwiftUI dashboard)
│   ├── Core/        AppState, ModeEngine, TimerEngine, BlockingEngine, ScheduleEngine, SleepEngine
│   ├── Models/      GRDB records: Session, Override, DailyStats, FIRESnapshot, FocusMode
│   ├── Views/       MenuBar, Dashboard, Interception overlay, Onboarding, Settings
│   ├── Services/    XPC client, file watcher, wake detector, location, audio, shortcuts
│   └── Utilities/   Constants, Database, FIRE calculator, Solar calculator, Error types
├── FocusHelper/     LaunchDaemon target (runs as root, manages /etc/hosts)
├── Shared/          Code shared between app and daemon (XPC protocol, constants)
└── Tests/           Unit tests
```

Built with Swift 6.2, SwiftUI, GRDB.swift, and Swift Charts. No external services, no accounts, no cloud.
