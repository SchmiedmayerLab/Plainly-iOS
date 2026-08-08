//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Reassures the participant that a session which could not be submitted yet is safe and will retry.
///
/// Tapping it starts another attempt, so a participant who is told to try again has something to press.
struct PendingReportsView: View {
    let count: Int
    let isUploading: Bool
    let onRetry: @MainActor () -> Void

    var body: some View {
        Button(action: onRetry) {
            HStack(spacing: 10) {
                indicator
                Text(isUploading ? "PENDING_REPORTS_UPLOADING" : "PENDING_REPORTS_WAITING \(count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 16))
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
        .animation(.default, value: isUploading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("PENDING_REPORTS_RETRY_HINT")
    }

    @ViewBuilder private var indicator: some View {
        if isUploading {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "arrow.up.circle.dotted")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}


#Preview("Waiting") {
    PendingReportsView(count: 1, isUploading: false) {}
        .padding(32)
}

#Preview("Uploading") {
    PendingReportsView(count: 2, isUploading: true) {}
        .padding(32)
}
