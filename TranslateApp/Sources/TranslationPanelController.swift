import AppKit
import CoreGraphics

@MainActor
final class TranslationPanelController: NSObject {
    private enum State {
        case loading
        case result(TranslationResult)
        case error(String)
    }

    private let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "Translation")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private var translatedText: String?

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 148),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = makeContentView()
    }

    func showLoading(for capture: TextCapture) {
        apply(.loading)
        present(near: capture)
    }

    func show(_ result: TranslationResult, for capture: TextCapture) {
        apply(.result(result))
        present(near: capture)
    }

    func show(error: Error, for capture: TextCapture) {
        apply(.error(error.localizedDescription))
        present(near: capture)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func makeContentView() -> NSView {
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .labelColor
        messageLabel.maximumNumberOfLines = 5
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyTranslation)

        let footer = NSStackView(views: [NSView(), copyButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.views[0].setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, messageLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return background
    }

    private func apply(_ state: State) {
        switch state {
        case .loading:
            titleLabel.stringValue = "Translating"
            messageLabel.stringValue = "Translating…"
            translatedText = nil
            copyButton.isHidden = true

        case .result(let result):
            titleLabel.stringValue = result.detectedSourceLanguage.map {
                "Translation from \($0.uppercased())"
            } ?? "Translation"
            messageLabel.stringValue = result.translatedText
            translatedText = result.translatedText
            copyButton.title = "Copy"
            copyButton.isHidden = false

        case .error(let message):
            titleLabel.stringValue = "Translation unavailable"
            messageLabel.stringValue = message
            translatedText = nil
            copyButton.isHidden = true
        }
    }

    private func present(near capture: TextCapture) {
        panel.setContentSize(NSSize(width: 360, height: 148))
        panel.setFrameOrigin(panelOrigin(near: capture))
        panel.orderFrontRegardless()
    }

    private func panelOrigin(near capture: TextCapture) -> NSPoint {
        let anchor = capture.bounds.map { CGPoint(x: $0.maxX, y: $0.maxY) } ?? capture.anchor
        let point = appKitPoint(from: anchor)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return NSPoint(x: point.x + 8, y: point.y - panel.frame.height - 8)
        }

        let proposed = NSPoint(x: point.x + 8, y: point.y - panel.frame.height - 8)
        return NSPoint(
            x: min(max(proposed.x, visibleFrame.minX + 8), visibleFrame.maxX - panel.frame.width - 8),
            y: min(max(proposed.y, visibleFrame.minY + 8), visibleFrame.maxY - panel.frame.height - 8)
        )
    }

    private func appKitPoint(from point: CGPoint) -> NSPoint {
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return NSPoint(x: point.x, y: desktopTop - point.y)
    }

    @objc private func copyTranslation() {
        guard let translatedText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
        copyButton.title = "Copied"
    }
}
