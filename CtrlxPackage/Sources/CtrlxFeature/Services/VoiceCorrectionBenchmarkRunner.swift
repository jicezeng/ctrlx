import Foundation

struct VoiceCorrectionBenchmarkSample: Sendable {
    let id: String
    let recognition: VoiceRecognitionResult
    let terminalContext: String?
    let requiredTerms: [String]
    let rejectedTerms: [String]
}

struct VoiceCorrectionBenchmarkScore: Equatable, Sendable {
    let requiredTermHits: Int
    let rejectedTermHits: Int

    var value: Int {
        requiredTermHits * 10 - rejectedTermHits * 6
    }
}

struct VoiceCorrectionModelTestResult: Identifiable, Equatable, Sendable {
    let modelID: String
    let score: Int
    let maximumScore: Int
    let requiredTermHits: Int
    let rejectedTermHits: Int
    let elapsedSeconds: TimeInterval
    let sampleCount: Int

    var id: String { modelID }

    var averageElapsedSeconds: TimeInterval {
        guard sampleCount > 0 else { return 0 }
        return elapsedSeconds / Double(sampleCount)
    }
}

enum VoiceCorrectionBenchmark {
    static let maximumTestedModelCount = 12

    private static let ctrlXProjectTerminalContext = """
    Last login: Fri Sep  4 08:41:12 on ttys003
    developer@mac ctrlx % pwd
    /Users/developer/Projects/coding/ctrlx
    developer@mac ctrlx % git status --short --branch
    ## main...origin/main [ahead 1]
     M CtrlxPackage/Sources/CtrlxFeature/Models/VoiceRecognitionResult.swift
     M CtrlxPackage/Sources/CtrlxFeature/Services/VoiceTranscriptCorrector.swift
     M CtrlxPackage/Sources/CtrlxFeature/Views/VoiceInputButton.swift
    developer@mac ctrlx % git log -4 --format='%h | %an | %s'
    8790bdd | 曾计策 | feat(ios): add BYOK voice correction benchmarking
    8d21f53 | CtrlX CI | fix(ios): preserve terminal scrollback history
    61cdb7a | CtrlX CI | fix(host): refresh idle presence
    3a8d4c1 | CtrlX CI | fix(mac): ignore stale pane resize
    developer@mac ctrlx % rg -n 'Voice Input|VoiceInputButton' CtrlxPackage/Sources
    CtrlxPackage/Sources/CtrlxFeature/Views/VoiceInputButton.swift:561: .accessibilityLabel("Voice Input")
    CtrlxPackage/Sources/CtrlxFeature/Views/VoiceInputButton.swift:679: struct TerminalVoiceInputButton: View {
    CtrlxPackage/Sources/CtrlxFeature/Views/TerminalKeyboardBar.swift:94: Text("Voice")
    developer@mac ctrlx % swift test --package-path CtrlxPackage --filter VoiceInputTextComposerTests
    Building for debugging...
    Build complete! (2.18s)
    Test Suite 'Voice input text composer' started
    Test Case 'appends finalized transcript without replacing existing input' passed
    Test Case 'keeps stable partial transcript prefixes' passed
    Test Case 'captures recent terminal text for final correction' passed
    Test Suite 'Voice input text composer' passed
    Executed 12 tests, with 0 failures in 0.081 seconds
    developer@mac ctrlx % sed -n '535,710p' CtrlxPackage/Sources/CtrlxFeature/Views/VoiceInputButton.swift
    struct VoiceInputButton: View {
        @Environment(IOSSettings.self) private var settings
        @State private var controller = VoiceInputController()
        @State private var isGestureActive = false
        // Recognition updates the existing terminal shadow document.
    }
    developer@mac ctrlx % xcodebuild -project Ctrlx.xcodeproj -scheme Ctrlx -configuration Debug -destination 'generic/platform=iOS' -skipMacroValidation build
    Resolve Package Graph
    Prepare packages
    Compile VoiceRecognitionResult.swift
    Compile VoiceTranscriptCorrector.swift
    Compile VoiceInputButton.swift
    Link CtrlX
    CodeSign CtrlX.app
    ** BUILD SUCCEEDED **
    developer@mac ctrlx % git diff --stat
     VoiceRecognitionResult.swift   | 34 ++++++++++++++++++++++++++++++----
     VoiceTranscriptCorrector.swift | 12 ++++--------
     VoiceInputButton.swift         |  2 +-
     3 files changed, 35 insertions(+), 13 deletions(-)
    developer@mac ctrlx % git config user.name
    曾计策
    developer@mac ctrlx % defaults read com.jicezeng.ctrlx VoiceCorrectionProvider
    volcengineArk
    developer@mac ctrlx % rg -n 'CtrlX' README.md | head
    1:# CtrlX
    5:> Your tmux, Your Agent, everywhere.
    9:CtrlX is a tmux-native, cross-device terminal.
    developer@mac ctrlx %
    """

    private static let modelBenchmarkTerminalContext = """
    developer@mac ctrlx % pwd
    /Users/developer/Projects/coding/ctrlx
    developer@mac ctrlx % git status --short --branch
    ## main...origin/main [ahead 1]
    developer@mac ctrlx % log stream --style compact --predicate 'subsystem == "com.jicezeng.ctrlx"'
    09:21:03.124 CtrlX VoiceInput correction started context=true
    09:21:04.862 CtrlX corrector=BYOK provider=Volcengine Ark model=deepseek-v4-pro-ga-260813
    09:21:06.741 CtrlX correction finished changed=true elapsed=1.87s
    09:22:14.201 CtrlX VoiceInput correction started context=true
    09:22:15.925 CtrlX corrector=BYOK provider=Volcengine Ark model=doubao-seed-2-0-lite-260215
    09:22:17.801 CtrlX correction finished changed=true elapsed=1.88s
    developer@mac ctrlx % curl -s https://ark.cn-beijing.volces.com/api/v3/models | jq -r '.data[].id' | rg 'doubao-seed-2-0|deepseek-v4'
    deepseek-v4-flash-260425
    deepseek-v4-flash-ga-260731
    deepseek-v4-pro-260425
    deepseek-v4-pro-ga-260813
    doubao-seed-2-0-code-preview-260215
    doubao-seed-2-0-lite-260215
    doubao-seed-2-0-lite-260428
    doubao-seed-2-0-mini-260215
    doubao-seed-2-0-mini-260428
    doubao-seed-2-0-pro-260215
    doubao-seed-2-0-pro-260428
    developer@mac ctrlx % rg -n 'recommendedModelIDs' CtrlxPackage/Sources/CtrlxFeature
    Models/VoiceCorrectionSettingsModel.swift:41: models = provider.recommendedModelIDs
    Services/VoiceCorrectionProviderClient.swift:28: var recommendedModelIDs: [String] {
    developer@mac ctrlx % sed -n '20,52p' CtrlxPackage/Sources/CtrlxFeature/Services/VoiceCorrectionProviderClient.swift
    case .volcengineArk:
        [
            "deepseek-v4-pro-ga-260813",
            "doubao-seed-2-0-lite-260215",
            "deepseek-v4-flash-260425",
            "deepseek-v4-pro-260425",
            "doubao-seed-2-0-code-preview-260215",
        ]
    developer@mac ctrlx % swift test --package-path CtrlxPackage --filter VoiceCorrectionProviderClientTests
    Building for debugging...
    Build complete! (1.71s)
    Test Suite 'Voice correction provider client' started
    Test Case 'Each provider exposes five curated models' passed
    Test Case 'Ranks canonical term recovery and residual recognition errors' passed
    Test Case 'Ranks score before latency' passed
    Test Case 'Uses the OpenAI-compatible Responses API' passed
    Test Suite 'Voice correction provider client' passed
    Executed 8 tests, with 0 failures in 0.063 seconds
    developer@mac ctrlx % git log -1 --format='%an <%ae>'
    曾计策 <developer@example.invalid>
    developer@mac ctrlx % rg -n 'Voice Input' CtrlxPackage/Sources/CtrlxFeature
    Views/TerminalKeyboardBar.swift:94: Text("Voice")
    Views/VoiceInputButton.swift:561: .accessibilityLabel("Voice Input")
    developer@mac ctrlx % rg -n '2.0 Pro|model test' docs CtrlxPackage/Sources/CtrlxFeature | head
    CtrlxPackage/Sources/CtrlxFeature/Views/VoiceCorrectionSettingsSection.swift:72: Label("Test Provider Models", systemImage: "gauge.with.dots.needle.50percent")
    CtrlxPackage/Sources/CtrlxFeature/Models/VoiceCorrectionSettingsModel.swift:118: statusMessage = "Testing provider models"
    developer@mac ctrlx %
    """

    static let samples = [
        VoiceCorrectionBenchmarkSample(
            id: "ctrlx-introduction",
            recognition: VoiceRecognitionResult(
                primaryTranscript: "好的 ，这是一句测试 CTRS是一个 APP由征记册开发它支持语音输入通过。外s20出发"
            ),
            terminalContext: ctrlXProjectTerminalContext,
            requiredTerms: ["CtrlX", "曾计策", "Voice", "触发"],
            rejectedTerms: ["CTRS", "征记册", "外s20", "出发"]
        ),
        VoiceCorrectionBenchmarkSample(
            id: "model-comparison-request",
            recognition: VoiceRecognitionResult(
                primaryTranscript: "我这句话是切换到多个 2.0 Pro，你能不能把我书的原文记录下来然后用这个来自动测试一下哪个模型的效果最好。啊 ，7RS是邮政计策开发的支持语音输入通过外s按钮进行厨房"
            ),
            terminalContext: modelBenchmarkTerminalContext,
            requiredTerms: ["豆包", "2.0 Pro", "CtrlX", "曾计策", "Voice", "触发"],
            rejectedTerms: [
                "多个 2.0 Pro",
                "多个2.0 Pro",
                "多个豆包",
                "书的原文",
                "7RS",
                "邮政计策",
                "有真计策",
                "外s",
                "厨房",
            ]
        ),
        VoiceCorrectionBenchmarkSample(
            id: "general-homophones-without-context",
            recognition: VoiceRecognitionResult(
                primaryTranscript: "我觉得这些相信的词明显跟整个语句的意思不匹配，你再认真优化一半"
            ),
            terminalContext: nil,
            requiredTerms: ["相近的词", "优化一下"],
            rejectedTerms: ["相信的词", "优化一半"]
        ),
    ]

    static var maximumScore: Int {
        samples.reduce(0) { total, sample in
            total + sample.requiredTerms.count * 10
        }
    }

    static func score(
        _ output: String,
        for sample: VoiceCorrectionBenchmarkSample
    ) -> VoiceCorrectionBenchmarkScore {
        VoiceCorrectionBenchmarkScore(
            requiredTermHits: sample.requiredTerms.count(where: output.contains),
            rejectedTermHits: sample.rejectedTerms.count(where: output.contains)
        )
    }

    static func candidateModelIDs(
        for provider: VoiceCorrectionProvider,
        from availableModelIDs: [String],
        selectedModelID: String
    ) -> [String] {
        let preferredFamilies: [String]
        switch provider {
        case .volcengineArk:
            preferredFamilies = ["doubao-seed-2-0", "deepseek-v4"]
        }

        var candidates = availableModelIDs.filter { modelID in
            let normalized = modelID.lowercased()
            return preferredFamilies.contains(where: normalized.contains)
        }

        if !selectedModelID.isEmpty,
           availableModelIDs.contains(selectedModelID),
           !candidates.contains(selectedModelID)
        {
            candidates.append(selectedModelID)
        }

        return Array(Set(candidates))
            .sorted()
            .prefix(maximumTestedModelCount)
            .map(\.self)
    }

    static func evaluate(
        modelID: String,
        provider: VoiceCorrectionProvider,
        apiKey: String,
        client: VoiceCorrectionProviderClient
    ) async throws -> VoiceCorrectionModelTestResult {
        guard let selection = VoiceCorrectionSelection(
            provider: provider,
            modelID: modelID
        ) else {
            throw VoiceCorrectionBenchmarkError.invalidModelID
        }

        var scoreValue = 0
        var requiredTermHits = 0
        var rejectedTermHits = 0
        var elapsedSeconds: TimeInterval = 0

        for sample in samples {
            let start = Date()
            let candidate = try await client.correct(
                recognition: sample.recognition,
                terminalContext: sample.terminalContext,
                contextualTerms: VoiceInputVocabulary.terms,
                localeIdentifier: "zh-Hans-CN",
                selection: selection,
                apiKey: apiKey
            )
            elapsedSeconds += Date().timeIntervalSince(start)
            let output = VoiceTranscriptCorrectionPolicy.accepted(
                candidate,
                replacing: sample.recognition.bestAvailableTranscript
            )
            let sampleScore = score(output, for: sample)
            scoreValue += sampleScore.value
            requiredTermHits += sampleScore.requiredTermHits
            rejectedTermHits += sampleScore.rejectedTermHits
        }

        return VoiceCorrectionModelTestResult(
            modelID: modelID,
            score: scoreValue,
            maximumScore: maximumScore,
            requiredTermHits: requiredTermHits,
            rejectedTermHits: rejectedTermHits,
            elapsedSeconds: elapsedSeconds,
            sampleCount: samples.count
        )
    }

    static func ranked(
        _ results: [VoiceCorrectionModelTestResult]
    ) -> [VoiceCorrectionModelTestResult] {
        results.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.rejectedTermHits != $1.rejectedTermHits {
                return $0.rejectedTermHits < $1.rejectedTermHits
            }
            return $0.elapsedSeconds < $1.elapsedSeconds
        }
    }
}

private enum VoiceCorrectionBenchmarkError: LocalizedError {
    case invalidModelID

    var errorDescription: String? {
        "The provider returned an invalid model ID."
    }
}

#if os(iOS) && DEBUG
    import CtrlxEncryption
    import Dependencies

    actor VoiceCorrectionBenchmarkRunner {
        static let shared = VoiceCorrectionBenchmarkRunner()

        @Dependency(SecretsService.self) private var secrets

        private var hasStarted = false

        func runIfRequested(selectedModelID: String) async {
            guard CommandLine.arguments.contains("--voice-correction-benchmark"),
                  !hasStarted
            else { return }
            hasStarted = true

            let provider = VoiceCorrectionProvider.volcengineArk
            let account = VoiceCorrectionCredentials.apiKeyAccount(for: provider)

            do {
                guard let apiKey = try await secrets.loadSecret(account), !apiKey.isEmpty else {
                    print("VOICE_BENCHMARK|error=missing-api-key")
                    return
                }

                let client = VoiceCorrectionProviderClient()
                let availableModelIDs = try await client.fetchModels(
                    provider: provider,
                    apiKey: apiKey
                )
                let modelIDs = VoiceCorrectionBenchmark.candidateModelIDs(
                    for: provider,
                    from: availableModelIDs,
                    selectedModelID: selectedModelID
                )
                guard !modelIDs.isEmpty else {
                    print("VOICE_BENCHMARK|error=no-candidate-models")
                    return
                }

                print("VOICE_BENCHMARK|start|models=\(modelIDs.count)")
                var results: [VoiceCorrectionModelTestResult] = []
                for modelID in modelIDs {
                    do {
                        let result = try await VoiceCorrectionBenchmark.evaluate(
                            modelID: modelID,
                            provider: provider,
                            apiKey: apiKey,
                            client: client
                        )
                        results.append(result)
                    } catch {
                        print("VOICE_BENCHMARK|model=\(modelID)|error=\(error.localizedDescription)")
                    }
                }

                for (index, result) in VoiceCorrectionBenchmark.ranked(results).enumerated() {
                    print(
                        "VOICE_BENCHMARK|rank=\(index + 1)|model=\(result.modelID)|score=\(result.score)/\(result.maximumScore)|elapsed=\(result.elapsedSeconds)"
                    )
                }
                print("VOICE_BENCHMARK|finished")
            } catch {
                print("VOICE_BENCHMARK|error=\(error.localizedDescription)")
            }
        }
    }
#endif
