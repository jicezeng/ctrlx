#if os(macOS)
    import CtrlxCommon
    import Dependencies
    import Testing
    @testable import CtrlxServerFeature

    @MainActor
    @Suite("Remote session order settings")
    struct RemoteSessionOrderSettingsTests {
        @Test("Orders persist independently by host")
        func persistsByHost() {
            let preferences = PreferencesService.inMemory()
            let settings = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }

            settings.setRemoteSessionOrder(["b", "a", "b", ""], for: "host-a")
            settings.setRemoteSessionOrder(["same", "other"], for: "host-b")

            let reloaded = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }
            #expect(reloaded.remoteSessionOrder(for: "host-a") == ["b", "a"])
            #expect(reloaded.remoteSessionOrder(for: "host-b") == ["same", "other"])
        }

        @Test("Rename and unpair update persisted order")
        func migratesAndRemovesOrder() {
            let preferences = PreferencesService.inMemory()
            let settings = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }

            settings.setRemoteSessionOrder(["first", "old", "last"], for: "host")
            settings.replaceRemoteSessionName("old", with: "new", for: "host")
            #expect(settings.remoteSessionOrder(for: "host") == ["first", "new", "last"])

            settings.removeHostPairing(id: "host")
            let reloaded = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }
            #expect(reloaded.remoteSessionOrder(for: "host").isEmpty)
        }
    }
#endif
