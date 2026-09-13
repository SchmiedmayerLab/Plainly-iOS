//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import Observation


/// Plays the voice screen without a session: fixed on one phase, or walking through a short conversation.
///
/// For previews, screenshots, and UI tests; the views cannot tell it from the real thing.
@MainActor
@Observable
public final class VoiceDemoPresenter: VoicePresenter {
    private struct Step {
        let phase: VoicePhase
        let lines: [VoiceLine]
        let duration: Duration
    }

    private static let opening = [
        VoiceLine(id: UUID(), speaker: .assistant, text: "Hello. Ask me about any report or result, and I will explain it in plain words."),
        VoiceLine(id: UUID(), speaker: .participant, text: "Hi, can you help me understand my records?"),
        VoiceLine(id: UUID(), speaker: .assistant, text: "Of course. What would you like to look at first?")
    ]
    private static let question = VoiceLine(id: UUID(), speaker: .participant, text: "What does my most recent MRI report say?")
    private static let bridge = VoiceLine(id: UUID(), speaker: .assistant, text: "Let me look through your records for that. One moment.")
    private static let answer = VoiceLine(
        id: UUID(),
        speaker: .assistant,
        text: "Your MRI from March shows a small disc bulge at L4 to L5 that touches, but does not press on, the nerve root. "
            + "That fits the pain you described, and it is a common finding that often improves with time and physical therapy."
    )

    private static let script: [Step] = [
        Step(phase: .listening, lines: opening, duration: .seconds(2)),
        Step(phase: .listening, lines: opening + [question], duration: .seconds(4)),
        Step(phase: .thinking, lines: opening + [question, bridge], duration: .seconds(3)),
        Step(phase: .speaking, lines: opening + [question, bridge, answer], duration: .seconds(6))
    ]

    public let levels = VoiceAudioLevels()
    public private(set) var phase: VoicePhase
    public private(set) var transcript: [VoiceLine]
    /// Shows as muted while listening; the script keeps running underneath.
    public var isMuted = false
    /// Shows as paused; the script keeps running underneath.
    public var isPaused = false

    private let fixedPhase: VoicePhase?
    private var driver: Task<Void, Never>?
    @ObservationIgnored private var stepIndex = 0
    @ObservationIgnored private var stepStart = ContinuousClock.now


    /// - Parameter phase: A phase to hold, or `nil` to walk through the scripted conversation on a loop.
    public init(phase: VoicePhase? = nil) {
        fixedPhase = phase
        self.phase = phase ?? .idle
        transcript = phase == nil ? [] : Self.script.last?.lines ?? []
    }


    /// Starts the script, or the level animation for a held phase.
    public func start() async {
        driver?.cancel()
        stepIndex = 0
        stepStart = .now
        // Weak between ticks, so a presenter nobody stops, such as one in a preview, can still go away.
        driver = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                self?.advance()
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    /// Freezes the screen.
    public func stop() {
        driver?.cancel()
        driver = nil
        levels.reset()
    }

    private func advance() {
        if let fixedPhase {
            phase = isPaused ? .paused : (isMuted && fixedPhase == .listening ? .muted : fixedPhase)
        } else {
            let step = Self.script[stepIndex]
            phase = isPaused ? .paused : (isMuted && step.phase == .listening ? .muted : step.phase)
            transcript = step.lines
            if ContinuousClock.now - stepStart >= step.duration {
                stepIndex = (stepIndex + 1) % Self.script.count
                stepStart = .now
            }
        }
        synthesizeLevels()
    }

    /// A voice-like envelope: syllable-rate pulses under a slower swell, so the orb moves the way it will in use.
    private func synthesizeLevels() {
        let time = Date.now.timeIntervalSinceReferenceDate
        let envelope = Float(0.45 + 0.35 * sin(time * 1.7) * sin(time * 5.3) + 0.2 * sin(time * 11))
        let level = max(0, min(1, envelope))
        switch phase {
        case .listening:
            levels.update(input: transcript.last?.speaker == .participant ? level : level * 0.15)
            levels.update(output: 0)
        case .speaking:
            levels.update(input: 0)
            levels.update(output: level)
        default:
            levels.update(input: 0)
            levels.update(output: 0)
        }
    }
}
