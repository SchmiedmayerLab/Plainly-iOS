//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import SwiftUI

struct StudyChatProcessingView: View {
    /// How quickly the creep approaches its ceiling; after this many seconds it has covered ~63 % of the way.
    private static let creepTimeConstant: TimeInterval = 8

    let model: StudyChatViewModel

    /// When the current state was entered, which is what the creep advances from.
    @State private var milestoneStart = Date.now
    /// Where the bar stood when the state last changed, so a new state's lower base never moves it backwards.
    @State private var carriedProgress: Double = 0

    var body: some View {
        Group {
            if model.isProcessing {
                Group {
                    if #available(iOS 26.0, *) {
                        content
                            .padding(.top, 6)
                            .glassEffect()
                            .padding(.horizontal)
                    } else {
                        content
                            .background(.ultraThinMaterial)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .animation(.interactiveSpring, value: model.isProcessing)
        .onChange(of: model.processingState) { _, _ in
            carriedProgress = displayedProgress(at: .now)
            milestoneStart = .now
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                ProgressView(value: displayedProgress(at: timeline.date), total: 100)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }

            Text(model.processingState.statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.3), value: model.processingState.statusDescription)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    /// The state's certain progress plus a creep towards its ceiling, never below where the bar already stood.
    private func displayedProgress(at date: Date) -> Double {
        let state = model.processingState
        let elapsed = max(0, date.timeIntervalSince(milestoneStart))
        let creeped = state.progress + (state.creepCeiling - state.progress) * (1 - exp(-elapsed / Self.creepTimeConstant))
        return max(creeped, min(carriedProgress, state.creepCeiling))
    }
}
