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
        registerLoginItemIfNeeded()
    }

    /// On first launch, register as a login item when the default is enabled.
    private func registerLoginItemIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "launchAtLogin"
        // Only act on first launch (key not yet written by user)
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(true, forKey: key)
        try? LoginItemManager.setEnabled(true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopMonitoring()
        notifyMonitor.stop()
    }
}
