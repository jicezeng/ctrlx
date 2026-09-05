#if os(macOS)
    import AppKit
    import CtrlxCommon
    import SwiftUI

    /// Custom About window with CtrlX build identity and upstream provenance.
    public struct AboutWindowView: View {
        public init() { }

        public var body: some View {
            VStack(spacing: 16) {
                // App icon and name
                headerSection

                Divider()

                provenanceSection

                // Links
                linksSection
            }
            .padding(24)
            .frame(width: 420)
        }

        // MARK: - Header

        @ViewBuilder
        private var headerSection: some View {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                Text(ProductIdentity.name)
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version \(AppBuildInfo.current.displayVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        // MARK: - Provenance

        @ViewBuilder
        private var provenanceSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Independent open-source distribution")
                    .font(.headline)

                Text("CtrlX is based on Gallager and distributed under GNU AGPL-3.0. It is not affiliated with or endorsed by the Gallager project.")

                Text("Forked from commit \(ProductIdentity.forkCommit) on \(ProductIdentity.forkDate).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // MARK: - Links

        @ViewBuilder
        private var linksSection: some View {
            HStack(spacing: 16) {
                Link(destination: AppBuildInfo.current.correspondingSourceURL) {
                    Label("CtrlX Source", symbol: .linkCircle)
                }

                Link(destination: ProductIdentity.upstreamURL) {
                    Label("Gallager Upstream", symbol: .linkCircle)
                }
            }
            .font(.callout)
        }
    }
#endif
