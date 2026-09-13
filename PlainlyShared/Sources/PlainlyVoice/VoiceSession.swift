//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// What a client asks its backend to mint: the choices the backend lets it make about a session.
public struct VoiceSessionRequest: Sendable {
    /// The realtime model.
    public let model: String
    /// How the voice behaves.
    public let instructions: String
    /// The assistant's voice, or the backend's default.
    public let voice: String?
    /// The ISO 639-1 code transcription listens for, or the backend's default.
    public let language: String?

    /// The fields mirror what the backend accepts.
    public init(model: String, instructions: String, voice: String?, language: String? = nil) {
        self.model = model
        self.instructions = instructions
        self.voice = voice
        self.language = language
    }
}


/// A minted session: the short-lived secret and the endpoint it opens the session at.
public struct VoiceSessionGrant: Sendable {
    /// The ephemeral credential.
    public let clientSecret: String
    /// The OpenAI-compatible endpoint the secret was minted for.
    public let baseUrl: URL
    /// The provider's identifier, for logs and reports.
    public let sessionId: String

    /// - Parameters:
    ///   - clientSecret: The ephemeral credential.
    ///   - baseUrl: The OpenAI-compatible endpoint the secret was minted for.
    ///   - sessionId: The provider's identifier, for logs and reports.
    public init(clientSecret: String, baseUrl: URL, sessionId: String) {
        self.clientSecret = clientSecret
        self.baseUrl = baseUrl
        self.sessionId = sessionId
    }
}


/// One spoken participant turn: what was heard, what the model asked for, and what came back.
public struct VoiceTurn: Identifiable, Sendable {
    public enum TranscriptSource: String, Sendable {
        /// The participant's own words, from the session's transcription.
        case transcript
        /// The model's rendering of the words in its tool arguments, used when no transcript arrived in time.
        case paraphrase
    }

    public let id: UUID
    /// When the forwarding call arrived.
    public let startedAt: Date
    /// What was forwarded.
    public let transcript: String
    /// Where ``transcript`` came from.
    public let transcriptSource: TranscriptSource
    /// The forwarding tool the model called.
    public let toolName: String
    /// The raw arguments of that call.
    public let arguments: String
    /// What the text conversation answered, once it has.
    public internal(set) var answer: String?
    /// When the answer arrived; what the assistant says after this is the spoken answer, what came before was bridging.
    public internal(set) var answeredAt: Date?
    /// What the assistant then said aloud, which can differ slightly from the answer it was given.
    public internal(set) var spokenTranscript: String?

    init(startedAt: Date, transcript: String, transcriptSource: TranscriptSource, toolName: String, arguments: String) {
        self.id = UUID()
        self.startedAt = startedAt
        self.transcript = transcript
        self.transcriptSource = transcriptSource
        self.toolName = toolName
        self.arguments = arguments
    }
}
