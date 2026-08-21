import AppKit
import CoreGraphics

@MainActor
final class InputEventMonitor {
    typealias Handler = @MainActor (MouseGesture) -> Void

    private let handler: Handler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mouseDownLocation: CGPoint?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool {
        eventTap != nil
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else {
            return false
        }

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        guard let tap = eventTap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        mouseDownLocation = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<InputEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let typeValue = type.rawValue
        let location = event.location
        let clickCount = event.getIntegerValueField(.mouseEventClickState)

        MainActor.assumeIsolated {
            monitor.handle(typeValue: typeValue, location: location, clickCount: clickCount)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(typeValue: UInt32, location: CGPoint, clickCount: Int64) {
        guard let type = CGEventType(rawValue: typeValue) else { return }
        switch type {
        case .leftMouseDown:
            mouseDownLocation = location

        case .leftMouseUp:
            let dragDistance = mouseDownLocation.map { hypot(location.x - $0.x, location.y - $0.y) } ?? 0
            mouseDownLocation = nil

            let kind: MouseGesture.Kind
            if dragDistance >= 3 {
                kind = .selection
            } else if clickCount >= 2 {
                kind = .doubleClick
            } else {
                kind = .singleClick
            }
            let gesture = MouseGesture(kind: kind, location: location)
            Task { @MainActor [handler] in
                await Task.yield()
                handler(gesture)
            }

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

        default:
            break
        }
    }
}
