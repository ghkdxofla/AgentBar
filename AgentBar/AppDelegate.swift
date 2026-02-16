import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let viewModel = UsageViewModel()
    private let notifyMonitor = AgentNotifyMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
        statusBarController?.setup()
        viewModel.startMonitoring()
        notifyMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopMonitoring()
        notifyMonitor.stop()
    }
}
