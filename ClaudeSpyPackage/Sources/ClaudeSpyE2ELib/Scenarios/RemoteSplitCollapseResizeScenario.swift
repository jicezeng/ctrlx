import Foundation

/// E2E scenario for shared layout plus explicit, user-owned dimensions.
///
/// The app-level left/right arrangement converges on every Mac, but geometry
/// alone never changes tmux. Either Mac may explicitly fit both visible tmux
/// windows; the last button click owns the shared grid until another click.
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
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winRight",
            widthKey: "hostRightWidth",
            heightKey: "hostRightHeight"
        )

        Shortcut.openPanesWindow(instance: 1)
        TestStep.macResizeWindow(width: 1_300, height: 700, instance: 1)
        TestStep.macWaitForElement(titled: "rslayout", timeout: 15, instance: 1)
        TestStep.macClickButton(titled: "rslayout", instance: 1)
        TestStep.macWaitForElement(titled: "winLeft", timeout: 10, instance: 1)
        TestStep.macWaitForElement(titled: "winRight", timeout: 10, instance: 1)
        // Opening and selecting a differently sized Viewer is presentation-only.
        // It must not alter the Host's global tmux rows or columns.
        TestStep.wait(seconds: 2)
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "afterViewerOpenWidth",
            heightKey: "afterViewerOpenHeight"
        )
        TestStep.assertStoredEqual(key: "afterViewerOpenWidth", otherKey: "hostFullWidth")
        TestStep.assertStoredEqual(key: "afterViewerOpenHeight", otherKey: "hostFullHeight")

        // Host opens the right terminal. Layout sync must not resize either
        // underlying tmux window.
        TestStep.log("Phase 1: Layout changes remain dimension-free")
        TestStep.macClickButton(titled: "Open terminal in split: winRight")
        TestStep.macWaitForElement(titled: "Move terminal to left: winRight", timeout: 10)
        TestStep.macWaitForElement(
            titled: "Move terminal to left: winRight",
            timeout: 10,
            instance: 1
        )
        TestStep.wait(seconds: 2)
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "afterHostSplitLeftWidth",
            heightKey: "afterHostSplitLeftHeight"
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winRight",
            widthKey: "afterHostSplitRightWidth",
            heightKey: "afterHostSplitRightHeight"
        )
        TestStep.assertStoredEqual(key: "afterHostSplitLeftWidth", otherKey: "hostFullWidth")
        TestStep.assertStoredEqual(key: "afterHostSplitLeftHeight", otherKey: "hostFullHeight")
        TestStep.assertStoredEqual(key: "afterHostSplitRightWidth", otherKey: "hostRightWidth")
        TestStep.assertStoredEqual(key: "afterHostSplitRightHeight", otherKey: "hostRightHeight")

        // Viewer selection, divider movement and window geometry are all
        // presentation-only until the Viewer clicks the explicit fit button.
        TestStep.macClickButton(titled: "winLeft", instance: 1)
        TestStep.macDrag(fromX: 785, fromY: 300, toX: 1_050, toY: 300, instance: 1)
        TestStep.macResizeWindow(width: 1_100, height: 700, instance: 1)
        TestStep.wait(seconds: 2)
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "afterViewerResizeLeftWidth",
            heightKey: "afterViewerResizeLeftHeight"
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winRight",
            widthKey: "afterViewerResizeRightWidth",
            heightKey: "afterViewerResizeRightHeight"
        )
        TestStep.assertStoredEqual(key: "afterViewerResizeLeftWidth", otherKey: "hostFullWidth")
        TestStep.assertStoredEqual(key: "afterViewerResizeLeftHeight", otherKey: "hostFullHeight")
        TestStep.assertStoredEqual(key: "afterViewerResizeRightWidth", otherKey: "hostRightWidth")
        TestStep.assertStoredEqual(key: "afterViewerResizeRightHeight", otherKey: "hostRightHeight")

        // One Viewer click fits both visible terminal windows using the
        // Viewer's asymmetric split widths.
        TestStep.log("Phase 2: Viewer explicitly fits both visible windows")
        TestStep.macClickButton(
            titled: "Resize visible terminals to fit this Mac",
            instance: 1
        )
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "rslayout:winLeft",
            format: "#{pane_width}",
            notEqualTo: "${hostFullWidth}",
            timeout: 10
        )
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "rslayout:winRight",
            format: "#{pane_width}",
            notEqualTo: "${hostRightWidth}",
            timeout: 10
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "viewerFitLeftWidth",
            heightKey: "viewerFitLeftHeight"
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winRight",
            widthKey: "viewerFitRightWidth",
            heightKey: "viewerFitRightHeight"
        )
        TestStep.assertStoredNotEqual(key: "viewerFitLeftWidth", otherKey: "hostFullWidth")
        TestStep.assertStoredNotEqual(key: "viewerFitRightWidth", otherKey: "hostRightWidth")
        TestStep.assertStoredNotEqual(key: "viewerFitLeftWidth", otherKey: "viewerFitRightWidth")

        // Host geometry remains inert too. Its own button then explicitly
        // reclaims both shared windows for the larger Host viewport.
        TestStep.log("Phase 3: Host explicitly fits the same two windows")
        TestStep.macResizeWindow(width: 1_400, height: 900)
        TestStep.wait(seconds: 2)
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winRight",
            widthKey: "beforeHostFitRightWidth",
            heightKey: "beforeHostFitRightHeight"
        )
        TestStep.assertStoredEqual(key: "beforeHostFitRightWidth", otherKey: "viewerFitRightWidth")
        TestStep.assertStoredEqual(key: "beforeHostFitRightHeight", otherKey: "viewerFitRightHeight")

        TestStep.macClickButton(titled: "Resize visible terminals to fit this Mac")
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "rslayout:winLeft",
            format: "#{pane_height}",
            notEqualTo: "${viewerFitLeftHeight}",
            timeout: 10
        )
        TestStep.waitForTmuxDisplayMessageNotEqual(
            target: "rslayout:winRight",
            format: "#{pane_height}",
            notEqualTo: "${viewerFitRightHeight}",
            timeout: 10
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winLeft",
            widthKey: "hostFitLeftWidth",
            heightKey: "hostFitLeftHeight"
        )
        TestStep.tmuxStorePaneDimensions(
            target: "rslayout:winRight",
            widthKey: "hostFitRightWidth",
            heightKey: "hostFitRightHeight"
        )
        TestStep.assertStoredNotEqual(key: "hostFitLeftHeight", otherKey: "viewerFitLeftHeight")
        TestStep.assertStoredNotEqual(key: "hostFitRightHeight", otherKey: "viewerFitRightHeight")
        TestStep.macScreenshot(label: "shared-layout-host-split")
        TestStep.macScreenshot(label: "shared-layout-viewer-converged", instance: 1)

        // A Viewer may request a change, but only the Host commits it. Moving
        // the terminal left on the Viewer must therefore collapse both UIs.
        TestStep.log("Phase 4: Viewer requests collapse; Host republishes it")
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
        TestStep.log("Phase 5: Viewer opens split, then Host tmux removes winRight")
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
