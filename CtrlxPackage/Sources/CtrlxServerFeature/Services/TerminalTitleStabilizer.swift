#if os(macOS)
    /// Removes a transient activity glyph from terminal titles before they
    /// enter observable UI state.
    ///
    /// Agent TUIs commonly rotate a leading Braille glyph roughly ten times a
    /// second (`⠇ coding`, `⠏ coding`, ...). The semantic title is unchanged,
    /// but publishing every frame invalidates the retained macOS view graph and
    /// competes with terminal input. A Braille character is treated as a spinner
    /// only when whitespace separates it from a non-empty title.
    enum TerminalTitleStabilizer {
        static func stabilize(_ title: String) -> String {
            guard
                let first = title.first,
                first.unicodeScalars.count == 1,
                let scalar = first.unicodeScalars.first,
                (0x2800 ... 0x28FF).contains(scalar.value)
            else { return title }

            let remainder = title.dropFirst()
            guard remainder.first?.isWhitespace == true else { return title }

            let stable = remainder.drop(while: \.isWhitespace)
            return stable.isEmpty ? title : String(stable)
        }
    }
#endif
