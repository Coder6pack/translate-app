import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let pauseItem = NSMenuItem()
    private let onPauseChanged: @MainActor (Bool) -> Void
    private let onOpenSettings: @MainActor () -> Void
    private var isPaused = false

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
    }

    @objc private func togglePaused() {
        isPaused.toggle()
        pauseItem.title = isPaused ? "Resume Translation" : "Pause Translation"
        statusItem.button?.image = NSImage(
            systemSymbolName: isPaused ? "character.bubble.fill" : "character.bubble",
            accessibilityDescription: isPaused ? "Translation paused" : "Translate App"
        )
        onPauseChanged(isPaused)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
