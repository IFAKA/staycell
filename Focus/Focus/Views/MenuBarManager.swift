import AppKit
import SwiftUI
import os.log

/// Manages the NSStatusItem in the macOS menu bar.
/// Uses AppKit directly for full control over timer updates.
@MainActor
final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState: AppState
    private let blockingEngine: BlockingEngine
    private let logger = Logger.app

    init(appState: AppState, blockingEngine: BlockingEngine) {
        self.appState = appState
        self.blockingEngine = blockingEngine
        super.init()
    }

    func setup() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        updateStatusItemDisplay()

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover(appState: appState, blockingEngine: blockingEngine)
        )
        self.popover = popover

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    func updateStatusItemDisplay() {
        guard let button = statusItem?.button else { return }

        let mode = appState.currentMode

        let dotColor: NSColor = switch mode {
        case .deepWork: .systemRed
        case .shallowWork: .systemOrange
        case .personalTime: .systemGreen
        case .offline: .systemPurple
        }

        let attributed = NSMutableAttributedString()

        let dot = NSAttributedString(
            string: "\u{25CF} ",
            attributes: [
                .foregroundColor: dotColor,
                .font: NSFont.systemFont(ofSize: 12),
            ]
        )
        attributed.append(dot)

        let label = NSAttributedString(
            string: mode.shortName,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            ]
        )
        attributed.append(label)

        button.attributedTitle = attributed
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }
}
