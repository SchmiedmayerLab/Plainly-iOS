//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import Observation


/// What a voice screen needs from whatever drives it, so the live session and a demo look the same to the views.
@MainActor
public protocol VoicePresenter: AnyObject, Observable {
    /// What the assistant is doing.
    var phase: VoicePhase { get }
    /// Everything said so far, oldest first; the last line may still be growing. Lines are never removed.
    var transcript: [VoiceLine] { get }
    /// How loud each side is.
    var levels: VoiceAudioLevels { get }
    /// Whether the microphone is forwarded; the assistant keeps talking.
    var isMuted: Bool { get set }
    /// Whether the conversation is paused: the microphone is not forwarded and the assistant's audio is held.
    var isPaused: Bool { get set }

    /// Opens the session; a failure shows up in ``phase``.
    func start() async
    /// Closes the session.
    func stop()
}
