//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI


/// A `Button` that opens the study enrollment QR code generator.
struct CreateQRCodeButton: View {
    @State private var isPresented = false
    
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
                .accessibilityLabel("Create study enrollment code")
        }
        .fullScreenCover(isPresented: $isPresented) {
            CreateEnrollmentQRCodeSheet()
        }
    }
}
