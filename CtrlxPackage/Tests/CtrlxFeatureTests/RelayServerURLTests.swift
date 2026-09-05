import Testing
@testable import CtrlxFeature

@Suite("RelayServerURL")
struct RelayServerURLTests {
    @Test("Accepts secure relay URLs with ports")
    func acceptsSecureURL() {
        #expect(
            RelayServerURL.normalized("wss://ctrlx.example.com:7001")
                == "wss://ctrlx.example.com:7001"
        )
    }

    @Test("Accepts local WebSocket URLs")
    func acceptsLocalURL() {
        #expect(RelayServerURL.normalized("ws://127.0.0.1:8080") == "ws://127.0.0.1:8080")
    }

    @Test("Trims whitespace and trailing slashes")
    func normalizesWhitespaceAndSlash() {
        #expect(
            RelayServerURL.normalized("  WSS://relay.example.com/base///\n")
                == "wss://relay.example.com/base"
        )
    }

    @Test("Rejects HTTP and URLs without a host")
    func rejectsInvalidSchemeOrHost() {
        #expect(RelayServerURL.normalized("https://relay.example.com") == nil)
        #expect(RelayServerURL.normalized("wss:///api/ws") == nil)
        #expect(RelayServerURL.normalized("") == nil)
    }

    @Test("Rejects credentials, queries, and fragments")
    func rejectsAmbiguousComponents() {
        #expect(RelayServerURL.normalized("wss://user:pass@relay.example.com") == nil)
        #expect(RelayServerURL.normalized("wss://relay.example.com?token=secret") == nil)
        #expect(RelayServerURL.normalized("wss://relay.example.com#fragment") == nil)
    }
}
