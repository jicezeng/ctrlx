import Foundation

struct VoiceCorrectionBenchmarkSample: Sendable {
    let id: String
    let recognition: VoiceRecognitionResult
    let terminalContext: String
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

    static let samples = [
        VoiceCorrectionBenchmarkSample(
            id: "ctrlx-introduction",
            recognition: VoiceRecognitionResult(
                primaryTranscript: "好的 ，这是一句测试 CTRS是一个 APP由征记册开发它支持语音输入通过。外s20出发"
            ),
            terminalContext: """
            当前项目是 CtrlX，一个 terminal remote-control App。
            开发者姓名写作“曾计策”。语音输入通过 Voice 按钮触发。
            """,
            requiredTerms: ["CtrlX", "曾计策", "Voice", "触发"],
            rejectedTerms: ["CTRS", "征记册", "外s20", "出发"]
        ),
        VoiceCorrectionBenchmarkSample(
            id: "model-comparison-request",
            recognition: VoiceRecognitionResult(
                primaryTranscript: "我这句话是切换到多个 2.0 Pro，你能不能把我书的原文记录下来然后用这个来自动测试一下哪个模型的效果最好。啊 ，7RS是邮政计策开发的支持语音输入通过外s按钮进行厨房"
            ),
            terminalContext: """
            当前选择的是豆包 2.0 Pro。当前项目是 CtrlX。
            CtrlX 由曾计策开发，语音输入通过 Voice 按钮触发。
            """,
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
    import ClaudeSpyEncryption
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
