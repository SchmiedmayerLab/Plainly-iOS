//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// One spoken line of the conversation, the participant's or the assistant's, as it was heard.
public struct VoiceLine: Identifiable, Hashable, Sendable {
    public enum Speaker: Hashable, Sendable {
        case participant
        case assistant
    }

    public let id: UUID
    public let speaker: Speaker
    /// Grows while the line is still being spoken.
    public var text: String

    public init(id: UUID, speaker: Speaker, text: String) {
        self.id = id
        self.speaker = speaker
        self.text = text
    }
}
