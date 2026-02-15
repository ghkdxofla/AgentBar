import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let viewModel = UsageViewModel()
    private let alertMonitor = AgentAlertMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
        statusBarController?.setup()
        viewModel.startMonitoring()
        alertMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopMonitoring()
        alertMonitor.stop()
    }
}
