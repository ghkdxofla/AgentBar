import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let viewModel = UsageViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
        statusBarController?.setup()
        viewModel.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopMonitoring()
    }
}
