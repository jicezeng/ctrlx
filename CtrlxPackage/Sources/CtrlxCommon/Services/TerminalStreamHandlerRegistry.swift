import CtrlxNetworking
import Foundation

/// Owns the single active relay callback for each pane.
///
/// Registration IDs make replacement atomic from the caller's perspective: an
/// old view may request removal, but only the current owner can actually clear
/// the callback.
@MainActor
package struct TerminalStreamHandlerRegistry {
    private struct Registration {
        let id: UUID
        let handler: @MainActor @Sendable (TerminalStreamMessage) -> Void
    }

    private var registrations: [String: Registration] = [:]

    package init() { }

    package mutating func register(
        paneId: String,
        handler: @MainActor @escaping @Sendable (TerminalStreamMessage) -> Void
    ) -> UUID {
        let id = UUID()
        registrations[paneId] = Registration(id: id, handler: handler)
        return id
    }

    package mutating func unregister(paneId: String, registrationId: UUID) {
        guard registrations[paneId]?.id == registrationId else { return }
        registrations.removeValue(forKey: paneId)
    }

    package func deliver(_ message: TerminalStreamMessage) {
        let handler = registrations[message.paneId]?.handler
        handler?(message)
    }
}
