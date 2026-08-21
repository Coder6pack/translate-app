# Translate App

A lightweight macOS menu bar translator powered by Google Cloud Translation.

The app is intentionally native and event-driven: it remains idle until the
user selects or clicks text, reads text through macOS Accessibility APIs, and
shows the translation in a non-activating floating panel.

## Requirements

- macOS 14 or newer
- Xcode 26 or newer
- A Google Cloud Translation API key

## Build

```sh
xcodebuild -project TranslateApp.xcodeproj -scheme TranslateApp \
  -configuration Debug -derivedDataPath DerivedData build
```

The built app is available at
`DerivedData/Build/Products/Debug/TranslateApp.app`.
