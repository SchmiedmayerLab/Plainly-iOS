//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Carries the session from its report upload through to the confirmation.
///
/// Both stages share one sheet so the participant sees the progress resolve in place, rather than a
/// sheet being dismissed and another presented in its stead.
struct StudyCompletedSheet: View {
    let studyTitle: String
    let state: StudyChatViewModel.CompletionState
    let onDone: @MainActor () -> Void

    private var title: LocalizedStringResource {
        state == .submitting ? "STUDY_COMPLETED_SUBMITTING_TITLE" : "STUDY_COMPLETED_TITLE"
    }

    private var message: LocalizedStringResource? {
        switch state {
        case .submitting:
            nil
        case .submitted:
            "STUDY_COMPLETED_MESSAGE \(studyTitle)"
        case .retained:
            "STUDY_COMPLETED_MESSAGE_PENDING \(studyTitle)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The spacers share whatever height the detent leaves over, which keeps the indicator, the
            // message, and the action spread across the sheet rather than bunched under its grabber.
            Spacer(minLength: 16)
            indicator
                .frame(height: 72)
            Spacer(minLength: 24)
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                if let message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 24)
            if state != .submitting {
                PrimaryActionButton("STUDY_COMPLETED_DONE_ACTION", action: onDone)
                    .transforming { button in
                        if #available(iOS 26, *) {
                            button.buttonStyle(.glassProminent)
                        } else {
                            button.buttonStyle(.borderedProminent)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth, value: state)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var indicator: some View {
        switch state {
        case .submitting:
            ProgressView()
                .controlSize(.extraLarge)
        case .submitted, .retained:
            Image(systemName: state == .submitted ? "checkmark.circle.fill" : "clock.badge.checkmark.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .transition(.scale.combined(with: .opacity))
        }
    }
}


#Preview("Submitting") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            StudyCompletedSheet(studyTitle: "Plainly REI study", state: .submitting) {}
        }
}

#Preview("Submitted") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            StudyCompletedSheet(studyTitle: "Plainly REI study", state: .submitted) {}
        }
}

#Preview("Retained") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            StudyCompletedSheet(studyTitle: "Plainly REI study", state: .retained) {}
        }
}
