import AppKit
import SwiftUI

enum ArticleKeyboardCommand { case moveUp, moveDown, open, openDetail, toggleRead, toggleStarred, refresh, dismiss }
enum ArticleReaderTarget {
    static func articleID(hoveredID: Int64?, selectedID: Int64?, availableIDs: Set<Int64>) -> Int64? {
        if let hoveredID, availableIDs.contains(hoveredID) { return hoveredID }
        if let selectedID, availableIDs.contains(selectedID) { return selectedID }
        return nil
    }
}
enum ArticleKeyboardRouting {
    static func command(for event: NSEvent) -> ArticleKeyboardCommand? {
        command(keyCode: event.keyCode, charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifierFlags: event.modifierFlags)
    }

    static func command(keyCode: UInt16, charactersIgnoringModifiers: String?, modifierFlags: NSEvent.ModifierFlags) -> ArticleKeyboardCommand? {
        let modifiers = modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, charactersIgnoringModifiers?.lowercased() == "r" { return .refresh }
        guard modifiers.isEmpty else { return nil }
        switch keyCode {
        case 49: return .openDetail
        case 126: return .moveUp
        case 125: return .moveDown
        case 36, 76: return .open
        case 53: return .dismiss
        default:
            switch charactersIgnoringModifiers?.lowercased() {
            case "m": return .toggleRead
            case "s": return .toggleStarred
            default: return nil
            }
        }
    }
}
struct KeyboardCommandObserver: NSViewRepresentable {
    let onCommand: (ArticleKeyboardCommand) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCommand: onCommand) }
    func makeNSView(context: Context) -> NSView { let view = NSView(); context.coordinator.view = view; context.coordinator.start(); return view }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.view = view; context.coordinator.onCommand = onCommand }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator {
        weak var view: NSView?; var onCommand: (ArticleKeyboardCommand) -> Void; private var monitor: Any?
        init(onCommand: @escaping (ArticleKeyboardCommand) -> Void) { self.onCommand = onCommand }
        func start() { guard monitor == nil else { return }; monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in guard let self, event.window === self.view?.window, !self.isTextEntryActive(in: event.window), let command = ArticleKeyboardRouting.command(for: event) else { return event }; self.onCommand(command); return nil } }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        private func isTextEntryActive(in window: NSWindow?) -> Bool {
            guard let responder = window?.firstResponder else { return false }
            if let textView = responder as? NSTextView { return textView.isEditable }
            return responder is NSTextField
        }
    }
}
