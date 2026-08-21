import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var inputEventMonitor: InputEventMonitor?
    private var translationCoordinator: TranslationCoordinator?
    private var settingsWindowController: SettingsWindowController?
    private var settingsStore: SettingsStore?
    private var isTranslationPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsStore = SettingsStore()
        let coordinator = TranslationCoordinator(settingsStore: settingsStore)
        let eventMonitor = InputEventMonitor(
            handler: { [weak coordinator] gesture in
                coordinator?.handle(gesture)
            },
            onSecondClick: { [weak coordinator] in
                coordinator?.supersedePendingClick()
            }
        )
        let settingsController = SettingsWindowController(settingsStore: settingsStore)
        settingsStore.onTranslationSettingsChanged = { [weak self, weak coordinator] in
            coordinator?.cancel()
            coordinator?.clearCache()
            self?.refreshMonitoring(promptForPermissions: false)
        }

        translationCoordinator = coordinator
        inputEventMonitor = eventMonitor
        settingsWindowController = settingsController
        self.settingsStore = settingsStore
        statusBarController = StatusBarController(
            onPauseChanged: { [weak self, weak coordinator] isPaused in
                self?.isTranslationPaused = isPaused
                if isPaused {
                    coordinator?.cancel()
                    coordinator?.clearCache()
                }
                self?.refreshMonitoring(promptForPermissions: !isPaused)
            },
            onOpenSettings: { [weak settingsController] in
                settingsController?.showWindow()
            }
        )

        refreshMonitoring(promptForPermissions: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputEventMonitor?.stop()
        translationCoordinator?.cancel()
        translationCoordinator?.clearCache()
        statusBarController = nil
        settingsWindowController = nil
        settingsStore = nil
        inputEventMonitor = nil
        translationCoordinator = nil
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        settingsWindowController?.refreshPermissionStatusIfVisible()
        refreshMonitoring(promptForPermissions: false)
    }

    private func refreshMonitoring(promptForPermissions: Bool) {
        guard let inputEventMonitor, let settingsStore, let statusBarController else {
            return
        }

        if isTranslationPaused {
            inputEventMonitor.stop()
            statusBarController.updateRuntimeState(.paused)
            return
        }
        guard settingsStore.hasEnabledCaptureTrigger else {
            inputEventMonitor.stop()
            translationCoordinator?.cancel()
            statusBarController.updateRuntimeState(.disabled)
            return
        }
        guard PermissionManager.hasCoreAccess(prompt: promptForPermissions) else {
            inputEventMonitor.stop()
            statusBarController.updateRuntimeState(.blockedPermissions)
            return
        }

        let started = inputEventMonitor.start()
        statusBarController.updateRuntimeState(started ? .running : .startFailed)
    }
}
