import Testing
@testable import CtrlxNetworking

@Suite("CtrlX protocol boundary")
struct CtrlXVersionBoundaryTests {
    @Test("CtrlX 3 refuses Gallager 2.x peers")
    func minimumVersions() {
        #expect(VersionCompatibility.defaultMinRequiredHostVersion == "3.0")
        #expect(VersionCompatibility.defaultMinRequiredViewerVersion == "3.0")
        #expect(!VersionCompatibility.isCompatible(version: "2.7", minimum: "3.0"))
        #expect(VersionCompatibility.isCompatible(version: "3.0.0", minimum: "3.0"))
    }
}
