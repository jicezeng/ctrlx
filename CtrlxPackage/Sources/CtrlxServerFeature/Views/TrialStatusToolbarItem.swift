#if os(macOS)
    import CtrlxCommon
    import CtrlxNetworking
    import Dependencies
    import SwiftUI

    /// Pure mapping from license state to toolbar-badge appearance. Kept free of
    /// view state so the trial/expired/urgent rules are unit-testable. `nil` means
    /// render nothing. The `isPaired` gate lives in the view (it's app state).
    enum TrialBadgeAppearance: Equatable {
        /// `urgent` → orange (≤ 2 days left), else secondary grey.
        case trial(daysLeft: Int, urgent: Bool)
        case expired
    }

    func trialBadgeAppearance(
        state: LicenseStatus.State?,
        trialDaysLeft: Int?
    ) -> TrialBadgeAppearance? {
        switch state {
        case .trial:
            guard let days = trialDaysLeft else { return nil }
            return .trial(daysLeft: days, urgent: days <= 2)
        case .expired:
            return .expired
        default:
            return nil
        }
    }

    struct TrialStatusToolbarItem: View {
        @Environment(LicenseManager.self) private var licenseManager
        @Environment(AppSettings.self) private var settings
        @State private var showingPopover = false

        var body: some View {
            if
                settings.isPaired,
                let appearance = trialBadgeAppearance(
                    state: licenseManager.status?.state,
                    trialDaysLeft: licenseManager.trialDaysLeft
                ) {
                Button {
                    showingPopover = true
                } label: {
                    Label(labelText(appearance), symbol: symbol(appearance))
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .tint(tint(appearance))
                .help(labelText(appearance))
                .accessibilityIdentifier("trial-status-badge")
                .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                    popoverContent(appearance)
                }
            }
        }

        private func labelText(_ appearance: TrialBadgeAppearance) -> String {
            switch appearance {
            case let .trial(daysLeft, _):
                "\(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
            case .expired:
                "Relay authorization required"
            }
        }

        private func symbol(_ appearance: TrialBadgeAppearance) -> Symbols {
            switch appearance {
            case .trial: .hourglass
            case .expired: .exclamationmarkTriangle
            }
        }

        private func tint(_ appearance: TrialBadgeAppearance) -> Color {
            // `tint(_:)` needs a `Color` (not the `.secondary` ShapeStyle the
            // Settings Text uses); `.gray` is the Color equivalent for the
            // non-urgent pill.
            switch appearance {
            case let .trial(_, urgent): urgent ? .orange : .gray
            case .expired: .red
            }
        }

        @ViewBuilder
        private func popoverContent(_ appearance: TrialBadgeAppearance) -> some View {
            @Bindable var licenseManager = licenseManager
            VStack(alignment: .leading, spacing: 12) {
                Text(popoverHeadline(appearance))
                    .font(.headline)
                Text(popoverBody(appearance))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Enter a key supplied by the relay operator")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("License Key", text: $licenseManager.licenseKeyField)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("trial-popover-license-key")
                    .onSubmit(activateAndDismiss)

                if case let .error(message) = licenseManager.actionState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Activate", action: activateAndDismiss)
                        .disabled(licenseManager.actionState == .working)
                        .accessibilityIdentifier("trial-popover-activate")
                }
            }
            .padding(16)
            .frame(width: 320)
        }

        private func activateAndDismiss() {
            Task {
                await licenseManager.activate()
                if licenseManager.actionState == .idle { showingPopover = false }
            }
        }

        private func popoverHeadline(_ appearance: TrialBadgeAppearance) -> String {
            switch appearance {
            case let .trial(daysLeft, _):
                "Free trial — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
            case .expired:
                "Your trial has ended"
            }
        }

        private func popoverBody(_ appearance: TrialBadgeAppearance) -> String {
            switch appearance {
            case .trial:
                "This relay requires authorization after its trial period. "
                    + "Enter a key supplied by the relay operator to keep remote access."
            case .expired:
                "Remote access is paused by this relay. Enter a key supplied by its "
                    + "operator to restore access."
            }
        }
    }
#endif
