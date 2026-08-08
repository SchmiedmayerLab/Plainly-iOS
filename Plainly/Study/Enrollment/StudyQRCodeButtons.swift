//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import Foundation
import SwiftUI


/// A `Button` that opens the study enrollment QR code scanner.
struct ScanQRCodeButton: View {
    let didScan: @MainActor (StudyQRCodeHandler.ScanResult) -> Void
    @State private var showQRCodeScanner = false
    
    var body: some View {
        Button {
            showQRCodeScanner = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
                .accessibilityLabel("Scan code to enroll in study")
        }
        .qrCodeScanningSheet(isPresented: $showQRCodeScanner) { payload in
            do {
                let result = try StudyQRCodeHandler.processQRCode(payload: payload)
                didScan(result)
                showQRCodeScanner = false
                return .stopScanning
            } catch {
                AppDiagnostics.study.logError(error, context: "Processing study QR code")
                return .continueScanning
            }
        }
    }
}


/// A `Button` that opens the study enrollment QR code generator.
struct CreateQRCodeButton: View {
    @State private var isPresented = false
    
    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
                .accessibilityLabel("Scan code to enroll in study")
        }
        .fullScreenCover(isPresented: $isPresented) {
            CreateEnrollmentQRCodeSheet()
        }
    }
}
