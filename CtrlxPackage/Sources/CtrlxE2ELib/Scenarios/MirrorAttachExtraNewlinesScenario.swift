import Foundation

/// E2E regression test for issue #429: with the conditional-padding fix
/// landed, the visible area must NOT show extra blank rows when an explicitly
/// requested resize reflows a freshly attached wide terminal.
///
/// Recipe — exercises the production manual resize path that originally
/// exposed the same double-spacing defect:
///
///   1. Start with a tmux pane that is significantly WIDER than the mirror
///      window can fit.
///   2. Pre-fill scrollback with paired log entries to give Part 1 + Part 2
///      of the rebuild substantial content to render.
///   3. Resize the mirror window to a narrow width.
///   4. Click the pane to attach at its current width.
///   5. Click “Resize visible terminals to fit this Mac”. The resulting
///      layout-change resizes the SwiftTerm buffer to fewer cols and triggers
///      `reflowNarrower`. Pre-fix, padded rows reflowed into blank
///      continuation rows; post-fix, ordinary content rows aren't padded,
///      so reflow trims trailing NULL cells and no blanks are produced.
///   6. Screenshot the attach state — the baseline captures the fixed,
///      single-spaced rendering. A regression that reintroduces the
///      pad-everything path will diff against this baseline.
///
/// Companion unit tests `issue429NoBlankRowsOnColsMismatch` and
/// `issue429NoBlankRowsAfterReflowNarrower` deterministically cover the
/// pad-to-width vs. cols mismatch and reflow-narrower paths; this scenario
/// exercises the same fix end-to-end through an explicit resize after attach.
public enum MirrorAttachExtraNewlinesScenario {
    public static let scenario = CtrlxE2ELib.scenario(
        "Mirror Attach Extra Newlines",
        tags: ["rendering", "macos-only"]
    ) {
        TestStep.log("Creating a WIDE tmux pane (200x40) for manual reflow")
        TestStep.tmuxCreateSession(name: "newline-bug", width: 200, height: 40)

        // Pre-fill scrollback with ~120 paired log entries to give Part 1
        // and Part 2 of the rebuild substantial content.
        Shortcut.tmuxRunCommand(
            target: "newline-bug:0",
            command: "for i in $(seq 1 60); do printf '[entry %03d] Checking for work...\\n' $i; printf '[entry %03d] Nothing to do\\n' $i; done"
        )
        TestStep.wait(seconds: 2)

        Shortcut.macOnlySetup
        // Narrow tall window — much smaller than the 200-column pane.
        TestStep.macResizeWindow(width: 700, height: 1_000)
        TestStep.wait(seconds: 1)

        // Attach first, then explicitly shrink the tmux window and trigger the
        // reflow path that exposed #429's double-spacing pre-fix.
        TestStep.macClickButton(titled: "newline-bug")
        TestStep.wait(seconds: 1)
        TestStep.macClickButton(titled: "Resize visible terminals to fit this Mac")
        TestStep.wait(seconds: 1)

        // Screenshot the post-attach state — the baseline captures the
        // fixed, single-spaced rendering. A regression that reintroduces
        // pad-every-row will diff against this baseline.
        TestStep.macScreenshot(label: "mac-attach-during-resize")
    }
}
