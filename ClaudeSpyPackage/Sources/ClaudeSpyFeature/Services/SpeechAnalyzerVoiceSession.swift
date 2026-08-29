#if os(iOS)
    import AVFoundation
    import Foundation
    import Speech

    @available(iOS 26.0, *)
    @MainActor
    final class SpeechAnalyzerVoiceSession {
        typealias UpdateHandler = @MainActor @Sendable (String) -> Void

        private let audioEngine = AVAudioEngine()
        private let contextualTerms: [String]

        private var analyzer: SpeechAnalyzer?
        private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
        private var resultTasks: [Task<Void, Never>] = []
        private var liveResultError: Error?
        private var finalResultError: Error?
        private var liveTranscriptState = VoiceInputTranscriptState()
        private var finalTranscriptState = VoiceInputTranscriptState()
        private var stableTranscriptState = VoiceInputStableTranscriptState()
        private var isFinishing = false
        private var hasAudioTap = false

        init(contextualTerms: [String]) {
            self.contextualTerms = contextualTerms
        }

        func start(onUpdate: @escaping UpdateHandler) async throws {
            let transcribers = try await ModernSpeechTranscribers.preferred(for: preferredLocale)
            let modules = transcribers.modules

            if let installationRequest = try await AssetInventory.assetInstallationRequest(
                supporting: modules
            ) {
                try await installationRequest.downloadAndInstall()
            }

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: modules
            ) else {
                throw SpeechAnalyzerVoiceSessionError.compatibleAudioFormatUnavailable
            }

            let options = SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .lingering
            )
            let analyzer = SpeechAnalyzer(modules: modules, options: options)
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualTerms
            try await analyzer.setContext(context)
            try await analyzer.prepareToAnalyze(in: analyzerFormat)

            let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.analyzer = analyzer
            self.inputContinuation = inputContinuation
            resultTasks = [
                makeResultTask(for: transcribers.live, role: .live, onUpdate: onUpdate),
                makeResultTask(for: transcribers.final, role: .final, onUpdate: onUpdate),
            ]

            do {
                try await analyzer.start(inputSequence: inputSequence)
                try startAudioInput(
                    analyzerFormat: analyzerFormat,
                    inputContinuation: inputContinuation
                )
            } catch {
                await cancel()
                throw error
            }
        }

        func finish() async throws -> String {
            isFinishing = true
            stopAudioInput()
            inputContinuation?.finish()
            inputContinuation = nil

            do {
                if let analyzer {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
                for resultTask in resultTasks {
                    await resultTask.value
                }

                let accurateText = finalTranscriptState.text
                let liveText = liveTranscriptState.text
                let completedText = accurateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? liveText
                    : accurateText

                if completedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let resultError = finalResultError ?? liveResultError
                {
                    throw resultError
                }

                cleanup()
                return completedText
            } catch {
                await cancel()
                throw error
            }
        }

        func cancel() async {
            stopAudioInput()
            inputContinuation?.finish()
            inputContinuation = nil
            await analyzer?.cancelAndFinishNow()
            resultTasks.forEach { $0.cancel() }
            cleanup()
        }

        private var preferredLocale: Locale {
            let identifier = Locale.preferredLanguages.first ?? Locale.current.identifier
            return Locale(identifier: identifier)
        }

        private func makeResultTask(
            for transcriber: ModernSpeechTranscriber,
            role: ModernSpeechResultRole,
            onUpdate: @escaping UpdateHandler
        ) -> Task<Void, Never> {
            switch transcriber {
            case let .speech(transcriber):
                Task { @MainActor [weak self] in
                    do {
                        for try await result in transcriber.results {
                            self?.receive(
                                text: String(result.text.characters),
                                isFinal: result.isFinal,
                                role: role,
                                onUpdate: onUpdate
                            )
                        }
                    } catch is CancellationError {
                    } catch {
                        self?.store(error, for: role)
                    }
                }

            case let .dictation(transcriber):
                Task { @MainActor [weak self] in
                    do {
                        for try await result in transcriber.results {
                            self?.receive(
                                text: String(result.text.characters),
                                isFinal: result.isFinal,
                                role: role,
                                onUpdate: onUpdate
                            )
                        }
                    } catch is CancellationError {
                    } catch {
                        self?.store(error, for: role)
                    }
                }
            }
        }

        private func receive(
            text: String,
            isFinal: Bool,
            role: ModernSpeechResultRole,
            onUpdate: UpdateHandler
        ) {
            switch role {
            case .live:
                let candidate = liveTranscriptState.receive(text, isFinal: isFinal)
                guard !isFinishing else { return }
                onUpdate(stableTranscriptState.receive(candidate))
            case .final:
                finalTranscriptState.receive(text, isFinal: isFinal)
            }
        }

        private func store(_ error: Error, for role: ModernSpeechResultRole) {
            switch role {
            case .live:
                liveResultError = error
            case .final:
                finalResultError = error
            }
        }

        private func startAudioInput(
            analyzerFormat: AVAudioFormat,
            inputContinuation: AsyncStream<AnalyzerInput>.Continuation
        ) throws {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                throw SpeechAnalyzerVoiceSessionError.microphoneUnavailable
            }
            guard let converter = AnalyzerAudioBufferConverter(
                inputFormat: inputFormat,
                outputFormat: analyzerFormat
            ) else {
                throw SpeechAnalyzerVoiceSessionError.audioConverterUnavailable
            }

            inputNode.installTap(
                onBus: 0,
                bufferSize: 4_096,
                format: inputFormat
            ) { @Sendable buffer, _ in
                guard let convertedBuffer = converter.convert(buffer) else { return }
                inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
            }
            hasAudioTap = true

            audioEngine.prepare()
            try audioEngine.start()
        }

        private func stopAudioInput() {
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            if hasAudioTap {
                audioEngine.inputNode.removeTap(onBus: 0)
                hasAudioTap = false
            }
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }

        private func cleanup() {
            analyzer = nil
            resultTasks = []
            liveResultError = nil
            finalResultError = nil
            liveTranscriptState.reset()
            finalTranscriptState.reset()
            stableTranscriptState.reset()
            isFinishing = false
        }
    }

    @available(iOS 26.0, *)
    private enum ModernSpeechResultRole {
        case live
        case final
    }

    @available(iOS 26.0, *)
    private struct ModernSpeechTranscribers {
        let live: ModernSpeechTranscriber
        let final: ModernSpeechTranscriber

        var modules: [any SpeechModule] {
            [live.module, final.module]
        }

        static func preferred(for locale: Locale) async throws -> Self {
            let speechLocale: Locale?
            if SpeechTranscriber.isAvailable {
                speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            } else {
                speechLocale = nil
            }
            let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale)

            if let dictationLocale {
                let live: ModernSpeechTranscriber
                if let speechLocale {
                    live = .speech(
                        SpeechTranscriber(
                            locale: speechLocale,
                            preset: .progressiveTranscription
                        )
                    )
                } else {
                    live = .dictation(
                        DictationTranscriber(
                            locale: dictationLocale,
                            preset: .progressiveLongDictation
                        )
                    )
                }

                return Self(
                    live: live,
                    final: .dictation(
                        DictationTranscriber(
                            locale: dictationLocale,
                            preset: .longDictation
                        )
                    )
                )
            }

            if let speechLocale {
                return Self(
                    live: .speech(
                        SpeechTranscriber(
                            locale: speechLocale,
                            preset: .progressiveTranscription
                        )
                    ),
                    final: .speech(
                        SpeechTranscriber(
                            locale: speechLocale,
                            preset: .transcriptionWithAlternatives
                        )
                    )
                )
            }

            throw SpeechAnalyzerVoiceSessionError.unsupportedLanguage
        }
    }

    @available(iOS 26.0, *)
    private enum ModernSpeechTranscriber {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case let .speech(transcriber):
                transcriber
            case let .dictation(transcriber):
                transcriber
            }
        }
    }

    @available(iOS 26.0, *)
    private final class AnalyzerAudioBufferConverter: @unchecked Sendable {
        private let inputFormat: AVAudioFormat
        private let outputFormat: AVAudioFormat
        private let converter: AVAudioConverter?
        private let lock = NSLock()

        init?(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
            self.inputFormat = inputFormat
            self.outputFormat = outputFormat

            if inputFormat == outputFormat {
                converter = nil
            } else {
                guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                    return nil
                }
                self.converter = converter
            }
        }

        func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            lock.withLock {
                guard let converter else { return buffer }

                let sampleRateRatio = outputFormat.sampleRate / inputFormat.sampleRate
                let frameCapacity = AVAudioFrameCount(
                    ceil(Double(buffer.frameLength) * sampleRateRatio) + 1
                )
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: frameCapacity
                ) else { return nil }

                var conversionError: NSError?
                var suppliedInput = false
                let status = converter.convert(
                    to: outputBuffer,
                    error: &conversionError
                ) { _, inputStatus in
                    guard !suppliedInput else {
                        inputStatus.pointee = .noDataNow
                        return nil
                    }
                    suppliedInput = true
                    inputStatus.pointee = .haveData
                    return buffer
                }

                guard
                    conversionError == nil,
                    status != .error,
                    outputBuffer.frameLength > 0
                else { return nil }

                return outputBuffer
            }
        }
    }

    @available(iOS 26.0, *)
    private enum SpeechAnalyzerVoiceSessionError: LocalizedError {
        case audioConverterUnavailable
        case compatibleAudioFormatUnavailable
        case microphoneUnavailable
        case unsupportedLanguage

        var errorDescription: String? {
            switch self {
            case .audioConverterUnavailable:
                "Unable to convert microphone audio for speech recognition."
            case .compatibleAudioFormatUnavailable:
                "No compatible speech recognition audio format is available."
            case .microphoneUnavailable:
                "The microphone is unavailable."
            case .unsupportedLanguage:
                "Speech recognition does not support the current language."
            }
        }
    }
#endif
