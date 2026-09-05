#if os(macOS)
    import Testing
    @testable import CtrlxServerFeature

    @Suite("Terminal theme palettes")
    struct TerminalThemePaletteTests {
        @Test("Every theme has a complete ANSI palette", arguments: TerminalTheme.allCases)
        func completeANSITheme(theme: TerminalTheme) {
            #expect(theme.palette.ansiColors.count == 16)
        }

        @Test("Anysphere Dark matches the Coterm palette")
        func anysphereDarkPalette() {
            let palette = TerminalTheme.anysphereDark.palette

            #expect(palette.foreground == TerminalRGB(hex: 0xF0F0F0))
            #expect(palette.background == TerminalRGB(hex: 0x141414))
            #expect(palette.ansiColors == TerminalThemePalette.anysphereDarkANSI)
            #expect(palette.ansiColors[1] == TerminalRGB(hex: 0xFC6B83))
            #expect(palette.ansiColors[10] == TerminalRGB(hex: 0x70B489))
        }

        @Test("Anysphere Dark keeps terminal and workspace surfaces separate")
        func anysphereDarkWorkspacePalette() {
            let terminal = TerminalTheme.anysphereDark.palette
            let workspace = TerminalTheme.anysphereDark.workspacePalette

            #expect(terminal.background == TerminalRGB(hex: 0x141414))
            #expect(workspace.sidebarBackground == .init(hex: 0x141414))
            #expect(workspace.workspaceBackground == .init(hex: 0x181818))
            #expect(workspace.chromeBackground == .init(hex: 0x202020, alpha: 0xCC))
            #expect(workspace.activeTabBackground == .init(hex: 0x181818))
            #expect(workspace.border == .init(hex: 0x303030))
            #expect(workspace.selectedSidebarRow == .init(hex: 0x1C1C1C))
        }

        @Test("Existing themes retain their terminal background", arguments: [
            TerminalTheme.defaultDark,
            TerminalTheme.defaultLight,
            TerminalTheme.solarizedDark,
            TerminalTheme.solarizedLight,
        ])
        func existingThemeWorkspaceBackground(theme: TerminalTheme) {
            #expect(theme.workspacePalette.workspaceBackground.color == theme.palette.background)
            #expect(theme.workspacePalette.workspaceBackground.alpha == 0xFF)
        }

        @Test("Default Dark uses the macOS dark window background")
        func defaultDarkBackground() {
            #expect(TerminalTheme.defaultDark.palette.background == TerminalRGB(hex: 0x1E1E1E))
        }

        @Test("OSC colors preserve full byte precision")
        func oscColors() {
            let palette = TerminalTheme.anysphereDark.palette

            #expect(palette.foreground.oscValue == "f0f0/f0f0/f0f0")
            #expect(palette.background.oscValue == "1414/1414/1414")
        }

        @Test("Anysphere Dark is exposed as a selectable theme")
        func selectableTheme() {
            #expect(TerminalTheme(rawValue: "Anysphere Dark") == .anysphereDark)
            #expect(TerminalTheme.allCases.contains(.anysphereDark))
        }

        @Test("Workbench contrast follows terminal theme brightness")
        func workbenchColorScheme() {
            #expect(TerminalTheme.defaultDark.workspaceColorScheme == .dark)
            #expect(TerminalTheme.solarizedDark.workspaceColorScheme == .dark)
            #expect(TerminalTheme.anysphereDark.workspaceColorScheme == .dark)
            #expect(TerminalTheme.defaultLight.workspaceColorScheme == .light)
            #expect(TerminalTheme.solarizedLight.workspaceColorScheme == .light)
        }
    }
#endif
