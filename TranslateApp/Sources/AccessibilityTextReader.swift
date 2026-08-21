import ApplicationServices
import CoreGraphics
import Foundation
import NaturalLanguage

actor AccessibilityTextReader {
    private let systemWideElement = AXUIElementCreateSystemWide()
    private let maximumFallbackTextLength = 5_000
    private let contextRadius = 128

    func capture(for gesture: MouseGesture) -> TextCapture? {
        switch gesture.kind {
        case .selection, .doubleClick:
            return selectedText(for: gesture, trigger: gesture.kind.captureTrigger)
        case .singleClick:
            return textAtPoint(gesture.location)
        }
    }

    private func selectedText(for gesture: MouseGesture, trigger: TextCapture.Trigger) -> TextCapture? {
        guard let focusedElement = focusedElement(),
              let pointedElement = element(at: gesture.location),
              sameApplication(focusedElement, pointedElement),
              !isSecure(focusedElement) else {
            return nil
        }
        guard let text = stringAttribute(kAXSelectedTextAttribute, of: focusedElement)?.trimmedForTranslation,
              !text.isEmpty,
              text.utf8.count <= maximumFallbackTextLength else {
            return nil
        }

        let selectionBounds = selectedTextBounds(of: focusedElement)
        guard selectionMatchesGesture(selectionBounds, gesture: gesture) else { return nil }

        return TextCapture(
            text: text,
            anchor: gesture.location,
            bounds: selectionBounds,
            trigger: trigger
        )
    }

    private func textAtPoint(_ point: CGPoint) -> TextCapture? {
        guard let element = element(at: point),
        !isSecure(element),
        let index = characterIndex(at: point, in: element),
        let context = textContext(around: index, in: element),
        let wordRange = Self.wordRange(in: context.text, utf16Index: index - context.range.location) else {
            return nil
        }

        let text = (context.text as NSString).substring(with: wordRange).trimmedForTranslation
        guard !text.isEmpty else { return nil }
        let documentWordRange = NSRange(
            location: context.range.location + wordRange.location,
            length: wordRange.length
        )

        return TextCapture(
            text: text,
            anchor: point,
            bounds: bounds(for: documentWordRange, in: element),
            trigger: .singleClick
        )
    }

    private func element(at point: CGPoint) -> AXUIElement? {
        var optionalElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &optionalElement
        ) == .success else {
            return nil
        }
        return optionalElement
    }

    private func sameApplication(_ first: AXUIElement, _ second: AXUIElement) -> Bool {
        var firstPID: pid_t = 0
        var secondPID: pid_t = 0
        return AXUIElementGetPid(first, &firstPID) == .success
            && AXUIElementGetPid(second, &secondPID) == .success
            && firstPID == secondPID
    }

    private func selectionMatchesGesture(_ bounds: CGRect?, gesture: MouseGesture) -> Bool {
        guard let bounds else { return false }
        switch gesture.kind {
        case .selection:
            return bounds.intersects(gesture.dragBounds.insetBy(dx: -12, dy: -12))
        case .doubleClick:
            return bounds.insetBy(dx: -12, dy: -12).contains(gesture.location)
        case .singleClick:
            return false
        }
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

    private func textContext(around index: Int, in element: AXUIElement) -> (text: String, range: NSRange)? {
        let totalLength = numberAttribute(kAXNumberOfCharactersAttribute, of: element)
        let start = max(0, index - contextRadius)
        let proposedEnd = index + contextRadius + 1
        let end = totalLength.map { min($0, proposedEnd) } ?? proposedEnd
        guard end > start else { return nil }

        let range = NSRange(location: start, length: end - start)
        if let text = string(for: range, in: element) {
            return (text, range)
        }

        guard let fullText = stringAttribute(kAXValueAttribute, of: element),
              fullText.utf16.count <= maximumFallbackTextLength else {
            return nil
        }
        return (fullText, NSRange(location: 0, length: fullText.utf16.count))
    }

    private func numberAttribute(_ attribute: String, of element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    private func string(for range: NSRange, in element: AXUIElement) -> String? {
        var mutableRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
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
        guard utf16Index >= 0, utf16Index < text.utf16.count else { return nil }
        let utf16View = text.utf16
        let offset = utf16View.index(utf16View.startIndex, offsetBy: utf16Index)
        guard let stringIndex = String.Index(offset, within: text) else { return nil }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let range = tokenizer.tokenRange(at: stringIndex)
        guard !range.isEmpty else { return nil }
        return NSRange(range, in: text)
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
