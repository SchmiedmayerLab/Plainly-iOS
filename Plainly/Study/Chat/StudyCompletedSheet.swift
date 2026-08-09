//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Confirms that the session ended, and whether its report already reached the study team.
struct StudyCompletedSheet: View {
    let studyTitle: String
    let didUpload: Bool
    let onDone: @MainActor () -> Void

    private var message: LocalizedStringResource {
        didUpload ? "STUDY_COMPLETED_MESSAGE \(studyTitle)" : "STUDY_COMPLETED_MESSAGE_PENDING \(studyTitle)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // The spacers share whatever height the detent leaves over, which keeps the icon, the
            // message, and the action spread across the sheet rather than bunched under its grabber.
            Spacer(minLength: 16)
            Image(systemName: didUpload ? "checkmark.circle.fill" : "clock.badge.checkmark.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Spacer(minLength: 24)
            VStack(spacing: 12) {
                Text("STUDY_COMPLETED_TITLE")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 24)
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
        .padding(.top, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}


#Preview("Uploaded") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            StudyCompletedSheet(studyTitle: "Plainly REI study", didUpload: true) {}
        }
}

#Preview("Waiting to upload") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            StudyCompletedSheet(studyTitle: "Plainly REI study", didUpload: false) {}
        }
}
