# Translate App

Translate App is a lightweight, native macOS menu bar utility that translates
selected text or the word beneath the pointer with Google Cloud Translation.
It is event-driven: there is no clipboard polling or repeating background job.

## Features

- Translate a mouse selection, double-click selection, or single-clicked word.
- Show the result in a non-activating popup near the captured text.
- Pause or resume capture from the menu bar.
- Keep the Google API key in macOS Keychain.
- Optionally use on-demand OCR when an app does not expose text through
  Accessibility.
- Optionally launch at login.

## Requirements

- macOS 14 or newer.
- Xcode 26 or newer to build the current project.
- Accessibility and Input Monitoring permission.
- A Google Cloud project with billing and the Cloud Translation API enabled.
- A Google Cloud Translation API key.

This repository currently publishes source code, not a notarized installer.

## Download the source

Download the current branch as a ZIP:

<https://github.com/Coder6pack/translate-app/archive/refs/heads/feat/macos-mvp.zip>

Alternatively, clone it with Git:

```sh
git clone https://github.com/Coder6pack/translate-app.git
cd translate-app
```

## Build and install

Build a Release app from the repository root:

```sh
xcodebuild -project TranslateApp.xcodeproj -scheme TranslateApp \
  -configuration Release -derivedDataPath DerivedData build
```

The result is written to:

```text
DerivedData/Build/Products/Release/TranslateApp.app
```

Copy it to Applications and launch it:

```sh
ditto DerivedData/Build/Products/Release/TranslateApp.app \
  /Applications/TranslateApp.app
open /Applications/TranslateApp.app
```

Translate App is a menu bar agent and does not appear in the Dock. Look for the
character-bubble icon in the menu bar.

## Configure Google Cloud Translation

1. Create or select a project in the
   [Google Cloud Console](https://console.cloud.google.com/).
2. Enable billing for that project.
3. Enable the
   [Cloud Translation API](https://console.cloud.google.com/apis/library/translate.googleapis.com).
4. Open [Credentials](https://console.cloud.google.com/apis/credentials), choose
   **Create credentials**, then **API key**.
5. Restrict the key to the Cloud Translation API.
6. In Translate App, open **Settings…** from the menu bar, paste the key, and
   choose **Save API Key**.

The app uses Cloud Translation Basic v2. Google documents its current setup,
billing, and pricing requirements in the
[Cloud Translation setup guide](https://cloud.google.com/translate/docs/setup).

## Grant macOS permissions

Open **Settings…** from the Translate App menu and use the permission buttons,
or navigate manually to **System Settings > Privacy & Security**:

1. Enable Translate App under **Accessibility**.
2. Enable Translate App under **Input Monitoring**.
3. Quit and reopen Translate App after changing either permission.

**Screen Recording** is optional and is required only when OCR fallback is
enabled. OCR is disabled by default.

The menu reports **Status: Running** only after required permissions are
available and the global event monitor starts successfully.

## Use

- Drag to select text and release the mouse button to translate the selection.
- Double-click a word to translate the selected word.
- Single-click a word to translate text exposed at that position.
- Press Escape or click elsewhere to dismiss the popup.
- Use **Pause Translation** in the menu to stop capture.

The target language defaults to Vietnamese (`vi`) and can be changed in
Settings using an ISO language code.

Some web canvases, images, protected documents, and applications that do not
expose text through macOS Accessibility cannot be read directly. Enable OCR
fallback for single-click capture in those cases. Secure text fields are never
captured.

## Privacy

Captured text is sent to Google Cloud Translation when a translation is
requested. The API key is stored in macOS Keychain. Translation results are
cached only in memory using bounded count and byte limits. OCR captures only a
small region around the pointer and does not retain screenshots.
