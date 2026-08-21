import Foundation

/// E2E scenario for the Host-owned shared terminal layout.
///
/// The app-level left/right arrangement must converge on every Mac without a
/// Viewer resizing the Host's tmux windows. Native tmux pane layout is outside
/// this protocol and remains synchronized by the existing `PaneState` path.
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
        TestStep.macResizeWindow(width: 1_300, height: 700)
        TestStep.macWaitForElement(titled: "rslayout", timeout: 15)
        TestStep.macClickButton(titled: "rslayout")
        TestStep.macWaitForElement(titled: "winLeft", timeout: 10)
        TestStep.macWaitForElement(titled: "winRight", timeout: 10)

        Shortcut.openPanesWindow(instance: 1)
        TestStep.macResizeWindow(width: 1_300, height: 700, instance: 1)
        TestStep.macWaitForElement(titled: "rslayout", timeout: 15, instance: 1)
        TestStep.macClickButton(titled: "rslayout", instance: 1)
        TestStep.macWaitForElement(titled: "winLeft", timeout: 10, instance: 1)
        TestStep.macWaitForElement(titled: "winRight", timeout: 10, instance: 1)

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
