import ApplicationServices
import CoreGraphics
import Foundation

final class AccessibilityTextReader {
    private let systemWideElement = AXUIElementCreateSystemWide()

    static func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func capture(for gesture: MouseGesture) -> TextCapture? {
        switch gesture.kind {
        case .selection, .doubleClick:
            return selectedText(anchor: gesture.location, trigger: gesture.kind.captureTrigger)
        case .singleClick:
            return textAtPoint(gesture.location)
        }
    }

    private func selectedText(anchor: CGPoint, trigger: TextCapture.Trigger) -> TextCapture? {
        guard let element = focusedElement(), !isSecure(element) else { return nil }
        guard let text = stringAttribute(kAXSelectedTextAttribute, of: element)?.trimmedForTranslation,
              !text.isEmpty else {
            return nil
        }

        return TextCapture(
            text: text,
            anchor: anchor,
            bounds: selectedTextBounds(of: element),
            trigger: trigger
        )
    }

    private func textAtPoint(_ point: CGPoint) -> TextCapture? {
        var optionalElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &optionalElement
        ) == .success,
        let element = optionalElement,
        !isSecure(element),
        let fullText = stringAttribute(kAXValueAttribute, of: element),
        let index = characterIndex(at: point, in: element),
        let wordRange = Self.wordRange(in: fullText, utf16Index: index) else {
            return nil
        }

        let text = (fullText as NSString).substring(with: wordRange).trimmedForTranslation
        guard !text.isEmpty else { return nil }

        return TextCapture(
            text: text,
            anchor: point,
            bounds: bounds(for: wordRange, in: element),
            trigger: .singleClick
        )
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return (value as! AXUIElement?)
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        stringAttribute(kAXSubroleAttribute, of: element) == kAXSecureTextFieldSubrole as String
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func selectedTextBounds(of element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success else {
            return nil
        }
        return cgRect(from: boundsValue)
    }

    private func characterIndex(at point: CGPoint, in element: AXUIElement) -> Int? {
        var mutablePoint = point
        guard let pointValue = AXValueCreate(.cgPoint, &mutablePoint) else { return nil }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXRangeForPositionParameterizedAttribute as CFString,
            pointValue,
            &rangeValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location >= 0 else {
            return nil
        }
        return range.location
    }

    private func bounds(for range: NSRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success else {
            return nil
        }
        return cgRect(from: boundsValue)
    }

    private func cgRect(from value: CFTypeRef?) -> CGRect? {
        guard let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func wordRange(in text: String, utf16Index: Int) -> NSRange? {
        let source = text as NSString
        guard source.length > 0, utf16Index >= 0, utf16Index < source.length else { return nil }

        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        var start = utf16Index
        var end = utf16Index

        if UnicodeScalar(source.character(at: utf16Index)).map(separators.contains) == true {
            return nil
        }
        while start > 0,
              UnicodeScalar(source.character(at: start - 1)).map(separators.contains) == false {
            start -= 1
        }
        while end + 1 < source.length,
              UnicodeScalar(source.character(at: end + 1)).map(separators.contains) == false {
            end += 1
        }
        return NSRange(location: start, length: end - start + 1)
    }
}

private extension MouseGesture.Kind {
    var captureTrigger: TextCapture.Trigger {
        switch self {
        case .selection: .selection
        case .doubleClick: .doubleClick
        case .singleClick: .singleClick
        }
    }
}

private extension String {
    var trimmedForTranslation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
