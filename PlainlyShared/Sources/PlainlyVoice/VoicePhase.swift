//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// What the participant should understand the assistant to be doing right now.
public enum VoicePhase: Equatable, Sendable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    /// The participant muted the microphone; the assistant can still finish what it is saying.
    case muted
    /// The participant paused the conversation; nothing is heard or said until they resume.
    case paused
    case failed(String)

    /// Whether the session is down and the participant can try again.
    public var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
