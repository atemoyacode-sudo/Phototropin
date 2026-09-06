import AppKit

@MainActor
enum OverlayWindowSupport {
    static func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// A borderless `NSPanel` reports `canBecomeKey == false`, which leaves any
    /// text field inside it unable to take keyboard focus.
    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    static func makePanel(contentSize: CGSize, transient: Bool = false) -> NSPanel {
        let panel = KeyablePanel(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        // Lets a text field inside the overlay take keyboard focus without the
        // panel stealing focus every time an answer appears.
        panel.becomesKeyOnlyIfNeeded = true
        // The app is not frontmost while the card floats over another window,
        // so hover tracking needs mouse-moved events delivered explicitly.
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = transient
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            : [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        return panel
    }
}
