import AppKit
import CoreGraphics
import Foundation

struct RealMenuBarItemMoveResult {
    let requestedWindowID: CGWindowID
    let targetWindowID: CGWindowID
    let startFrame: CGRect
    let destination: CGPoint
    let mouseDownAcknowledged: Bool
    let mouseDragAcknowledged: Bool
    let mouseUpAcknowledged: Bool
    let finalSnapshot: RealMenuBarItemSnapshot?
    let errorReason: String?

    var frameChanged: Bool {
        guard let finalSnapshot else {
            return false
        }

        return abs(finalSnapshot.frame.minX - startFrame.minX) > 0.5
            || abs(finalSnapshot.frame.maxX - startFrame.maxX) > 0.5
    }

    var becameHidden: Bool {
        finalSnapshot?.isOnScreen == false
    }

    var dictionary: [String: Any] {
        [
            "requestedWindowID": Int(requestedWindowID),
            "targetWindowID": Int(targetWindowID),
            "startFrame": dictionary(from: startFrame),
            "destination": dictionary(from: CGRect(x: destination.x, y: destination.y, width: 0, height: 0)),
            "mouseDownAcknowledged": mouseDownAcknowledged,
            "mouseDragAcknowledged": mouseDragAcknowledged,
            "mouseUpAcknowledged": mouseUpAcknowledged,
            "frameChanged": frameChanged,
            "becameHidden": becameHidden,
            "finalSnapshot": finalSnapshot?.dictionary ?? [:],
            "errorReason": errorReason ?? "",
        ]
    }

    private func dictionary(from rect: CGRect) -> [String: Double] {
        [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.width,
            "height": rect.height,
            "minX": rect.minX,
            "maxX": rect.maxX,
            "minY": rect.minY,
            "maxY": rect.maxY,
            "midX": rect.midX,
            "midY": rect.midY,
        ]
    }
}

@MainActor
enum RealMenuBarItemMover {
    static func move(
        _ item: RealMenuBarItemSnapshot,
        to destination: CGPoint,
        targetItem: RealMenuBarItemSnapshot
    ) async -> RealMenuBarItemMoveResult {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return result(
                item: item,
                targetItem: targetItem,
                destination: destination,
                mouseDownAcknowledged: false,
                mouseDragAcknowledged: false,
                mouseUpAcknowledged: false,
                errorReason: "missing CGEventSource"
            )
        }

        configureSuppression(on: source)

        guard let mouseDown = CGEvent.menuBarMoveEvent(
            type: .leftMouseDown,
            location: CGPoint(x: item.frame.midX, y: item.frame.midY),
            item: item,
            targetPID: item.ownerPID,
            source: source
        ), let mouseDragged = CGEvent.menuBarMoveEvent(
            type: .leftMouseDragged,
            location: destination,
            item: item,
            targetPID: item.ownerPID,
            source: source
        ), let mouseUp = CGEvent.menuBarMoveEvent(
            type: .leftMouseUp,
            location: destination,
            item: targetItem,
            targetPID: item.ownerPID,
            source: source
        ) else {
            return result(
                item: item,
                targetItem: targetItem,
                destination: destination,
                mouseDownAcknowledged: false,
                mouseDragAcknowledged: false,
                mouseUpAcknowledged: false,
                errorReason: "failed to create CGEvents"
            )
        }

        var lastResult: RealMenuBarItemMoveResult?

        for attempt in 1...5 {
            let mouseDownAcknowledged = await scrombleEvent(
                mouseDown,
                from: .pid(item.ownerPID),
                to: .sessionEventTap
            )
            try? await Task.sleep(for: .milliseconds(80))
            let mouseDragAcknowledged = await scrombleEvent(
                mouseDragged,
                from: .pid(item.ownerPID),
                to: .sessionEventTap
            )
            try? await Task.sleep(for: .milliseconds(120))
            let mouseUpAcknowledged = await scrombleEvent(
                mouseUp,
                from: .pid(item.ownerPID),
                to: .sessionEventTap
            )
            let finalSnapshot = await waitForFrameChange(
                windowID: item.windowID,
                initialFrame: item.frame,
                timeout: .milliseconds(500)
            )
            let result = RealMenuBarItemMoveResult(
                requestedWindowID: item.windowID,
                targetWindowID: targetItem.windowID,
                startFrame: item.frame,
                destination: destination,
                mouseDownAcknowledged: mouseDownAcknowledged,
                mouseDragAcknowledged: mouseDragAcknowledged,
                mouseUpAcknowledged: mouseUpAcknowledged,
                finalSnapshot: finalSnapshot ?? RealMenuBarItemReader.snapshot(windowID: item.windowID),
                errorReason: mouseDownAcknowledged && mouseDragAcknowledged && mouseUpAcknowledged
                    ? nil
                    : "event tap acknowledgement failed"
            )

            if result.frameChanged {
                return result
            }

            lastResult = result
            if attempt < 5 {
                await wakeUp(item)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }

        return lastResult ?? result(
            item: item,
            targetItem: targetItem,
            destination: destination,
            mouseDownAcknowledged: false,
            mouseDragAcknowledged: false,
            mouseUpAcknowledged: false,
            errorReason: "move did not produce a result"
        )
    }

    private static func result(
        item: RealMenuBarItemSnapshot,
        targetItem: RealMenuBarItemSnapshot,
        destination: CGPoint,
        mouseDownAcknowledged: Bool,
        mouseDragAcknowledged: Bool,
        mouseUpAcknowledged: Bool,
        errorReason: String
    ) -> RealMenuBarItemMoveResult {
        RealMenuBarItemMoveResult(
            requestedWindowID: item.windowID,
            targetWindowID: targetItem.windowID,
            startFrame: item.frame,
            destination: destination,
            mouseDownAcknowledged: mouseDownAcknowledged,
            mouseDragAcknowledged: mouseDragAcknowledged,
            mouseUpAcknowledged: mouseUpAcknowledged,
            finalSnapshot: RealMenuBarItemReader.snapshot(windowID: item.windowID),
            errorReason: errorReason
        )
    }

    private static func configureSuppression(on source: CGEventSource) {
        let filter: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents,
        ]
        source.setLocalEventsFilterDuringSuppressionState(filter, state: .eventSuppressionStateRemoteMouseDrag)
        source.setLocalEventsFilterDuringSuppressionState(filter, state: .eventSuppressionStateSuppressionInterval)
        source.localEventsSuppressionInterval = 0
    }

    private static func wakeUp(_ item: RealMenuBarItemSnapshot) async {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let currentItem = RealMenuBarItemReader.snapshot(windowID: item.windowID),
              let mouseDown = CGEvent.menuBarMoveEvent(
                type: .leftMouseDown,
                location: CGPoint(x: currentItem.frame.midX, y: currentItem.frame.midY),
                item: currentItem,
                targetPID: item.ownerPID,
                source: source
              ),
              let mouseUp = CGEvent.menuBarMoveEvent(
                type: .leftMouseUp,
                location: CGPoint(x: currentItem.frame.midX, y: currentItem.frame.midY),
                item: currentItem,
                targetPID: item.ownerPID,
                source: source
              ) else {
            return
        }

        configureSuppression(on: source)
        _ = await scrombleEvent(mouseDown, from: .pid(item.ownerPID), to: .sessionEventTap)
        _ = await scrombleEvent(mouseUp, from: .pid(item.ownerPID), to: .sessionEventTap)
    }

    private static func scrombleEvent(
        _ event: CGEvent,
        from firstLocation: RealMenuBarEventTap.Location,
        to secondLocation: RealMenuBarEventTap.Location
    ) async -> Bool {
        guard let nullEvent = CGEvent(source: nil) else {
            return false
        }

        let nullUserData = Int64(truncatingIfNeeded: Int(bitPattern: ObjectIdentifier(nullEvent)))
        nullEvent.setIntegerValueField(.eventSourceUserData, value: nullUserData)

        return await withCheckedContinuation { continuation in
            var didResume = false
            func finish(_ succeeded: Bool, disabling taps: [RealMenuBarEventTap?]) {
                guard !didResume else {
                    return
                }

                didResume = true
                for tap in taps {
                    tap?.disable()
                }
                continuation.resume(returning: succeeded)
            }

            var firstTap: RealMenuBarEventTap?
            var secondTap: RealMenuBarEventTap?

            firstTap = RealMenuBarEventTap(
                options: .defaultTap,
                location: firstLocation,
                place: .tailAppendEventTap,
                types: [nullEvent.type]
            ) { proxy, type, receivedEvent in
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    proxy.enable()
                    return nil
                }

                guard receivedEvent.getIntegerValueField(.eventSourceUserData) == nullUserData else {
                    return nil
                }

                proxy.disable()
                postEvent(event, to: secondLocation)
                return nil
            }

            secondTap = RealMenuBarEventTap(
                options: .listenOnly,
                location: secondLocation,
                place: .tailAppendEventTap,
                types: [event.type]
            ) { proxy, type, receivedEvent in
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    proxy.enable()
                    return nil
                }

                guard eventsMatch(receivedEvent, event) else {
                    return nil
                }
                guard proxy.isEnabled else {
                    return nil
                }

                proxy.disable()
                postEvent(event, to: firstLocation)
                finish(true, disabling: [firstTap, secondTap])
                return nil
            }

            guard let firstTap, let secondTap else {
                finish(false, disabling: [firstTap, secondTap])
                return
            }

            firstTap.enable()
            secondTap.enable(timeout: .milliseconds(100)) {
                finish(false, disabling: [firstTap, secondTap])
            }
            postEvent(nullEvent, to: firstLocation)
        }
    }

    private static func waitForFrameChange(
        windowID: CGWindowID,
        initialFrame: CGRect,
        timeout: Duration
    ) async -> RealMenuBarItemSnapshot? {
        let start = ContinuousClock.now

        while start.duration(to: .now) < timeout {
            guard let snapshot = RealMenuBarItemReader.snapshot(windowID: windowID) else {
                return nil
            }

            if !snapshot.isOnScreen
                || abs(snapshot.frame.minX - initialFrame.minX) > 0.5
                || abs(snapshot.frame.maxX - initialFrame.maxX) > 0.5 {
                return snapshot
            }

            try? await Task.sleep(for: .milliseconds(25))
        }

        return RealMenuBarItemReader.snapshot(windowID: windowID)
    }

    private static func postEvent(_ event: CGEvent, to location: RealMenuBarEventTap.Location) {
        switch location {
        case .hidEventTap:
            event.post(tap: .cghidEventTap)
        case .sessionEventTap:
            event.post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap:
            event.post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid):
            event.postToPid(pid)
        }
    }

    private static func eventsMatch(_ first: CGEvent, _ second: CGEvent) -> Bool {
        let fields: [CGEventField] = [
            .eventSourceUserData,
            .mouseEventWindowUnderMousePointer,
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            .windowID,
        ]

        return fields.allSatisfy {
            first.getIntegerValueField($0) == second.getIntegerValueField($0)
        }
    }
}

private extension CGEventField {
    static let windowID = CGEventField(rawValue: 0x33)!
}

private extension CGEvent {
    static func menuBarMoveEvent(
        type: CGEventType,
        location: CGPoint,
        item: RealMenuBarItemSnapshot,
        targetPID: pid_t,
        source: CGEventSource
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            return nil
        }

        if type == .leftMouseDown || type == .leftMouseDragged || type == .leftMouseUp {
            event.flags = .maskCommand
        }

        let windowID = Int64(item.windowID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
        event.setIntegerValueField(
            .eventSourceUserData,
            value: Int64(truncatingIfNeeded: Int(bitPattern: ObjectIdentifier(event)))
        )
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
        event.setIntegerValueField(.windowID, value: windowID)

        return event
    }
}
