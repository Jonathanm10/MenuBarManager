@preconcurrency import CoreGraphics
import Foundation

final class RealMenuBarEventTap {
    enum Location: Equatable {
        case hidEventTap
        case sessionEventTap
        case annotatedSessionEventTap
        case pid(pid_t)
    }

    struct Proxy {
        private let tap: RealMenuBarEventTap
        private let pointer: CGEventTapProxy

        var isEnabled: Bool {
            tap.isEnabled
        }

        fileprivate init(tap: RealMenuBarEventTap, pointer: CGEventTapProxy) {
            self.tap = tap
            self.pointer = pointer
        }

        func postEvent(_ event: CGEvent) {
            event.tapPostEvent(pointer)
        }

        func enable() {
            tap.enable()
        }

        func disable() {
            tap.disable()
        }
    }

    private let runLoop = CFRunLoopGetCurrent()
    private let mode: CFRunLoopMode = .commonModes
    private let callback: (
        RealMenuBarEventTap,
        CGEventTapProxy,
        CGEventType,
        CGEvent
    ) -> Unmanaged<CGEvent>?

    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?

    var isEnabled: Bool {
        guard let machPort else {
            return false
        }

        return CGEvent.tapIsEnabled(tap: machPort)
    }

    init?(
        options: CGEventTapOptions,
        location: Location,
        place: CGEventTapPlacement,
        types: [CGEventType],
        callback: @escaping (_ proxy: Proxy, _ type: CGEventType, _ event: CGEvent) -> CGEvent?
    ) {
        self.callback = { tap, pointer, type, event in
            callback(Proxy(tap: tap, pointer: pointer), type, event).map(Unmanaged.passUnretained)
        }

        guard let machPort = Self.createTapMachPort(
            location: location,
            place: place,
            options: options,
            eventsOfInterest: types.reduce(into: 0) { $0 |= 1 << $1.rawValue },
            callback: handleRealMenuBarEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return nil
        }
        guard let source = CFMachPortCreateRunLoopSource(nil, machPort, 0) else {
            CFMachPortInvalidate(machPort)
            return nil
        }

        self.machPort = machPort
        self.source = source
    }

    deinit {
        guard let machPort else {
            return
        }

        if let source {
            CFRunLoopRemoveSource(runLoop, source, mode)
        }
        CGEvent.tapEnable(tap: machPort, enable: false)
        CFMachPortInvalidate(machPort)
    }

    func enable() {
        guard let source, let machPort else {
            return
        }

        CFRunLoopAddSource(runLoop, source, mode)
        CGEvent.tapEnable(tap: machPort, enable: true)
    }

    func enable(timeout: Duration, onTimeout: @escaping () -> Void) {
        enable()
        let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
            if self?.isEnabled == true {
                onTimeout()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func disable() {
        guard let source, let machPort else {
            return
        }

        CFRunLoopRemoveSource(runLoop, source, mode)
        CGEvent.tapEnable(tap: machPort, enable: false)
    }

    fileprivate static func performCallback(
        for eventTap: RealMenuBarEventTap,
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        eventTap.callback(eventTap, proxy, type, event)
    }

    private static func createTapMachPort(
        location: Location,
        place: CGEventTapPlacement,
        options: CGEventTapOptions,
        eventsOfInterest: CGEventMask,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        if case .pid(let pid) = location {
            return CGEvent.tapCreateForPid(
                pid: pid,
                place: place,
                options: options,
                eventsOfInterest: eventsOfInterest,
                callback: callback,
                userInfo: userInfo
            )
        }

        let tap: CGEventTapLocation? = switch location {
        case .hidEventTap: .cghidEventTap
        case .sessionEventTap: .cgSessionEventTap
        case .annotatedSessionEventTap: .cgAnnotatedSessionEventTap
        case .pid: nil
        }

        guard let tap else {
            return nil
        }

        return CGEvent.tapCreate(
            tap: tap,
            place: place,
            options: options,
            eventsOfInterest: eventsOfInterest,
            callback: callback,
            userInfo: userInfo
        )
    }
}

extension RealMenuBarEventTap: @unchecked Sendable { }

private func handleRealMenuBarEvent(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passRetained(event)
    }

    let eventTap = Unmanaged<RealMenuBarEventTap>.fromOpaque(refcon).takeUnretainedValue()
    return RealMenuBarEventTap.performCallback(for: eventTap, proxy: proxy, type: type, event: event)
}
