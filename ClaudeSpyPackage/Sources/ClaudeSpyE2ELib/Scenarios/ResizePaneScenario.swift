import Foundation

/// E2E coverage for the manual-only terminal sizing policy.
///
/// Window geometry and session selection must leave tmux untouched. A direct
/// click on "Resize visible terminals to fit this Mac" is the only resize
/// trigger and affects only the session currently visible in CtrlX.
public enum ResizePaneScenario {
    public static let scenario = ClaudeSpyE2ELib.scenario(
        "Manual Terminal Resize",
        tags: ["resize", "macos-only"]
    ) {
        TestStep.log("Creating tmux sessions on test socket")
        TestStep.tmuxCreateSession(name: "resize-test-1", width: 80, height: 24)
        TestStep.tmuxCreateSession(name: "resize-test-2", width: 80, height: 24)

        Shortcut.macOnlySetup
        TestStep.macClickButton(titled: "resize-test-1")
        TestStep.wait(seconds: 1)
        TestStep.macWaitForElement(
            titled: "Resize visible terminals to fit this Mac",
            timeout: 5
        )

        TestStep.tmuxStorePaneDimensions(
            target: "resize-test-1:0",
            widthKey: "initialWidth",
            heightKey: "initialHeight"
        )

        // Geometry alone is presentation-only.
        TestStep.macResizeWindow(width: 1_400, height: 900)
        TestStep.wait(seconds: 1)
        TestStep.tmuxStorePaneDimensions(
            target: "resize-test-1:0",
            widthKey: "afterWindowResizeWidth",
            heightKey: "afterWindowResizeHeight"
        )
        TestStep.assertStoredEqual(key: "afterWindowResizeWidth", otherKey: "initialWidth")
        TestStep.assertStoredEqual(key: "afterWindowResizeHeight", otherKey: "initialHeight")

        // The explicit button applies the current Mac's viewport.
        TestStep.macClickButton(titled: "Resize visible terminals to fit this Mac")
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "resize-test-1:0",
            format: "#{pane_width}",
            notEqualTo: "${initialWidth}",
            timeout: 10
        )
        TestStep.tmuxStorePaneDimensions(
            target: "resize-test-1:0",
            widthKey: "firstManualWidth",
            heightKey: "firstManualHeight"
        )

        // A second geometry change remains inert until another click.
        TestStep.macResizeWindow(width: 900, height: 600)
        TestStep.wait(seconds: 1)
        TestStep.tmuxStorePaneDimensions(
            target: "resize-test-1:0",
            widthKey: "afterSecondWindowResizeWidth",
            heightKey: "afterSecondWindowResizeHeight"
        )
        TestStep.assertStoredEqual(key: "afterSecondWindowResizeWidth", otherKey: "firstManualWidth")
        TestStep.assertStoredEqual(key: "afterSecondWindowResizeHeight", otherKey: "firstManualHeight")

        // Switching sessions must not implicitly resize either session.
        TestStep.macClickButton(titled: "resize-test-2")
        TestStep.wait(seconds: 1)
        TestStep.tmuxStorePaneDimensions(
            target: "resize-test-2:0",
            widthKey: "secondInitialWidth",
            heightKey: "secondInitialHeight"
        )
        TestStep.storeValue(key: "standardWidth", value: "80")
        TestStep.storeValue(key: "standardHeight", value: "24")
        TestStep.assertStoredEqual(key: "secondInitialWidth", otherKey: "standardWidth")
        TestStep.assertStoredEqual(key: "secondInitialHeight", otherKey: "standardHeight")

        TestStep.macResizeWindow(width: 1_200, height: 800)
        TestStep.wait(seconds: 1)
        TestStep.tmuxStorePaneDimensions(
            target: "resize-test-2:0",
            widthKey: "secondBeforeManualWidth",
            heightKey: "secondBeforeManualHeight"
        )
        TestStep.assertStoredEqual(key: "secondBeforeManualWidth", otherKey: "secondInitialWidth")
        TestStep.assertStoredEqual(key: "secondBeforeManualHeight", otherKey: "secondInitialHeight")

        TestStep.macClickButton(titled: "Resize visible terminals to fit this Mac")
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "resize-test-2:0",
            format: "#{pane_width}",
            notEqualTo: "${secondInitialWidth}",
            timeout: 10
        )

        TestStep.macClickButton(titled: "resize-test-1")
        TestStep.wait(seconds: 1)
        TestStep.tmuxStorePaneDimensions(
            target: "resize-test-1:0",
            widthKey: "firstAfterSwitchWidth",
            heightKey: "firstAfterSwitchHeight"
        )
        TestStep.assertStoredEqual(key: "firstAfterSwitchWidth", otherKey: "firstManualWidth")
        TestStep.assertStoredEqual(key: "firstAfterSwitchHeight", otherKey: "firstManualHeight")

        TestStep.macClickButton(titled: "Resize visible terminals to fit this Mac")
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "resize-test-1:0",
            format: "#{pane_width}",
            notEqualTo: "${firstManualWidth}",
            timeout: 10
        )
        TestStep.macScreenshot(label: "mac-manual-resize-only")

        TestStep.tmuxCommand(arguments: ["kill-session", "-t", "resize-test-1"])
        TestStep.tmuxCommand(arguments: ["kill-session", "-t", "resize-test-2"])
        TestStep.wait(seconds: 2)
    }
}
