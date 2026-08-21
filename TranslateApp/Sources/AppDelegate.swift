import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var inputEventMonitor: InputEventMonitor?
    private var translationCoordinator: TranslationCoordinator?
    private var settingsWindowController: SettingsWindowController?
    private var isTranslationPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsStore = SettingsStore()
        let coordinator = TranslationCoordinator(settingsStore: settingsStore)
        let eventMonitor = InputEventMonitor { [weak coordinator] gesture in
            coordinator?.handle(gesture)
        }
        let settingsController = SettingsWindowController(settingsStore: settingsStore)
        settingsStore.onTranslationSettingsChanged = { [weak coordinator] in
            coordinator?.cancel()
            coordinator?.clearCache()
        }

        translationCoordinator = coordinator
        inputEventMonitor = eventMonitor
        settingsWindowController = settingsController
        statusBarController = StatusBarController(
            onPauseChanged: { [weak self, weak eventMonitor, weak coordinator] isPaused in
                self?.isTranslationPaused = isPaused
                if isPaused {
                    eventMonitor?.stop()
                    coordinator?.cancel()
                    coordinator?.clearCache()
                } else if PermissionManager.hasCoreAccess(prompt: true) {
                    _ = eventMonitor?.start()
                }
            },
            onOpenSettings: { [weak settingsController] in
                settingsController?.showWindow()
            }
        )

        if PermissionManager.hasCoreAccess(prompt: true) {
            _ = eventMonitor.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputEventMonitor?.stop()
        translationCoordinator?.cancel()
        translationCoordinator?.clearCache()
        statusBarController = nil
        settingsWindowController = nil
        inputEventMonitor = nil
        translationCoordinator = nil
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let inputEventMonitor,
              !isTranslationPaused,
              !inputEventMonitor.isRunning,
              PermissionManager.hasCoreAccess(prompt: false) else {
            return
        }
        _ = inputEventMonitor.start()
    }
}
