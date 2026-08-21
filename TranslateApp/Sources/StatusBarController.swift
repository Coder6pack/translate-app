import AppKit

@MainActor
final class StatusBarController: NSObject {
    enum RuntimeState {
        case running
        case paused
        case disabled
        case blockedPermissions
        case startFailed
    }

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let pauseItem = NSMenuItem()
    private let statusLabelItem = NSMenuItem()
    private let onPauseChanged: @MainActor (Bool) -> Void
    private let onOpenSettings: @MainActor () -> Void
    private var runtimeState: RuntimeState = .startFailed

    init(
        onPauseChanged: @escaping @MainActor (Bool) -> Void,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        self.onPauseChanged = onPauseChanged
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "character.bubble",
            accessibilityDescription: "Translate App"
        )
        statusItem.button?.toolTip = "Translate App"

        pauseItem.title = "Pause Translation"
        pauseItem.target = self
        pauseItem.action = #selector(togglePaused)
        menu.addItem(pauseItem)
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Translate App",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        updateRuntimeState(.startFailed)
    }

    @objc private func togglePaused() {
        onPauseChanged(runtimeState != .paused)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    func updateRuntimeState(_ state: RuntimeState) {
        runtimeState = state

        let symbolName: String
        let description: String
        let statusText: String
        switch state {
        case .running:
            symbolName = "character.bubble"
            description = "Translate App running"
            statusText = "Status: Running"
        case .paused:
            symbolName = "pause.circle"
            description = "Translation paused"
            statusText = "Status: Paused"
        case .disabled:
            symbolName = "character.bubble.fill"
            description = "All translation triggers disabled"
            statusText = "Status: All triggers disabled"
        case .blockedPermissions:
            symbolName = "exclamationmark.triangle"
            description = "Translation permissions required"
            statusText = "Status: Permissions required"
        case .startFailed:
            symbolName = "exclamationmark.triangle.fill"
            description = "Translation monitor failed to start"
            statusText = "Status: Monitor failed to start"
        }

        pauseItem.title = state == .paused ? "Resume Translation" : "Pause Translation"
        statusLabelItem.title = statusText
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        )
        statusItem.button?.toolTip = description
    }
}
