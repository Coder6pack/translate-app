import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var inputEventMonitor: InputEventMonitor?
    private var translationCoordinator: TranslationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = TranslationCoordinator()
        let eventMonitor = InputEventMonitor { [weak coordinator] gesture in
            coordinator?.handle(gesture)
        }

        translationCoordinator = coordinator
        inputEventMonitor = eventMonitor
        statusBarController = StatusBarController { [weak eventMonitor, weak coordinator] isPaused in
            if isPaused {
                eventMonitor?.stop()
                coordinator?.cancel()
                coordinator?.clearCache()
            } else if PermissionManager.hasCoreAccess(prompt: true) {
                _ = eventMonitor?.start()
            }
        }

        if PermissionManager.hasCoreAccess(prompt: true) {
            _ = eventMonitor.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputEventMonitor?.stop()
        translationCoordinator?.cancel()
        translationCoordinator?.clearCache()
        statusBarController = nil
        inputEventMonitor = nil
        translationCoordinator = nil
    }
}
