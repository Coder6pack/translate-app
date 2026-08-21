import Foundation

@MainActor
final class TranslationCoordinator {
    private struct ActiveRequest {
        let id = UUID()
        let key: TranslationCache.Key
        var capture: TextCapture
    }

    private let textReader: AccessibilityTextReader
    private let translationClient: GoogleTranslationClient
    private let cache: TranslationCache
    private let keychainStore: KeychainStore
    private let panelController: TranslationPanelController
    private let settingsStore: SettingsStore
    private let ocrTextReader: OCRTextReader
    private let captureDelay: Duration
    private let debounceDuration: Duration
    private let maximumInputBytes = 20_000

    private var activeRequest: ActiveRequest?
    private var captureTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var cacheClearTask: Task<Void, Never>?
    private var captureGeneration: UInt64 = 0

    init(
        textReader: AccessibilityTextReader = AccessibilityTextReader(),
        translationClient: GoogleTranslationClient = GoogleTranslationClient(),
        cache: TranslationCache = TranslationCache(),
        keychainStore: KeychainStore = KeychainStore(),
        panelController: TranslationPanelController = TranslationPanelController(),
        settingsStore: SettingsStore,
        ocrTextReader: OCRTextReader = OCRTextReader(),
        captureDelay: Duration = .milliseconds(80),
        debounceDuration: Duration = .milliseconds(170)
    ) {
        self.textReader = textReader
        self.translationClient = translationClient
        self.cache = cache
        self.keychainStore = keychainStore
        self.panelController = panelController
        self.settingsStore = settingsStore
        self.ocrTextReader = ocrTextReader
        self.captureDelay = captureDelay
        self.debounceDuration = debounceDuration
        panelController.onDismiss = { [weak self] in
            self?.cancel()
        }
    }

    func handle(_ gesture: MouseGesture) {
        supersedeCurrentWork(hidePanel: true)
        guard settingsStore.isEnabled(for: gesture.kind) else { return }

        let generation = captureGeneration
        captureTask = Task { @MainActor [weak self, captureDelay] in
            do {
                try await Task.sleep(for: captureDelay)
            } catch {
                return
            }
            guard let self, isCurrentCapture(generation) else { return }
            var capture = await textReader.capture(for: gesture)
            guard isCurrentCapture(generation) else { return }
            if capture == nil,
               gesture.kind == .singleClick,
               settingsStore.isOCREnabled,
               PermissionManager.hasScreenRecordingAccess(prompt: false) {
                capture = await ocrTextReader.capture(for: gesture)
            }
            guard isCurrentCapture(generation), let capture else { return }
            captureTask = nil
            translate(capture)
        }
    }

    func translate(_ capture: TextCapture) {
        let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              text.utf8.count <= maximumInputBytes,
              !settingsStore.targetLanguage.isEmpty else {
            cancel()
            return
        }

        let key = TranslationCache.Key(text: text, targetLanguage: settingsStore.targetLanguage)
        if var activeRequest, activeRequest.key == key {
            activeRequest.capture = capture
            self.activeRequest = activeRequest
            panelController.showLoading(for: capture)
            return
        }

        cancelCurrentRequest(hidePanel: false)

        let request = ActiveRequest(
            key: key,
            capture: TextCapture(
                text: text,
                anchor: capture.anchor,
                bounds: capture.bounds,
                trigger: capture.trigger
            )
        )
        activeRequest = request
        panelController.showLoading(for: request.capture)

        translationTask = Task { @MainActor [weak self, debounceDuration] in
            do {
                try await Task.sleep(for: debounceDuration)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await self?.performTranslation(requestID: request.id, key: request.key)
        }
    }

    func cancel() {
        supersedeCurrentWork(hidePanel: true)
    }

    func clearCache() {
        let previousClear = cacheClearTask
        cacheClearTask = Task {
            if let previousClear {
                await previousClear.value
            }
            await cache.invalidate()
        }
    }

    func supersedePendingClick() {
        supersedeCurrentWork(hidePanel: true)
    }

    private func performTranslation(requestID: UUID, key: TranslationCache.Key) async {
        guard isCurrent(requestID) else { return }
        if let cacheClearTask {
            await cacheClearTask.value
        }
        guard !Task.isCancelled, isCurrent(requestID) else { return }
        let cacheEpoch = await cache.currentEpoch()

        if let cachedResult = await cache.value(for: key) {
            show(cachedResult, for: requestID)
            return
        }

        guard let apiKey = keychainStore.apiKey(), !apiKey.isEmpty else {
            show(TranslationError.missingAPIKey, for: requestID)
            return
        }

        do {
            let result = try await translationClient.translate(
                text: key.text,
                targetLanguage: key.targetLanguage,
                apiKey: apiKey
            )
            guard !Task.isCancelled, isCurrent(requestID) else { return }

            await cache.insert(result, for: key, ifEpochMatches: cacheEpoch)
            show(result, for: requestID)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            show(error, for: requestID)
        }
    }

    private func show(_ result: TranslationResult, for requestID: UUID) {
        guard let request = activeRequest, request.id == requestID else { return }
        translationTask = nil
        activeRequest = nil
        panelController.show(result, for: request.capture)
    }

    private func show(_ error: Error, for requestID: UUID) {
        guard let request = activeRequest, request.id == requestID else { return }
        translationTask = nil
        activeRequest = nil
        panelController.show(error: error, for: request.capture)
    }

    private func isCurrent(_ requestID: UUID) -> Bool {
        activeRequest?.id == requestID
    }

    private func isCurrentCapture(_ generation: UInt64) -> Bool {
        !Task.isCancelled && captureGeneration == generation
    }

    private func supersedeCurrentWork(hidePanel: Bool) {
        captureGeneration &+= 1
        captureTask?.cancel()
        captureTask = nil
        cancelCurrentRequest(hidePanel: hidePanel)
    }

    private func cancelCurrentRequest(hidePanel: Bool) {
        translationTask?.cancel()
        translationTask = nil
        activeRequest = nil
        if hidePanel {
            panelController.hide()
        }
    }
}
