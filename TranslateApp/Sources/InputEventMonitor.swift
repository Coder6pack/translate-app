import AppKit
import CoreGraphics

@MainActor
final class InputEventMonitor {
    private final class CallbackContext {
        weak var monitor: InputEventMonitor?

        init(monitor: InputEventMonitor) {
            self.monitor = monitor
        }
    }

    typealias Handler = @MainActor (MouseGesture) -> Void

    private let handler: Handler
    private let secondClickHandler: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callbackContext: UnsafeMutableRawPointer?
    private var mouseDownLocation: CGPoint?
    private var deliveryGeneration: UInt64 = 0

    init(
        handler: @escaping Handler,
        onSecondClick: @escaping @MainActor () -> Void
    ) {
        self.handler = handler
        secondClickHandler = onSecondClick
    }

    var isRunning: Bool {
        eventTap != nil
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard CGPreflightListenEventAccess() else {
            return false
        }

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let context = CallbackContext(monitor: self)
        let userInfo = Unmanaged.passRetained(context).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            Unmanaged<CallbackContext>.fromOpaque(userInfo).release()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        callbackContext = userInfo
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
        deliveryGeneration &+= 1
        if let callbackContext {
            Unmanaged<CallbackContext>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<CallbackContext>.fromOpaque(userInfo).takeUnretainedValue()
        guard let monitor = context.monitor else { return Unmanaged.passUnretained(event) }
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
            deliveryGeneration &+= 1
            mouseDownLocation = location
            if clickCount >= 2 {
                secondClickHandler()
            }

        case .leftMouseUp:
            let startLocation = mouseDownLocation ?? location
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
            let gesture = MouseGesture(kind: kind, startLocation: startLocation, location: location)
            let generation = deliveryGeneration
            Task { @MainActor [weak self, handler] in
                await Task.yield()
                guard self?.deliveryGeneration == generation else { return }
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
