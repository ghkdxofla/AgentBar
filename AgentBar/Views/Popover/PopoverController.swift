import Cocoa
import SwiftUI

@MainActor
final class PopoverController {
    static let shared = PopoverController()

    private var popover: NSPopover?
    private var isShown = false

    private init() {}

    func toggle(relativeTo button: NSButton, viewModel: UsageViewModel) {
        if isShown {
            hide()
        } else {
            show(relativeTo: button, viewModel: viewModel)
        }
    }

    func show(relativeTo button: NSButton, viewModel: UsageViewModel) {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 350)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DetailPopoverView(viewModel: viewModel)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.delegate = PopoverDelegateHandler.shared
        self.popover = popover
        isShown = true
    }

    func hide() {
        popover?.performClose(nil)
        popover = nil
        isShown = false
    }
}

// Simple delegate to track popover closure
@MainActor
private final class PopoverDelegateHandler: NSObject, NSPopoverDelegate {
    static let shared = PopoverDelegateHandler()

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            PopoverController.shared.hide()
        }
    }
}
