import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionManager {
    enum PrivacyPane: String {
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
        case screenRecording = "Privacy_ScreenCapture"
    }

    static func hasAccessibilityAccess(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func hasInputMonitoringAccess(prompt: Bool) -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        return prompt && CGRequestListenEventAccess()
    }

    static func hasScreenRecordingAccess(prompt: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return prompt && CGRequestScreenCaptureAccess()
    }

    static func hasCoreAccess(prompt: Bool) -> Bool {
        let accessibility = hasAccessibilityAccess(prompt: prompt)
        let inputMonitoring = hasInputMonitoringAccess(prompt: prompt)
        return accessibility && inputMonitoring
    }

    @MainActor
    static func openSystemSettings(_ pane: PrivacyPane) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
