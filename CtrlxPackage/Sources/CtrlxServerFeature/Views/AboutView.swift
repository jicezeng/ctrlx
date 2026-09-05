#if os(macOS)
    import AppKit
    import CtrlxCommon
    import SwiftUI

    /// CtrlX build, source, upstream, and license information.
    public struct AboutView: View {
        public init() { }

        public var body: some View {
            Form {
                Section("Build") {
                    LabeledContent("Version") {
                        Text(AppBuildInfo.current.displayVersion)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("Origin and license") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CtrlX is an independent distribution based on Gallager and licensed under GNU AGPL-3.0.")

                        Text("CtrlX is not affiliated with or endorsed by the Gallager project.")

                        Text("Forked from `\(ProductIdentity.forkCommit)` on \(ProductIdentity.forkDate).")
                            .textSelection(.enabled)
                    }
                    .font(.body)
                }

                Section("Links") {
                    Link(destination: AppBuildInfo.current.correspondingSourceURL) {
                        HStack {
                            Label("CtrlX Source", symbol: .linkCircle)
                            Spacer()
                            Text("GitHub")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Link(destination: ProductIdentity.upstreamURL) {
                        HStack {
                            Label("Gallager Upstream", symbol: .linkCircle)
                            Spacer()
                            Text("GitHub")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Link(destination: ProductIdentity.licenseURL) {
                        HStack {
                            Label("GNU AGPL-3.0", symbol: .linkCircle)
                            Spacer()
                            Text("License")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text(ThirdPartyLicense.intro)
                } header: {
                    Text("Licenses")
                }

                ForEach(ThirdPartyLicense.Usage.allCases, id: \.self) { usage in
                    Section(usage.rawValue) {
                        ForEach(ThirdPartyLicense.all(in: usage)) { license in
                            LicenseRow(license)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 400, minHeight: 300)
            .navigationTitle("About")
        }
    }

    #Preview {
        AboutView()
    }
#endif
