import CtrlxNetworking
import Foundation
import Testing
@testable import CtrlxCommon

@Suite("Terminal stream handler ownership")
@MainActor
struct TerminalStreamHandlerRegistryTests {
    @Test("A stale view cannot unregister its replacement handler")
    func staleUnregisterIsIgnored() {
        var registry = TerminalStreamHandlerRegistry()
        var deliveries: [String] = []
        let oldId = registry.register(paneId: "%1") { _ in
            deliveries.append("old")
        }
        let newId = registry.register(paneId: "%1") { _ in
            deliveries.append("new")
        }

        registry.unregister(paneId: "%1", registrationId: oldId)
        registry.deliver(.streamEnd(paneId: "%1"))

        #expect(deliveries == ["new"])

        registry.unregister(paneId: "%1", registrationId: newId)
        registry.deliver(.streamEnd(paneId: "%1"))
        #expect(deliveries == ["new"])
    }
}
