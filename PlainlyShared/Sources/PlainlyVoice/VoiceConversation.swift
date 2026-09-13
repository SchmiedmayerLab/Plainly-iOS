//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveLLM
public import GroveLLMOpenAIRealtime
import Observation
import os


/// A realtime voice session layered on a text conversation.
///
/// The backend pins the session to one forwarding tool, so every participant turn arrives here as a tool call,
/// is handed to `forward`, and the answer is read aloud. The text conversation stays the record; this class only
/// carries audio, keeps the participant informed, and remembers each turn for reporting.
@MainActor
@Observable
public final class VoiceConversation: VoicePresenter {
    /// Asks the backend for a session; what comes back is what the session connects with.
    public typealias Mint = @Sendable (VoiceSessionRequest) async throws -> VoiceSessionGrant
    /// Answers one participant turn from the text conversation; the result is read aloud.
    public typealias Forward = @Sendable (String) async throws -> String

    private enum Connection: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    private static let logger = Logger(subsystem: "edu.stanford.plainly.voice", category: "VoiceConversation")
    private static let repeatedCallOutput = "Already covered by the previous answer. Do not answer again and add nothing."
    private static let speechTimeout: TimeInterval = 20

    public let levels = VoiceAudioLevels()
    /// Stops forwarding the microphone; the assistant finishes what it is saying and the session stays open.
    public var isMuted = false {
        didSet {
            audio?.isMuted = isMuted
        }
    }
    /// Pauses the participant's side and the assistant's audio; the session stays open and resumes where it was.
    public var isPaused = false {
        didSet {
            audio?.isPaused = isPaused
            if isPaused {
                audio?.pausePlayback()
            } else {
                audio?.resumePlayback()
                greetIfDue()
            }
        }
    }

    private let configuration: Configuration
    private let llmRunner: LLMRunner
    private let mint: Mint
    private let forward: Forward
    private var connection: Connection = .idle
    private var isForwarding = false {
        didSet {
            holdMicrophoneWhileAnswering()
        }
    }
    private var forwardsInFlight = 0
    private var storedTurns: [VoiceTurn] = []
    private var session: LLMOpenAIRealtimeSession?
    private var audio: VoiceAudioEngine?
    private var tasks: [Task<Void, Never>] = []
    private var consumedTranscriptId: UUID?
    private var finishedContext: LLMContext = []
    // Sampled ten times a second, which nothing on screen needs to observe.
    @ObservationIgnored private var caption = SpokenCaption()
    private var heardAssistantText: String?
    // One forwarded turn at a time: the text conversation answers one question per generation, and a second
    // question arriving mid-answer would cancel the first.
    private var previousTurn: Task<Void, Never>?
    // The greeting waits for the participant to actually be there: a session that opens under a sheet stays quiet,
    // and it is said once per conversation, not again after every reconnect.
    private var greetingIsDue = false
    private var hasGreeted = false
    private var startTask: Task<Void, Never>?
    // The answer is in but its audio has not started; the screen keeps showing work until the voice arrives.
    private var awaitingSpeech = false {
        didSet {
            holdMicrophoneWhileAnswering()
        }
    }
    // Where the playback queue stood when the answer came in; audio queued beyond it is the answer being read.
    private var speechMark: TimeInterval?
    // A reply that never plays must not hold the microphone for the rest of the session.
    private var speechDeadline: Date?
    private var turnTasks: [UUID: Task<String, any Error>] = [:]


    /// What the assistant is doing, for the screen.
    public var phase: VoicePhase {
        switch connection {
        case .idle:
            return .idle
        case .connecting:
            return .connecting
        case .failed(let message):
            return .failed(message)
        case .connected:
            if isPaused {
                return .paused
            }
            if isForwarding || awaitingSpeech {
                return .thinking
            }
            if levels.isOutputActive {
                return .speaking
            }
            return isMuted ? .muted : .listening
        }
    }

    /// Whether a session is open or being opened.
    public var isActive: Bool {
        connection == .connected || connection == .connecting
    }

    /// Creates a conversation that is not connected yet; ``start()`` mints and opens the session.
    public init(configuration: Configuration, llmRunner: LLMRunner, mint: @escaping Mint, forward: @escaping Forward) {
        self.configuration = configuration
        self.llmRunner = llmRunner
        self.mint = mint
        self.forward = forward
    }


    /// Mints a session and opens it; a failure shows up as ``VoicePhase/failed(_:)``.
    public func start() async {
        guard !isActive else {
            return
        }
        connection = .connecting
        let task = Task { await self.connect() }
        startTask = task
        await task.value
    }

    /// The part of ``start()`` that can be cut short by ``stop()``: nothing it made survives a cancellation.
    private func connect() async {
        do {
            let grant = try await mint(VoiceSessionRequest(
                model: configuration.model.rawValue,
                instructions: configuration.instructions + "\n\n" + configuration.languageRule,
                voice: configuration.voice,
                language: configuration.languageCode
            ))
            try Task.checkCancellation()
            let session = llmRunner(with: schema(for: grant))
            let audio = try VoiceAudioEngine(levels: levels)
            audio.isPaused = isPaused
            audio.isMuted = isMuted
            audio.isAnswering = isForwarding || awaitingSpeech
            audio.onFailure = { [weak self] error in
                Task { @MainActor in self?.fail(error, context: "audio") }
            }
            self.session = session
            self.audio = audio
            attach(session: session, audio: audio)
            try audio.start()
            connection = .connected
            greetingIsDue = !hasGreeted && configuration.greeting != nil
            greetIfDue()
        } catch is CancellationError {
            // `stop()` already put everything back.
        } catch {
            // A call cut short by `stop()` can fail with an error of its own rather than a cancellation.
            guard !Task.isCancelled else {
                return
            }
            fail(error, context: "start")
        }
    }

    /// Closes the session and releases the audio hardware; the turns so far are kept.
    public func stop() {
        startTask?.cancel()
        startTask = nil
        if let session {
            finishedContext.append(contentsOf: session.context)
        }
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        // An answer still on its way belongs to the session that asked for it; the next one neither waits for it
        // nor hears it.
        turnTasks.values.forEach { $0.cancel() }
        turnTasks.removeAll()
        previousTurn = nil
        audio?.stop()
        audio = nil
        session?.cancel()
        session = nil
        levels.reset()
        caption.reset()
        heardAssistantText = nil
        isForwarding = false
        awaitingSpeech = false
        speechMark = nil
        speechDeadline = nil
        greetingIsDue = false
        connection = .idle
    }

    /// Runs the three streams that carry a session: assistant audio out, activity, and microphone in.
    private func attach(session: LLMOpenAIRealtimeSession, audio: VoiceAudioEngine) {
        tasks = [
            Task { [weak self] in
                do {
                    for try await chunk in await session.listen() {
                        audio.play(chunk)
                    }
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.fail(error, context: "playback")
                }
            },
            Task { [weak self] in
                do {
                    for try await activity in await session.activity() {
                        if case let .serverRefused(code, message) = activity {
                            Self.logger.warning(
                                "The realtime server refused an event (\(code ?? "no code", privacy: .public)): \(message, privacy: .public)"
                            )
                        }
                    }
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.fail(error, context: "activity")
                }
            },
            Task {
                for await chunk in audio.microphone {
                    try? await session.appendUserAudio(chunk)
                }
            },
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    self?.followSpeech(session: session, audio: audio)
                }
            }
        ]
    }

    /// One question at a time: while an answer is being fetched or has not been heard yet, the participant's next
    /// words do not reach the server, so they cannot pile up into two answers read back to back.
    private func holdMicrophoneWhileAnswering() {
        audio?.isAnswering = isForwarding || awaitingSpeech
    }

    private func fail(_ error: any Error, context: String) {
        Self.logger.error("Voice session \(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        stop()
        connection = .failed(error.localizedDescription)
    }

    private func schema(for grant: VoiceSessionGrant) -> LLMOpenAIRealtimeSchema {
        LLMOpenAIRealtimeSchema(
            parameters: .init(
                modelType: configuration.model,
                systemPrompt: nil,
                sessionConfiguration: .server,
                followUpToolChoice: .none,
                overwritingAuthToken: .constant(grant.clientSecret),
                overwritingServerUrl: grant.baseUrl,
                // The forwarded turn should carry the participant's own words, which arrive a moment after the call.
                transcriptGracePeriod: .seconds(4)
            )
        ) {
            VoiceForwardingTool(name: configuration.toolName) { [weak self] question in
                guard let self else {
                    throw CancellationError()
                }
                return try await self.answer(question)
            }
        }
    }
}


// MARK: Turns
extension VoiceConversation {
    /// Runs one forwarded turn after the one before it: the participant's own words when their transcript landed,
    /// the model's rendering otherwise.
    private func answer(_ question: String) async throws -> String {
        // The words are matched to the call now, while the transcript that belongs to it is the latest one.
        let latest = session?.context.last { $0.role == .user && $0.complete && !$0.content.isEmpty }
        let usesTranscript = latest != nil && latest?.id != consumedTranscriptId
        consumedTranscriptId = latest?.id ?? consumedTranscriptId
        // A second call for the same words, which a model makes when it splits one turn in two, must not become a
        // second answer read after the first; it waits for the turn in flight and adds nothing.
        if !usesTranscript, forwardsInFlight > 0, let earlier = previousTurn {
            await earlier.value
            return Self.repeatedCallOutput
        }
        forwardsInFlight += 1
        defer {
            forwardsInFlight -= 1
        }
        let turn = VoiceTurn(
            startedAt: .now,
            transcript: usesTranscript ? latest?.content ?? question : question,
            transcriptSource: usesTranscript ? .transcript : .paraphrase,
            toolName: configuration.toolName,
            arguments: question
        )
        storedTurns.append(turn)
        let earlier = previousTurn
        let task = Task<String, any Error> {
            await earlier?.value
            return try await self.forwardTurn(turn)
        }
        turnTasks[turn.id] = task
        defer {
            turnTasks[turn.id] = nil
        }
        previousTurn = Task {
            _ = try? await task.value
        }
        return try await task.value
    }

    private func forwardTurn(_ turn: VoiceTurn) async throws -> String {
        let session = self.session
        isForwarding = true
        defer {
            isForwarding = false
        }
        // Spoken alongside the forward, never ahead of it: an interjection waits its turn on the socket, and the
        // participant's question must not wait with it.
        let bridging = bridge(for: turn)
        let reassuring = reassure()
        defer {
            bridging?.cancel()
            reassuring?.cancel()
        }
        let answer: String
        do {
            answer = try await forward(turn.transcript)
        } catch let error where !(error is CancellationError) && !Task.isCancelled {
            // The model reads whatever the tool returns; an error description would have it improvise around it.
            Self.logger.error("Forwarding a voice turn failed: \(error.localizedDescription, privacy: .public)")
            answer = configuration.unavailableAnswer
        }
        // A session that ended while the answer was on its way has nobody to read it to.
        guard session != nil, self.session === session else {
            throw CancellationError()
        }
        if let index = storedTurns.firstIndex(where: { $0.id == turn.id }) {
            storedTurns[index].answer = answer
            storedTurns[index].answeredAt = .now
        }
        speechMark = audio?.scheduledSeconds
        speechDeadline = .now.addingTimeInterval(Self.speechTimeout)
        awaitingSpeech = true
        return answer
    }
}


// MARK: Interjections
extension VoiceConversation {
    private func bridge(for turn: VoiceTurn) -> Task<Void, Never>? {
        guard let bridge = configuration.bridge, let session else {
            return nil
        }
        let question = "<question>\(turn.transcript)</question>"
        let spoken = configuration.interjection(bridge.replacingOccurrences(of: "{question}", with: question))
        return Task {
            try? await session.interject(spoken)
        }
    }

    /// Speaks up at intervals for as long as the task lives, so a long wait never goes quiet.
    private func reassure() -> Task<Void, Never>? {
        guard let reassurance = configuration.reassurance, let session else {
            return nil
        }
        let interval = configuration.reassuranceInterval
        let aside = configuration.interjection(reassurance)
        return Task { [weak self] in
            var spoken = 0
            while !Task.isCancelled, spoken < 2 {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else {
                    return
                }
                // Nothing to add while the assistant is still being heard; a reassurance over queued audio only
                // delays the answer and sounds like repetition.
                guard let self, !self.isPaused, let audio = self.audio, audio.queuedSeconds < 0.3, !self.levels.isOutputActive else {
                    continue
                }
                spoken += 1
                try? await session.interject(aside)
            }
        }
    }

    private func greetIfDue() {
        guard greetingIsDue, !isPaused, connection == .connected, let greeting = configuration.greeting, let session else {
            return
        }
        greetingIsDue = false
        hasGreeted = true
        tasks.append(Task {
            try? await session.interject(configuration.interjection(greeting))
        })
    }
}


// MARK: Transcript
extension VoiceConversation {
    /// Every line spoken so far, in order, from the session's own record; the last assistant line is shown only as
    /// far as the loudspeaker has reached.
    public var transcript: [VoiceLine] {
        let context = finishedContext + (session?.context ?? [])
        var lines = context.compactMap { entity -> VoiceLine? in
            let speaker: VoiceLine.Speaker
            switch entity.role {
            case .user:
                speaker = .participant
            case .assistant:
                speaker = .assistant
            default:
                return nil
            }
            guard !entity.content.isEmpty else {
                return nil
            }
            return VoiceLine(id: entity.id, speaker: speaker, text: entity.content)
        }
        if let heard = heardAssistantText, let last = lines.indices.last, lines[last].speaker == .assistant {
            lines[last].text = heard
        }
        return lines.filter { !$0.text.isEmpty }
    }

    /// Every forwarded turn so far, each paired with what the assistant then said aloud.
    public var turns: [VoiceTurn] {
        let context = finishedContext + (session?.context ?? [])
        return storedTurns.map { turn in
            var turn = turn
            if let answeredAt = turn.answeredAt {
                turn.spokenTranscript = context.first { $0.role == .assistant && $0.complete && $0.date >= answeredAt }?.content
            }
            return turn
        }
    }

    /// Shows the assistant's latest line only as far as the loudspeaker has reached, and notices when the answer starts.
    private func followSpeech(session: LLMOpenAIRealtimeSession, audio: VoiceAudioEngine) {
        guard let latest = session.context.last(where: { $0.role == .assistant }) else {
            if heardAssistantText != nil {
                heardAssistantText = nil
            }
            return
        }
        let heard = caption.text(of: latest.id, arrived: latest.content, queued: audio.scheduledSeconds, played: audio.playedSeconds)
        if heard != heardAssistantText {
            heardAssistantText = heard
        }
        if awaitingSpeech {
            // Audio still playing when the answer came in is an aside; only audio queued after it is the answer.
            let replyIsPlaying = levels.isOutputActive && audio.scheduledSeconds > (speechMark ?? 0)
            let gaveUp = speechDeadline.map { Date.now > $0 } ?? false
            if replyIsPlaying || gaveUp {
                awaitingSpeech = false
                speechMark = nil
                speechDeadline = nil
            }
        }
    }
}
