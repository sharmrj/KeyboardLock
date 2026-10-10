@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import SwiftUI

private let systemDefinedEventTypeRawValue: UInt32 = 14
private let accessibilityPromptKey =
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

private func eventMaskBit(_ rawValue: UInt32) -> CGEventMask {
    CGEventMask(1) << rawValue
}

private func keyboardEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    return blocker.handleEvent(type: type, event: event)
}

final class KeyboardBlocker: ObservableObject, @unchecked Sendable {
    static let shared = KeyboardBlocker()

    @Published private(set) var isLocked = false
    @Published private(set) var status = "Ready"

    private var shouldBlock = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var suppressedKeyCodes = Set<Int64>()

    private static let modifierFlags: CGEventFlags = [
        .maskAlphaShift,
        .maskShift,
        .maskControl,
        .maskAlternate,
        .maskCommand,
        .maskSecondaryFn
    ]

    private static let blockedEventMask: CGEventMask = [
        CGEventType.keyDown.rawValue,
        CGEventType.keyUp.rawValue,
        CGEventType.flagsChanged.rawValue,
        systemDefinedEventTypeRawValue
    ].reduce(0) { mask, rawValue in
        mask | eventMaskBit(rawValue)
    }

    private init() {}

    func setLocked(_ newValue: Bool) {
        precondition(Thread.isMainThread)

        if newValue {
            lock()
        } else {
            unlock()
        }
    }

    func refreshPermissionStatus() {
        precondition(Thread.isMainThread)

        guard !isLocked else { return }
        status = AXIsProcessTrusted() ? "Ready" : "Accessibility permission required"
    }

    private func lock() {
        guard !isLocked else { return }

        guard requestAccessibilityPermissionIfNeeded() else {
            status = "Allow Accessibility access, then turn the switch on again"
            return
        }

        let currentFlags = CGEventSource.flagsState(.combinedSessionState)
        guard currentFlags.intersection(Self.modifierFlags).isEmpty else {
            status = "Release all modifier keys, then try again"
            return
        }

        guard installEventTap() else {
            status = "Could not create the keyboard event filter"
            return
        }

        shouldBlock = true
        isLocked = true
        status = "Keyboard locked"
        updateWindowSafetyMode(locked: true)
    }

    private func unlock() {
        shouldBlock = false
        removeEventTap()
        suppressedKeyCodes.removeAll(keepingCapacity: true)

        if isLocked {
            isLocked = false
            status = "Ready"
        }
        updateWindowSafetyMode(locked: false)
    }

    private func requestAccessibilityPermissionIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let promptKey = accessibilityPromptKey
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func installEventTap() -> Bool {
        removeEventTap()

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.blockedEventMask,
            callback: keyboardEventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if shouldBlock, let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard shouldBlock else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            suppressedKeyCodes.insert(event.getIntegerValueField(.keyboardEventKeycode))
            return nil
        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // Let a key held before locking receive its release. This avoids a
            // key becoming logically stuck in the foreground application.
            return suppressedKeyCodes.remove(keyCode) == nil
                ? Unmanaged.passUnretained(event)
                : nil
        case .flagsChanged:
            return nil
        default:
            return type.rawValue == systemDefinedEventTypeRawValue
                ? nil
                : Unmanaged.passUnretained(event)
        }
    }

    private func updateWindowSafetyMode(locked: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.title == "Keyboard Lock" }) else {
                return
            }

            window.level = locked ? .floating : .normal
            window.standardWindowButton(.closeButton)?.isEnabled = !locked
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = !locked

            if locked {
                window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
                window.makeKeyAndOrderFront(nil)
            } else {
                window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
            }
        }
    }

    deinit {
        shouldBlock = false
        removeEventTap()
    }
}

struct ContentView: View {
    @ObservedObject var blocker: KeyboardBlocker

    var body: some View {
        VStack(spacing: 18) {
            Text("Keyboard Lock")
                .font(.title2.weight(.semibold))

            Toggle(
                "Disable keyboard",
                isOn: Binding(
                    get: { blocker.isLocked },
                    set: { blocker.setLocked($0) }
                )
            )
            .toggleStyle(.switch)

            Text(blocker.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .frame(width: 310)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        KeyboardBlocker.shared.refreshPermissionStatus()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        KeyboardBlocker.shared.refreshPermissionStatus()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        KeyboardBlocker.shared.setLocked(false)
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct KeyboardLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var blocker = KeyboardBlocker.shared

    var body: some Scene {
        WindowGroup("Keyboard Lock") {
            ContentView(blocker: blocker)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
