//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Keeps a caption in step with the loudspeaker.
///
/// Text and audio stream in together, so the text that had arrived with the audio now being heard is the text to
/// show. Wall-clock time would not do: audio arrives much faster than it plays, and a caption timed by arrival
/// appears all at once near the end.
struct SpokenCaption {
    private struct Sample {
        /// How much audio had been queued when this much text had arrived; the caption reaches it as the audio plays.
        let audioMark: TimeInterval
        let text: String
        let entity: UUID
    }

    private static let sampleLimit = 600

    private var samples: [Sample] = []


    /// Records how much of the line `entity` has arrived with `queued` seconds of audio, and returns the part heard
    /// once `played` seconds have played.
    mutating func text(of entity: UUID, arrived text: String, queued: TimeInterval, played: TimeInterval) -> String {
        // A new line starts over, and so does a queue that was emptied and counts from zero again; the marks taken
        // before it would otherwise hide the whole line.
        if samples.last?.entity != entity || samples.last.map({ $0.audioMark > queued }) == true {
            samples.removeAll()
        }
        if samples.last?.text != text {
            samples.append(Sample(audioMark: queued, text: text, entity: entity))
            if samples.count > Self.sampleLimit {
                // The sample being heard stays, however far playback lags behind the text.
                let heard = samples.last { $0.audioMark <= played }
                samples.removeFirst(samples.count - Self.sampleLimit)
                if let heard, let first = samples.first, first.audioMark > heard.audioMark {
                    samples.insert(heard, at: 0)
                }
            }
        }
        return samples.last { $0.audioMark <= played }?.text ?? ""
    }

    mutating func reset() {
        samples.removeAll()
    }
}
