import XCTest
import AppKit
import SwiftUI
@testable import CCUsageBar

@MainActor
final class DetailPopoverViewTests: XCTestCase {

    func testDetailPopoverScrollsWhenUsageRowsOverflow() {
        let viewModel = UsageViewModel(providers: [])
        viewModel.usageData = makeUsageRows(count: 36)

        let rendered = renderPopover(viewModel: viewModel)
        let scrollView = findFirstScrollView(in: rendered.hostingView)

        XCTAssertNotNil(scrollView, "Expected a scroll view when usage data is present.")
        guard let scrollView else { return }

        let viewportHeight = scrollView.contentView.bounds.height
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        XCTAssertGreaterThan(
            documentHeight,
            viewportHeight,
            "Expected overflow rows to exceed the viewport so content is scrollable."
        )

        withExtendedLifetime(rendered.window) {}
    }

    func testDetailPopoverReservesSpaceOutsideScrollRegionForFooter() {
        let viewModel = UsageViewModel(providers: [])
        viewModel.usageData = makeUsageRows(count: 36)

        let rendered = renderPopover(viewModel: viewModel)
        let scrollView = findFirstScrollView(in: rendered.hostingView)

        XCTAssertNotNil(scrollView, "Expected a scroll view when usage data is present.")
        guard let scrollView else { return }

        let scrollFrame = scrollView.convert(scrollView.bounds, to: rendered.hostingView)
        let nonScrollHeight = rendered.hostingView.bounds.height - scrollFrame.height
        XCTAssertGreaterThan(
            nonScrollHeight,
            80,
            "Expected fixed header/footer chrome to remain visible outside the scroll region."
        )

        withExtendedLifetime(rendered.window) {}
    }

    private func makeUsageRows(count: Int) -> [UsageData] {
        let services = ServiceType.allCases
        return (0..<count).map { index in
            UsageData.mock(service: services[index % services.count])
        }
    }

    private func renderPopover(viewModel: UsageViewModel) -> (window: NSWindow, hostingView: NSHostingView<DetailPopoverView>) {
        let rootView = DetailPopoverView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        let frame = NSRect(x: 0, y: 0, width: 320, height: 480)
        hostingView.frame = frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        return (window, hostingView)
    }

    private func findFirstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for child in view.subviews {
            if let match = findFirstScrollView(in: child) {
                return match
            }
        }
        return nil
    }

}
