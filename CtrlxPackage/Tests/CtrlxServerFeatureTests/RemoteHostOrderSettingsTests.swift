#if os(macOS)
    import CtrlxCommon
    import CtrlxNetworking
    import Dependencies
    import Testing
    @testable import CtrlxServerFeature

    @MainActor
    @Suite("Remote host order settings")
    struct RemoteHostOrderSettingsTests {
        @Test("Order persists and pairing updates stay in place")
        func persistsAcrossUpdates() {
            let preferences = PreferencesService.inMemory()
            let settings = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }

            settings.addHostPairing(host("a"))
            settings.addHostPairing(host("b"))
            settings.addHostPairing(host("c"))
            settings.moveHostPairing(sourceID: "a", targetID: "c")
            #expect(settings.pairedHosts.map(\.id) == ["b", "c", "a"])

            settings.addHostPairing(host("c", name: "Updated C"))
            #expect(settings.pairedHosts.map(\.id) == ["b", "c", "a"])
            #expect(settings.getHostPairing(id: "c")?.hostName == "Updated C")

            let reloaded = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }
            #expect(reloaded.pairedHosts.map(\.id) == ["b", "c", "a"])

            reloaded.addHostPairing(host("d"))
            #expect(reloaded.pairedHosts.map(\.id) == ["b", "c", "a", "d"])

            reloaded.removeHostPairing(id: "c")
            #expect(reloaded.pairedHosts.map(\.id) == ["b", "a", "d"])
        }

        private func host(_ id: String, name: String? = nil) -> PairedHost {
            PairedHost(
                id: id,
                hostName: name ?? "Host \(id)",
                username: "user",
                partnerPublicKey: "key",
                partnerPublicKeyId: "key-id"
            )
        }
    }
#endif
