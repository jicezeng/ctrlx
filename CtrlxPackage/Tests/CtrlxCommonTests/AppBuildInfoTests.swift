import Testing
@testable import CtrlxCommon

@Suite("App build information")
struct AppBuildInfoTests {
    @Test("Displays version, build, timestamp, and source revision")
    func completeBuildIdentity() {
        let info = AppBuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "3.0.0",
            "CFBundleVersion": "1",
            AppBuildInfo.buildStampKey: "20260808-2040",
            AppBuildInfo.sourceRevisionKey: "919c7772928531d4d0bb266bdf275691d361901e",
        ])

        #expect(
            info.displayVersion
                == "3.0.0 (1) · 20260808-2040 · 919c77729285"
        )
        #expect(
            info.correspondingSourceURL.absoluteString
                .hasSuffix("/tree/919c7772928531d4d0bb266bdf275691d361901e")
        )
    }

    @Test("Does not claim a mutable short revision is exact source")
    func rejectsShortRevisionForSourceLink() {
        let info = AppBuildInfo(infoDictionary: [
            AppBuildInfo.sourceRevisionKey: "919c777",
        ])

        #expect(info.correspondingSourceURL == ProductIdentity.sourceURL)
    }

    @Test("Falls back to the standard version when build metadata is absent")
    func standardVersionFallback() {
        let info = AppBuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "3.0.0",
            "CFBundleVersion": "1",
        ])

        #expect(info.displayVersion == "3.0.0 (1)")
    }

    @Test("Ignores empty build metadata")
    func emptyMetadata() {
        let info = AppBuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "3.0.0",
            "CFBundleVersion": "1",
            AppBuildInfo.buildStampKey: "  ",
            AppBuildInfo.sourceRevisionKey: "\n",
        ])

        #expect(info.displayVersion == "3.0.0 (1)")
    }

    @Test("Handles missing standard version fields")
    func missingStandardVersion() {
        #expect(AppBuildInfo(infoDictionary: nil).displayVersion == "Unknown version")
        #expect(
            AppBuildInfo(infoDictionary: ["CFBundleVersion": "40"]).displayVersion
                == "Build 40"
        )
    }
}
