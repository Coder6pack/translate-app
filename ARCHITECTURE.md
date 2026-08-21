# Architecture

Translate App is a single-process macOS menu bar agent. AppKit owns the app
lifecycle, global input monitoring, and the non-activating translation panel.
SwiftUI is reserved for settings views where it reduces boilerplate.

## Runtime flow

```text
CGEventTap
  -> SelectionCoordinator
  -> AccessibilityTextReader
  -> TranslationCache
  -> GoogleTranslationClient
  -> TranslationPanelController
```

The app does not poll the clipboard, selection, or screen. Work begins only in
response to a relevant mouse-up event. OCR is an on-demand fallback and is
disabled by default.

## Ownership

- `AppDelegate`: process lifecycle and dependency composition.
- `StatusBarController`: pause/resume, settings, and quit commands.
- `InputEventMonitor`: global mouse events without application activation.
- `AccessibilityTextReader`: selected text and text beneath the pointer.
- `SelectionCoordinator`: validation, deduplication, and cancellation.
- `GoogleTranslationClient`: the sole translation protocol implementation.
- `TranslationCache`: bounded in-memory LRU cache.
- `TranslationPanelController`: non-activating result presentation.
- `KeychainStore`: API credential persistence.
- `SettingsStore`: current user preferences.

There is one current translation request/response contract. The application
does not implement legacy formats, compatibility branches, or provider
abstractions without a second production provider.
