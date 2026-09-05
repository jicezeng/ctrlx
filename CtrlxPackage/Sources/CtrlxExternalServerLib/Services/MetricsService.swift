import Foundation

/// Snapshot of live gauge values queried at scrape time.
/// Computed by the route handler from existing services (no caching).
struct MetricsSnapshot: Sendable {
    let activePairs: Int
    let hostsConnected: Int
    let viewersConnected: Int
    let uptimeSeconds: Int
}

/// Tracks monotonically-increasing counters for the relay server.
/// Gauges are not stored here — they're queried live at render time.
actor MetricsService {
    private(set) var messagesRelayedTotal = 0
    private(set) var pushNotificationsTotal = 0
    private(set) var trialStartsTotal = 0
    private(set) var licenseActivationsTotal = 0
    private(set) var licenseValidationFailuresTotal = 0
    private(set) var licenseDeactivationsTotal = 0
    private(set) var blockedHostAttemptsTotal = 0
    private(set) var pausedPairingAttemptsTotal = 0

    func incrementMessagesRelayed() {
        messagesRelayedTotal &+= 1
    }

    func incrementPushNotifications() {
        pushNotificationsTotal &+= 1
    }

    func incrementTrialStarts() {
        trialStartsTotal &+= 1
    }

    func incrementLicenseActivations() {
        licenseActivationsTotal &+= 1
    }

    func incrementLicenseValidationFailures() {
        licenseValidationFailuresTotal &+= 1
    }

    func incrementLicenseDeactivations() {
        licenseDeactivationsTotal &+= 1
    }

    func incrementBlockedHostAttempts() {
        blockedHostAttemptsTotal &+= 1
    }

    func incrementPausedPairingAttempts() {
        pausedPairingAttemptsTotal &+= 1
    }

    /// Render the full Prometheus text exposition for a scrape.
    func render(snapshot: MetricsSnapshot, buildVersion: String) -> String {
        var lines: [String] = []

        lines.append("# HELP ctrlx_messages_relayed_total Total encrypted messages relayed since process start.")
        lines.append("# TYPE ctrlx_messages_relayed_total counter")
        lines.append("ctrlx_messages_relayed_total \(messagesRelayedTotal)")

        lines.append("# HELP ctrlx_push_notifications_total Total push notifications sent to APNs since process start.")
        lines.append("# TYPE ctrlx_push_notifications_total counter")
        lines.append("ctrlx_push_notifications_total \(pushNotificationsTotal)")

        lines.append("# HELP ctrlx_trial_starts_total Hosted-relay trials auto-started since process start.")
        lines.append("# TYPE ctrlx_trial_starts_total counter")
        lines.append("ctrlx_trial_starts_total \(trialStartsTotal)")

        lines.append("# HELP ctrlx_license_activations_total License keys activated since process start.")
        lines.append("# TYPE ctrlx_license_activations_total counter")
        lines.append("ctrlx_license_activations_total \(licenseActivationsTotal)")

        lines.append("# HELP ctrlx_license_deactivations_total License activations released since process start.")
        lines.append("# TYPE ctrlx_license_deactivations_total counter")
        lines.append("ctrlx_license_deactivations_total \(licenseDeactivationsTotal)")

        lines.append("# HELP ctrlx_license_validation_failures_total Failed license validations/activations since process start.")
        lines.append("# TYPE ctrlx_license_validation_failures_total counter")
        lines.append("ctrlx_license_validation_failures_total \(licenseValidationFailuresTotal)")

        lines.append("# HELP ctrlx_blocked_host_attempts_total Host connections/registrations rejected for lack of entitlement.")
        lines.append("# TYPE ctrlx_blocked_host_attempts_total counter")
        lines.append("ctrlx_blocked_host_attempts_total \(blockedHostAttemptsTotal)")

        lines.append("# HELP ctrlx_paused_pairing_attempts_total Pairing registrations refused by the pairing-pause switch.")
        lines.append("# TYPE ctrlx_paused_pairing_attempts_total counter")
        lines.append("ctrlx_paused_pairing_attempts_total \(pausedPairingAttemptsTotal)")

        lines.append("# HELP ctrlx_active_pairs Number of currently-paired devices.")
        lines.append("# TYPE ctrlx_active_pairs gauge")
        lines.append("ctrlx_active_pairs \(snapshot.activePairs)")

        lines.append("# HELP ctrlx_ws_connections Active WebSocket connections by device type.")
        lines.append("# TYPE ctrlx_ws_connections gauge")
        lines.append("ctrlx_ws_connections{device_type=\"host\"} \(snapshot.hostsConnected)")
        lines.append("ctrlx_ws_connections{device_type=\"viewer\"} \(snapshot.viewersConnected)")

        lines.append("# HELP ctrlx_uptime_seconds Process uptime in seconds.")
        lines.append("# TYPE ctrlx_uptime_seconds gauge")
        lines.append("ctrlx_uptime_seconds \(snapshot.uptimeSeconds)")

        lines.append("# HELP ctrlx_build_info Build version (always 1).")
        lines.append("# TYPE ctrlx_build_info gauge")
        lines.append("ctrlx_build_info{version=\"\(Self.escapeLabelValue(buildVersion))\"} 1")

        return lines.joined(separator: "\n") + "\n"
    }

    /// Escape a Prometheus label value per the text exposition format:
    /// backslash, double-quote, and newline must be escaped.
    /// https://prometheus.io/docs/instrumenting/exposition_formats/#text-format-details
    static func escapeLabelValue(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            default: out.append(ch)
            }
        }
        return out
    }
}
