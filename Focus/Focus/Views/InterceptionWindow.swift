import AppKit
import SwiftUI
import os.log

/// Full-screen monastic overlay shown when a blocked site is attempted.
/// Covers ALL screens. Appears above full-screen apps.
/// Design: near-black background, cream EB Garamond, zero chrome.
@MainActor
final class InterceptionWindowManager {
    private var windows: [NSWindow] = []
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "interception")

    var onDismiss: (() -> Void)?
    var onOverrideRequested: (() -> Void)?

    /// When true, overlays are suppressed (e.g., during a presentation or call).
    var suppressOverlays = false

    /// Show the interception overlay on all screens.
    func show() {
        guard windows.isEmpty else { return }
        guard !suppressOverlays else {
            logger.info("Overlay suppressed — presentation/call active")
            return
        }

        for screen in NSScreen.screens {
            let window = createWindow(for: screen)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        logger.info("Interception overlay shown on \(NSScreen.screens.count) screen(s)")
    }

    /// Dismiss all overlay windows.
    func dismiss() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
        onDismiss?()
        logger.info("Interception overlay dismissed")
    }

    var isShowing: Bool {
        !windows.isEmpty
    }

    // MARK: - Private

    private func createWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = false
        window.backgroundColor = NSColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1.0) // #0D0D0D

        let contentView = InterceptionContentView(
            onBackToWork: { [weak self] in
                self?.dismiss()
            },
            onOverride: { [weak self] in
                self?.dismiss()
                self?.onOverrideRequested?()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)

        return window
    }
}

/// The SwiftUI content of the interception overlay.
/// Monastic minimalism: prayer text, pushup prompt, timed buttons.
struct InterceptionContentView: View {
    let onBackToWork: () -> Void
    let onOverride: () -> Void

    @State private var showBackToWork = false
    @State private var showOverrideLink = false
    @State private var elapsedSeconds = 0

    // Cream/gold color for text
    private let creamColor = Color(red: 0.96, green: 0.93, blue: 0.85)
    private let subtleColor = Color(red: 0.5, green: 0.48, blue: 0.42)

    var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // The Jesus Prayer
                Text("Lord Jesus Christ,")
                    .font(.system(size: 32, weight: .light, design: .serif))
                    .foregroundStyle(creamColor)

                Text("Son of God,")
                    .font(.system(size: 32, weight: .light, design: .serif))
                    .foregroundStyle(creamColor)
                    .padding(.top, 4)

                Text("have mercy on me, a sinner.")
                    .font(.system(size: 32, weight: .light, design: .serif))
                    .foregroundStyle(creamColor)
                    .padding(.top, 4)

                // Action prompt
                Text("Stand up. 10 pushups. Then return.")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(subtleColor)
                    .padding(.top, 48)

                Spacer()

                // Back to Work button (appears after 5 seconds)
                if showBackToWork {
                    Button {
                        onBackToWork()
                    } label: {
                        Text("Back to Work")
                            .font(.system(size: 14, weight: .medium, design: .serif))
                            .foregroundStyle(creamColor.opacity(0.7))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(creamColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }

                // Override link (appears after 30 seconds, barely visible)
                if showOverrideLink {
                    Button {
                        onOverride()
                    } label: {
                        Text("I need to override this")
                            .font(.system(size: 11, design: .serif))
                            .foregroundStyle(subtleColor.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    .transition(.opacity)
                }

                Spacer()
                    .frame(height: 80)
            }
        }
        .onAppear {
            startTimers()
        }
    }

    private func startTimers() {
        // Show "Back to Work" after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(.easeIn(duration: 0.5)) {
                showBackToWork = true
            }
        }

        // Show override link after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            withAnimation(.easeIn(duration: 0.5)) {
                showOverrideLink = true
            }
        }
    }
}
