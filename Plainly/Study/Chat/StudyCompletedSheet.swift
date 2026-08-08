//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Confirms that the session ended and its report reached the study team.
struct StudyCompletedSheet: View {
    let studyTitle: String
    let onDone: @MainActor () -> Void

    var body: some View {
        BottomSheet {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("STUDY_COMPLETED_TITLE")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("STUDY_COMPLETED_MESSAGE \(studyTitle)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                PrimaryActionButton("STUDY_COMPLETED_DONE_ACTION", action: onDone)
                    .transforming { button in
                        if #available(iOS 26, *) {
                            button.buttonStyle(.glassProminent)
                        } else {
                            button.buttonStyle(.borderedProminent)
                        }
                    }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
        }
        .interactiveDismissDisabled()
        .scrollBounceBehavior(.basedOnSize)
    }
}


#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            StudyCompletedSheet(studyTitle: "Plainly REI study") {}
        }
}
