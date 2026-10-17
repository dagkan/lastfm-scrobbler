import AppKit

@MainActor
final class HotkeyManager {
    private var monitors: [Any] = []

    typealias Handler = () -> Void

    func register(key: String, modifiers: NSEvent.ModifierFlags, handler: @escaping Handler) {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers else { return }
            guard event.charactersIgnoringModifiers?.lowercased() == key.lowercased() else { return }
            Task { @MainActor in handler() }
        }
        if let m = monitor { monitors.append(m) }
    }

    func removeAll() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
    }

    deinit { }
}
