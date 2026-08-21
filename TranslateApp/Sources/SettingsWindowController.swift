import AppKit

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private var window: NSWindow?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    convenience override init() {
        self.init(settingsStore: SettingsStore())
    }

    func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentViewController = SettingsContentViewController(settingsStore: settingsStore)
        let window = NSWindow(contentViewController: contentViewController)
        window.title = "Translate App Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(contentViewController.view.fittingSize)
        window.delegate = self
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }
        window = nil
    }
}

@MainActor
private final class SettingsContentViewController: NSViewController {
    private let settingsStore: SettingsStore
    private let targetLanguageField = NSTextField()
    private let selectionCheckbox = NSButton(checkboxWithTitle: "Translate selected text", target: nil, action: nil)
    private let doubleClickCheckbox = NSButton(checkboxWithTitle: "Translate on double-click", target: nil, action: nil)
    private let singleClickCheckbox = NSButton(checkboxWithTitle: "Translate word on single-click", target: nil, action: nil)
    private let ocrCheckbox = NSButton(checkboxWithTitle: "Enable OCR fallback on demand", target: nil, action: nil)
    private let apiKeyField = NSSecureTextField()
    private let apiKeyStatusLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")
    private let permissionStatusLabel = NSTextField(labelWithString: "")

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let contentView = NSView()
        view = contentView

        targetLanguageField.stringValue = settingsStore.targetLanguage
        targetLanguageField.placeholderString = SettingsStore.defaultTargetLanguage
        targetLanguageField.target = self
        targetLanguageField.action = #selector(saveTargetLanguage)

        selectionCheckbox.state = settingsStore.isSelectionEnabled ? .on : .off
        doubleClickCheckbox.state = settingsStore.isDoubleClickEnabled ? .on : .off
        singleClickCheckbox.state = settingsStore.isSingleClickEnabled ? .on : .off
        ocrCheckbox.state = settingsStore.isOCREnabled ? .on : .off
        [selectionCheckbox, doubleClickCheckbox, singleClickCheckbox, ocrCheckbox].forEach {
            $0.target = self
            $0.action = #selector(saveCapturePreferences)
        }

        apiKeyField.placeholderString = "Google Cloud Translation API key"
        apiKeyStatusLabel.stringValue = settingsStore.hasGoogleAPIKey
            ? "A Google API key is configured."
            : "No Google API key is configured."

        launchAtLoginCheckbox.state = settingsStore.isLaunchAtLoginEnabled ? .on : .off
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(saveLaunchAtLoginPreference)

        let targetLanguageRow = NSStackView(views: [
            label("Target language code"),
            targetLanguageField,
            button(title: "Save", action: #selector(saveTargetLanguage))
        ])
        targetLanguageRow.orientation = .horizontal
        targetLanguageRow.alignment = .centerY
        targetLanguageRow.spacing = 12
        targetLanguageRow.setHuggingPriority(.required, for: .horizontal)

        let apiKeyActions = NSStackView(views: [
            button(title: "Save API Key", action: #selector(saveAPIKey)),
            button(title: "Remove API Key", action: #selector(removeAPIKey))
        ])
        apiKeyActions.orientation = .horizontal
        apiKeyActions.spacing = 8

        let permissionActions = NSStackView(views: [
            button(title: "Accessibility", action: #selector(openAccessibilitySettings)),
            button(title: "Input Monitoring", action: #selector(openInputMonitoringSettings)),
            button(title: "Screen Recording", action: #selector(openScreenRecordingSettings))
        ])
        permissionActions.orientation = .horizontal
        permissionActions.spacing = 8
        refreshPermissionStatus()

        let stack = NSStackView(views: [
            targetLanguageRow,
            separator(),
            selectionCheckbox,
            doubleClickCheckbox,
            singleClickCheckbox,
            ocrCheckbox,
            separator(),
            label("Google Cloud Translation"),
            apiKeyField,
            apiKeyActions,
            apiKeyStatusLabel,
            separator(),
            label("System Permissions"),
            permissionActions,
            permissionStatusLabel,
            separator(),
            launchAtLoginCheckbox,
            launchAtLoginStatusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(equalToConstant: 380),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            targetLanguageField.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
            apiKeyField.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func saveTargetLanguage() {
        do {
            try settingsStore.setTargetLanguage(targetLanguageField.stringValue)
            targetLanguageField.stringValue = settingsStore.targetLanguage
        } catch {
            presentError(error)
            targetLanguageField.stringValue = settingsStore.targetLanguage
        }
    }

    @objc private func saveCapturePreferences() {
        settingsStore.isSelectionEnabled = selectionCheckbox.state == .on
        settingsStore.isDoubleClickEnabled = doubleClickCheckbox.state == .on
        settingsStore.isSingleClickEnabled = singleClickCheckbox.state == .on
        if ocrCheckbox.state == .on {
            let granted = PermissionManager.hasScreenRecordingAccess(prompt: true)
            settingsStore.isOCREnabled = granted
            ocrCheckbox.state = granted ? .on : .off
        } else {
            settingsStore.isOCREnabled = false
        }
        refreshPermissionStatus()
    }

    @objc private func saveAPIKey() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            apiKeyStatusLabel.stringValue = "Enter a Google API key to save."
            return
        }

        do {
            try settingsStore.saveGoogleAPIKey(apiKey)
            apiKeyField.stringValue = ""
            apiKeyStatusLabel.stringValue = "Google API key saved."
        } catch {
            presentError(error)
        }
    }

    @objc private func removeAPIKey() {
        do {
            try settingsStore.removeGoogleAPIKey()
            apiKeyField.stringValue = ""
            apiKeyStatusLabel.stringValue = "Google API key removed."
        } catch {
            presentError(error)
        }
    }

    @objc private func saveLaunchAtLoginPreference() {
        let isEnabled = launchAtLoginCheckbox.state == .on
        do {
            try settingsStore.setLaunchAtLoginEnabled(isEnabled)
            let isActive = settingsStore.isLaunchAtLoginEnabled
            launchAtLoginCheckbox.state = isActive ? .on : .off
            launchAtLoginStatusLabel.stringValue = isActive || !isEnabled
                ? ""
                : "Launch at login needs approval in System Settings."
        } catch {
            launchAtLoginCheckbox.state = settingsStore.isLaunchAtLoginEnabled ? .on : .off
            presentError(error)
        }
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        return label
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    @objc private func openAccessibilitySettings() {
        PermissionManager.openSystemSettings(.accessibility)
    }

    @objc private func openInputMonitoringSettings() {
        PermissionManager.openSystemSettings(.inputMonitoring)
    }

    @objc private func openScreenRecordingSettings() {
        PermissionManager.openSystemSettings(.screenRecording)
    }

    private func refreshPermissionStatus() {
        let accessibility = PermissionManager.hasAccessibilityAccess(prompt: false)
            ? "Accessibility ✓" : "Accessibility required"
        let input = PermissionManager.hasInputMonitoringAccess(prompt: false)
            ? "Input ✓" : "Input required"
        let screen = PermissionManager.hasScreenRecordingAccess(prompt: false)
            ? "Screen ✓" : "Screen optional"
        permissionStatusLabel.stringValue = [accessibility, input, screen].joined(separator: "  •  ")
    }
}
