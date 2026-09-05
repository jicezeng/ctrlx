import Foundation
import Testing
import VaporTesting
@testable import CtrlxExternalServerLib

@Suite("CtrlX Relay distribution identity")
struct RelayDistributionIdentityTests {
    @Test("Environment files use the documented priority without merging lower files")
    func environmentFilePriority() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctrlx-env-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try "VALUE=production\nONLY_PRODUCTION=ignored\n".write(
            to: directory.appendingPathComponent(".env.production"),
            atomically: true,
            encoding: .utf8
        )
        try "VALUE=local\nQUOTED=\"hello world\"\n".write(
            to: directory.appendingPathComponent(".env.local"),
            atomically: true,
            encoding: .utf8
        )

        let result = try RelayEnvironmentLoader.load(
            from: directory,
            processEnvironment: ["VALUE": "process", "INHERITED": "kept"]
        )

        #expect(result.source?.lastPathComponent == ".env.local")
        #expect(result.values["VALUE"] == "local")
        #expect(result.values["QUOTED"] == "hello world")
        #expect(result.values["INHERITED"] == "kept")
        #expect(result.values["ONLY_PRODUCTION"] == nil)
    }

    @Test("Version and source endpoints expose the exact corresponding source")
    func sourceEndpoints() async throws {
        let revision = "0123456789abcdef0123456789abcdef01234567"
        let dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctrlx-relay-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        try await withApp(configure: { app in
            try await configure(app, env: [
                "CTRLX_VERSION": "3.0.0",
                "CTRLX_PROTOCOL_VERSION": "3.0",
                "CTRLX_SOURCE_REVISION": revision,
                "CTRLX_SOURCE_REPOSITORY": "https://github.com/jicezeng/CtrlX",
                "DATA_DIRECTORY": dataDirectory.path,
            ])
        }) { app in
            try await app.testing().test(.GET, "version") { response in
                #expect(response.status == .ok)
                let body = try response.content.decode(VersionResponse.self)
                #expect(body.name == "CtrlX Relay")
                #expect(body.version == "3.0.0")
                #expect(body.commit == revision)
                #expect(body.protocolVersion == "3.0")
                #expect(body.source == "https://github.com/jicezeng/CtrlX/tree/\(revision)")
                #expect(body.sourceIsExact)
                #expect(body.license == "AGPL-3.0-only")
            }

            try await app.testing().test(.GET, "source") { response in
                #expect(response.status == .ok)
                let body = try response.content.decode(SourceResponse.self)
                #expect(body.commit == revision)
                #expect(body.exact)
                #expect(body.license == "AGPL-3.0-only")
            }
        }
    }

    @Test("Development source metadata is honest about being mutable")
    func developmentSourceIsNotExact() {
        let info = RelayBuildInfo.fromEnvironment([:])
        #expect(info.sourceURL == RelayBuildInfo.defaultRepository)
        #expect(!info.hasExactSource)
    }
}
