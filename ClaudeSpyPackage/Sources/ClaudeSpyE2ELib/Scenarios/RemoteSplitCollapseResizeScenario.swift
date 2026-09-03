import Foundation

/// E2E scenario for Host-owned shared terminal layout and dimensions.
///
/// The app-level left/right arrangement must converge on every Mac without a
/// Viewer mutating tmux directly. The active Viewer requests dimensions for its
/// own viewport; the Host executes them and republishes the resulting state.
/// Native tmux pane layout remains synchronized by the existing `PaneState` path.
public enum RemoteSplitCollapseResizeScenario {
    public static let scenario = ClaudeSpyE2ELib.scenario(
        "Remote Shared Terminal Layout",
        tags: ["remote", "split-view", "layout-sync", "macos-only"]
    ) {
        Shortcut.twoMacPairing

        TestStep.log("Setup: Create rslayout session with two windows")
        TestStep.tmuxCreateSession(name: "rslayout", width: 100, height: 30)
        TestStep.tmuxCommand(arguments: ["rename-window", "-t", "rslayout:0", "winLeft"])
        TestStep.tmuxCommand(arguments: ["new-window", "-t", "rslayout", "-n", "winRight"])
        TestStep.tmuxCommand(arguments: ["select-window", "-t", "rslayout:winLeft"])

        Shortcut.openPanesWindow()
        TestStep.macResizeWindow(width: 1_000, height: 700)
        TestStep.macWaitForElement(titled: "rslayout", timeout: 15)
        TestStep.macClickButton(titled: "rslayout")
        TestStep.macWaitForElement(titled: "winLeft", timeout: 10)
        TestStep.macWaitForElement(titled: "winRight", timeout: 10)
        TestStep.wait(seconds: 1)
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "hostFullWidth",
            heightKey: "hostFullHeight"
        )

        Shortcut.openPanesWindow(instance: 1)
        TestStep.macResizeWindow(width: 1_300, height: 700, instance: 1)
        TestStep.macWaitForElement(titled: "rslayout", timeout: 15, instance: 1)
        TestStep.macClickButton(titled: "rslayout", instance: 1)
        TestStep.macWaitForElement(titled: "winLeft", timeout: 10, instance: 1)
        TestStep.macWaitForElement(titled: "winRight", timeout: 10, instance: 1)
        // Selecting the wider Viewer must resize the Host tmux window even
        // though the logical terminal layout did not change.
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "rslayout:winLeft",
            format: "#{pane_width}",
            notEqualTo: "${hostFullWidth}",
            timeout: 10
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "viewerFullWidth",
            heightKey: "viewerFullHeight"
        )
        TestStep.assertStoredNotEqual(key: "viewerFullWidth", otherKey: "hostFullWidth")
        TestStep.wait(seconds: 2)
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "settledViewerFullWidth",
            heightKey: "settledViewerFullHeight"
        )
        TestStep.assertStoredEqual(key: "settledViewerFullWidth", otherKey: "viewerFullWidth")

        // Host opens the right terminal. The Viewer must render the same
        // logical arrangement after the canonical SessionState push.
        TestStep.log("Phase 1: Host opens winRight in the right pane")
        TestStep.macClickButton(titled: "Open terminal in split: winRight")
        TestStep.macWaitForElement(titled: "Move terminal to left: winRight", timeout: 10)
        TestStep.macWaitForElement(
            titled: "Move terminal to left: winRight",
            timeout: 10,
            instance: 1
        )
        // Activate the Viewer, then reproduce the reported asymmetric layout.
        // The left tmux window must grow beyond the right's 80-column floor;
        // without Viewer-driven sizing both remain 80 columns and the left side
        // renders a large blank strip.
        TestStep.macClickButton(titled: "winLeft", instance: 1)
        TestStep.wait(seconds: 1)
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "equalSplitLeftWidth",
            heightKey: "equalSplitLeftHeight"
        )
        TestStep.macDrag(fromX: 785, fromY: 300, toX: 1_050, toY: 300, instance: 1)
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "rslayout:winLeft",
            format: "#{pane_width}",
            notEqualTo: "${equalSplitLeftWidth}",
            timeout: 10
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "wideSplitLeftWidth",
            heightKey: "wideSplitLeftHeight"
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winRight",
            widthKey: "narrowSplitRightWidth",
            heightKey: "narrowSplitRightHeight"
        )
        TestStep.assertStoredNotEqual(key: "wideSplitLeftWidth", otherKey: "narrowSplitRightWidth")
        TestStep.wait(seconds: 2)
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "settledWideSplitLeftWidth",
            heightKey: "settledWideSplitLeftHeight"
        )
        TestStep.assertStoredEqual(key: "settledWideSplitLeftWidth", otherKey: "wideSplitLeftWidth")

        // A Viewer-only window resize carries no logical layout update, so this
        // assertion specifically guards the geometry-to-ResizeTmuxPane path.
        TestStep.macResizeWindow(width: 1_100, height: 700, instance: 1)
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "rslayout:winLeft",
            format: "#{pane_width}",
            notEqualTo: "${wideSplitLeftWidth}",
            timeout: 10
        )
        TestStep.macScreenshot(label: "shared-layout-host-split")
        TestStep.macScreenshot(label: "shared-layout-viewer-converged", instance: 1)

        // A Viewer may request a change, but only the Host commits it. Moving
        // the terminal left on the Viewer must therefore collapse both UIs.
        TestStep.log("Phase 2: Viewer requests collapse; Host republishes it")
        TestStep.macClickButton(titled: "Move terminal to left: winRight", instance: 1)
        TestStep.macWaitForElementToDisappear(
            titled: "Move terminal to left: winRight",
            timeout: 10,
            instance: 1
        )
        TestStep.macWaitForElementToDisappear(
            titled: "Move terminal to left: winRight",
            timeout: 10
        )
        TestStep.macScreenshot(label: "shared-layout-viewer-collapse")
        TestStep.macScreenshot(label: "shared-layout-host-converged")

        // Re-open from the Viewer, then remove the underlying tmux window.
        // The stale canonical right side must be pruned on both clients.
        TestStep.log("Phase 3: Viewer opens split, then Host tmux removes winRight")
        TestStep.macClickButton(titled: "Open terminal in split: winRight", instance: 1)
        TestStep.macWaitForElement(titled: "Move terminal to left: winRight", timeout: 10)
        TestStep.tmuxCommand(arguments: ["kill-window", "-t", "rslayout:winRight"])
        TestStep.macWaitForElementToDisappear(
            titled: "Move terminal to left: winRight",
            timeout: 10,
            instance: 1
        )
        TestStep.macWaitForElementToDisappear(
            titled: "Move terminal to left: winRight",
            timeout: 10
        )

        TestStep.tmuxCommand(arguments: ["kill-session", "-t", "rslayout"])
        TestStep.wait(seconds: 2)
    }
}
