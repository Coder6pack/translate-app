import Foundation
import ServiceManagement

@MainActor
final class SettingsStore {
    static let defaultTargetLanguage = "vi"

    private enum Key {
        static let targetLanguage = "targetLanguage"
        static let selectionEnabled = "selectionEnabled"
        static let doubleClickEnabled = "doubleClickEnabled"
        static let singleClickEnabled = "singleClickEnabled"
        static let ocrEnabled = "ocrEnabled"
    }

    private let defaults: UserDefaults
    private let keychainStore: KeychainStore
    var onTranslationSettingsChanged: (@MainActor () -> Void)?

    init(
        defaults: UserDefaults = .standard,
        keychainStore: KeychainStore = KeychainStore()
    ) {
        self.defaults = defaults
        self.keychainStore = keychainStore
        defaults.register(defaults: [
            Key.targetLanguage: Self.defaultTargetLanguage,
            Key.selectionEnabled: true,
            Key.doubleClickEnabled: true,
            Key.singleClickEnabled: true,
            Key.ocrEnabled: false
        ])
    }

    var targetLanguage: String {
        defaults.string(forKey: Key.targetLanguage) ?? Self.defaultTargetLanguage
    }

    var isSelectionEnabled: Bool {
        get { defaults.bool(forKey: Key.selectionEnabled) }
        set {
            guard newValue != isSelectionEnabled else { return }
            defaults.set(newValue, forKey: Key.selectionEnabled)
            onTranslationSettingsChanged?()
        }
    }

    var isDoubleClickEnabled: Bool {
        get { defaults.bool(forKey: Key.doubleClickEnabled) }
        set {
            guard newValue != isDoubleClickEnabled else { return }
            defaults.set(newValue, forKey: Key.doubleClickEnabled)
            onTranslationSettingsChanged?()
        }
    }

    var isSingleClickEnabled: Bool {
        get { defaults.bool(forKey: Key.singleClickEnabled) }
        set {
            guard newValue != isSingleClickEnabled else { return }
            defaults.set(newValue, forKey: Key.singleClickEnabled)
            onTranslationSettingsChanged?()
        }
    }

    var isOCREnabled: Bool {
        get { defaults.bool(forKey: Key.ocrEnabled) }
        set {
            guard newValue != isOCREnabled else { return }
            defaults.set(newValue, forKey: Key.ocrEnabled)
            onTranslationSettingsChanged?()
        }
    }

    var hasGoogleAPIKey: Bool {
        guard let apiKey = keychainStore.apiKey() else { return false }
        return !apiKey.isEmpty
    }

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var hasEnabledCaptureTrigger: Bool {
        isSelectionEnabled || isDoubleClickEnabled || isSingleClickEnabled
    }

    func setTargetLanguage(_ language: String) throws {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLanguage.isEmpty else {
            throw SettingsStoreError.emptyTargetLanguage
        }
        defaults.set(normalizedLanguage, forKey: Key.targetLanguage)
        onTranslationSettingsChanged?()
    }

    func saveGoogleAPIKey(_ apiKey: String) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw SettingsStoreError.emptyGoogleAPIKey
        }
        try keychainStore.saveAPIKey(trimmedAPIKey)
        onTranslationSettingsChanged?()
    }

    func removeGoogleAPIKey() throws {
        try keychainStore.removeAPIKey()
        onTranslationSettingsChanged?()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    func isEnabled(for trigger: MouseGesture.Kind) -> Bool {
        switch trigger {
        case .selection:
            isSelectionEnabled
        case .doubleClick:
            isDoubleClickEnabled
        case .singleClick:
            isSingleClickEnabled
        }
    }

    func setCapturePreferences(
        selectionEnabled: Bool,
        doubleClickEnabled: Bool,
        singleClickEnabled: Bool,
        ocrEnabled: Bool
    ) {
        let changed = selectionEnabled != isSelectionEnabled
            || doubleClickEnabled != isDoubleClickEnabled
            || singleClickEnabled != isSingleClickEnabled
            || ocrEnabled != isOCREnabled
        guard changed else { return }

        defaults.set(selectionEnabled, forKey: Key.selectionEnabled)
        defaults.set(doubleClickEnabled, forKey: Key.doubleClickEnabled)
        defaults.set(singleClickEnabled, forKey: Key.singleClickEnabled)
        defaults.set(ocrEnabled, forKey: Key.ocrEnabled)
        onTranslationSettingsChanged?()
    }
}

enum SettingsStoreError: LocalizedError {
    case emptyTargetLanguage
    case emptyGoogleAPIKey

    var errorDescription: String? {
        switch self {
        case .emptyTargetLanguage:
            "Enter a target language code."
        case .emptyGoogleAPIKey:
            "Enter a Google API key to save."
        }
    }
}
