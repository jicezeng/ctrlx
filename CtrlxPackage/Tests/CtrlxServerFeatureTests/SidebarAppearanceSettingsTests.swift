#if os(macOS)
    import CtrlxCommon
    import Dependencies
    import Foundation
    import Testing
    @testable import CtrlxServerFeature

    @MainActor
    @Suite("Sidebar appearance settings")
    struct SidebarAppearanceSettingsTests {
        @Test("Selected-session highlight defaults off and persists")
        func selectedSessionHighlightPersistence() {
            let preferences = PreferencesService.inMemory()

            let settings = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }

            #expect(settings.highlightSelectedSidebarSession == false)
            settings.highlightSelectedSidebarSession = true

            let reloaded = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }

            #expect(reloaded.highlightSelectedSidebarSession == true)
        }

        @Test("Default sidebar layouts lead with the tmux session name")
        func sessionNameLeadsDefaultLayouts() {
            #expect(SidebarField.defaultFields.first == .sessionName)
            #expect(SidebarField.defaultTerminalFields.first == .sessionName)
            #expect(SidebarField.terminalFields.contains(.windowName))
            #expect(!SidebarField.defaultFields.contains(.windowName))
            #expect(!SidebarField.defaultTerminalFields.contains(.windowName))
        }

        @Test("Exact legacy defaults migrate and persist")
        func legacyDefaultsMigrate() throws {
            let preferences = PreferencesService.inMemory()
            let legacyAgentData = try JSONEncoder().encode([
                SidebarField.customDescription, .projectName, .currentPath, .latestEvent,
            ])
            let legacyTerminalData = try JSONEncoder().encode([
                SidebarField.customDescription, .terminalTitle, .currentPath, .command,
            ])
            preferences.setData(
                legacyAgentData,
                AppSettings.Keys.sidebarFields.rawValue
            )
            preferences.setData(
                legacyTerminalData,
                AppSettings.Keys.sidebarTerminalFields.rawValue
            )

            let settings = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }

            #expect(settings.sidebarFields == SidebarField.defaultFields)
            #expect(settings.sidebarTerminalFields == SidebarField.defaultTerminalFields)
            let persistedAgentData = try #require(preferences.data(AppSettings.Keys.sidebarFields.rawValue))
            let persistedTerminalData = try #require(preferences.data(AppSettings.Keys.sidebarTerminalFields.rawValue))
            let persistedAgent = try JSONDecoder().decode([SidebarField].self, from: persistedAgentData)
            let persistedTerminal = try JSONDecoder().decode([SidebarField].self, from: persistedTerminalData)
            #expect(persistedAgent == SidebarField.defaultFields)
            #expect(persistedTerminal == SidebarField.defaultTerminalFields)
        }

        @Test("Custom sidebar layouts are not migrated")
        func customLayoutsRemainUnchanged() throws {
            let preferences = PreferencesService.inMemory()
            let customAgent: [SidebarField] = [.customDescription, .projectName]
            let customTerminal: [SidebarField] = [.currentPath, .command]
            let customAgentData = try JSONEncoder().encode(customAgent)
            let customTerminalData = try JSONEncoder().encode(customTerminal)
            preferences.setData(
                customAgentData,
                AppSettings.Keys.sidebarFields.rawValue
            )
            preferences.setData(
                customTerminalData,
                AppSettings.Keys.sidebarTerminalFields.rawValue
            )

            let settings = withDependencies {
                $0[PreferencesService.self] = preferences
            } operation: {
                AppSettings()
            }

            #expect(settings.sidebarFields == customAgent)
            #expect(settings.sidebarTerminalFields == customTerminal)
        }
    }
#endif
