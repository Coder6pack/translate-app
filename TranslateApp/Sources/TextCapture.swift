import CoreGraphics

struct TextCapture: Sendable, Equatable {
    enum Trigger: Sendable {
        case selection
        case doubleClick
        case singleClick
    }

    let text: String
    let anchor: CGPoint
    let bounds: CGRect?
    let trigger: Trigger
}

struct MouseGesture: Sendable, Equatable {
    enum Kind: Sendable {
        case selection
        case doubleClick
        case singleClick
    }

    let kind: Kind
    let startLocation: CGPoint
    let location: CGPoint

    var dragBounds: CGRect {
        CGRect(
            x: min(startLocation.x, location.x),
            y: min(startLocation.y, location.y),
            width: abs(location.x - startLocation.x),
            height: abs(location.y - startLocation.y)
        )
    }
}
