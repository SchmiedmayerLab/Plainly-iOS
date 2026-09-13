//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import Observation


/// What the voice screen animates on: how loud the participant and the assistant are right now.
///
/// Levels are perceptual, in `0...1`, and already smoothed enough to drive a view directly.
@MainActor
@Observable
public final class VoiceAudioLevels {
    private static let activityThreshold: Float = 0.04
    private static let activityHold: Duration = .milliseconds(350)

    /// How loud the participant is.
    public private(set) var input: Float = 0
    /// How loud the assistant is.
    public private(set) var output: Float = 0
    /// Whether the assistant is audibly speaking, held briefly across the gaps between words.
    public private(set) var isOutputActive = false

    private var outputHold: Task<Void, Never>?


    /// Starts silent.
    public init() {}


    /// Reports the participant's loudness.
    public func update(input level: Float) {
        if level != input {
            input = level
        }
    }

    /// Reports the assistant's loudness and keeps ``isOutputActive`` up while it keeps coming.
    public func update(output level: Float) {
        output = level
        guard level > Self.activityThreshold else {
            return
        }
        isOutputActive = true
        outputHold?.cancel()
        outputHold = Task { [weak self] in
            try? await Task.sleep(for: Self.activityHold)
            guard !Task.isCancelled else {
                return
            }
            self?.isOutputActive = false
        }
    }

    /// Back to silence, for when the session ends or is interrupted.
    public func reset() {
        outputHold?.cancel()
        input = 0
        output = 0
        isOutputActive = false
    }
}
