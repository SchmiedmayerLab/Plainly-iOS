//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import SwiftUI


/// The progress of the answer being prepared, drawn as the same hairline under the navigation bar that the
/// questionnaire fills as its pages pass: tinted, one point tall, and with no track of its own, so the untravelled
/// part stays clear and the bar's separator shows through.
struct StudyChatProcessingView: View {
    /// How quickly the line approaches its ceiling; after this many seconds it has covered ~63 % of the way.
    /// An unstreamed answer with an image can take most of a minute; the bar must still be moving when it lands.
    private static let creepTimeConstant: TimeInterval = 20
    private static let lineHeight: CGFloat = 1
    /// How long the finished line stays at full width before it fades.
    private static let completionHold: Duration = .milliseconds(400)

    let model: StudyChatViewModel

    /// When the current state was entered, which is what the creep advances from.
    @State private var milestoneStart = Date.now
    /// Where the line stood when the state last changed, so a later state never moves it backwards.
    @State private var carriedProgress: Double = 0
    /// Kept visible after the work ends, so the line finishes its run rather than vanishing part way along.
    @State private var isFinishing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool {
        model.isProcessing || isFinishing
    }

    var body: some View {
        ZStack {
            if isVisible {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    line(fraction: fraction(at: timeline.date))
                }
                .transition(.opacity)
            }
        }
        .frame(height: Self.lineHeight)
        .animation(.default, value: isVisible)
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

    private func line(fraction: Double) -> some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.tint)
                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
        }
        .frame(height: Self.lineHeight)
        // Smooth rather than snappy, as in the questionnaire: the line reports, it does not react.
        .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: fraction)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
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
