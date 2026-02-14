import Cocoa
import SwiftUI
import Combine

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<StackedBarView>?
    private var cancellable: AnyCancellable?

    private let viewModel: UsageViewModel

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: 70)

        guard let button = statusItem?.button else { return }

        let barView = StackedBarView(services: viewModel.usageData)
        let hosting = NSHostingView(rootView: barView)
        hosting.frame = NSRect(x: 0, y: 0, width: 64, height: 22)

        button.frame = NSRect(x: 0, y: 0, width: 70, height: 22)
        button.addSubview(hosting)
        self.hostingView = hosting

        // Observe ViewModel changes
        cancellable = viewModel.$usageData
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                self?.hostingView?.rootView = StackedBarView(services: data)
            }

        // Click action — toggle popover
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        PopoverController.shared.toggle(relativeTo: button, viewModel: viewModel)
    }
}
