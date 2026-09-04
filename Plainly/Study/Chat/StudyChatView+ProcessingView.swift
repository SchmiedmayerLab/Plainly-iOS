//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import SwiftUI


/// The progress of the answer being prepared, drawn as a line under the navigation bar.
///
/// A browser's loading line is the model: it sits at the edge of the chrome, fills as the work proceeds, and
/// leaves once it is done. That keeps the conversation itself undisturbed, which a floating bar over the
/// messages does not.
struct StudyChatProcessingView: View {
    /// How quickly the line approaches its ceiling; after this many seconds it has covered ~63 % of the way.
    /// An unstreamed answer with an image can take most of a minute; the bar must still be moving when it lands.
    private static let creepTimeConstant: TimeInterval = 20
    private static let lineHeight: CGFloat = 2.5
    /// How long the finished line stays at full width before it fades.
    private static let completionHold: Duration = .milliseconds(400)

    let model: StudyChatViewModel

    /// When the current state was entered, which is what the creep advances from.
    @State private var milestoneStart = Date.now
    /// Where the line stood when the state last changed, so a later state never moves it backwards.
    @State private var carriedProgress: Double = 0
    /// Kept visible after the work ends, so the line finishes its run rather than vanishing part way along.
    @State private var isFinishing = false

    private var isVisible: Bool {
        model.isProcessing || isFinishing
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !isVisible)) { timeline in
            Rectangle()
                .fill(.tint)
                .frame(height: Self.lineHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Scaled rather than sized, so the line needs no reader to know the width it fills.
                .scaleEffect(x: fraction(at: timeline.date), y: 1, anchor: .leading)
                // The creep already moves in small steps; animating each one carries the line between them
                // instead of stepping four times a second.
                .animation(.easeOut(duration: 0.35), value: fraction(at: timeline.date))
        }
        .frame(height: Self.lineHeight)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .accessibilityLabel(model.processingState.statusDescription)
        .onChange(of: model.processingState) { previous, current in
            // A turn that starts over reports less progress than the one before it: carrying the old value
            // across would leave the next answer's line starting where the last one stopped.
            carriedProgress = current.progress < previous.progress ? current.progress : displayedProgress(at: .now)
            milestoneStart = .now
        }
        .onChange(of: model.isProcessing) { _, isProcessing in
            if isProcessing {
                carriedProgress = 0
                milestoneStart = .now
                isFinishing = false
            } else if isVisible {
                finish()
            }
        }
    }

    private func fraction(at date: Date) -> Double {
        (isFinishing ? 100 : displayedProgress(at: date)) / 100
    }

    /// The state's certain progress plus a creep towards its ceiling, never below where the line already stood.
    private func displayedProgress(at date: Date) -> Double {
        let state = model.processingState
        let elapsed = max(0, date.timeIntervalSince(milestoneStart))
        let creeped = state.progress + (state.creepCeiling - state.progress) * (1 - exp(-elapsed / Self.creepTimeConstant))
        return max(creeped, min(carriedProgress, state.creepCeiling))
    }

    /// Runs the line out to full width before it leaves.
    ///
    /// The work ends while the line is partway along, and a line that disappears there reads as a bar that
    /// gave up rather than one that finished.
    private func finish() {
        isFinishing = true
        Task {
            try? await Task.sleep(for: Self.completionHold)
            isFinishing = false
        }
    }
}
