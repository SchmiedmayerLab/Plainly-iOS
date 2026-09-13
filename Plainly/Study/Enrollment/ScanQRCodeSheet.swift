//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import AVFoundation
import Foundation
import GroveViews
import PlainlyShared
import PlainlyStudyDefinitions
import SwiftUI
import VisionKit


enum QRCodeScanningResponse {
    case continueScanning
    case stopScanning
    /// The code was read but is no use; the scanner says why and goes on looking.
    case rejected(reason: LocalizedStringResource)
}


/// What the scanner says over the camera: where to point it, or why the code it just read was no use.
private struct ScanNotice: Equatable {
    static let guidance = ScanNotice(symbol: "qrcode.viewfinder", text: "Point the camera at your study's enrollment code.")

    let symbol: String
    let text: LocalizedStringResource

    static func rejection(_ reason: LocalizedStringResource) -> ScanNotice {
        ScanNotice(symbol: "exclamationmark.triangle", text: reason)
    }
}


private struct ScanQRCodeSheet: View {
    /// How long a rejection stays up before the guidance returns.
    private static let rejectionHold: Duration = .seconds(4)

    // periphery:ignore - read only from physical-device builds (the scan indexes a simulator destination)
    let onSuccess: @Sendable @MainActor (_ payload: String) -> QRCodeScanningResponse

    @State private var isDeniedCameraAccess = false
    // periphery:ignore - read only from physical-device builds (the scan indexes a simulator destination)
    @State private var isScanning = false
    @State private var notice = ScanNotice.guidance
    @State private var rejections = 0

    /// Whether the studies stand in for the camera: a debug build in a simulator.
    private var isSimulatorList: Bool {
        #if targetEnvironment(simulator) && DEBUG
        true
        #else
        false
        #endif
    }
    
    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if isDeniedCameraAccess {
                    permissionsDeniedInfo
                } else {
                    scanner
                }
            }
            .navigationTitle(isSimulatorList ? "Choose a Study" : "Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissButton()
                }
            }
        }
        .task {
            isDeniedCameraAccess = switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .denied, .restricted:
                true
            default:
                false
            }
        }
    }
    
    @ViewBuilder private var scanner: some View {
        #if targetEnvironment(simulator)
        #if DEBUG
        SimulatorStudyList(onSuccess: onSuccess)
        #else
        ContentUnavailableView(
            "No Study Loaded" as String,
            systemImage: "document.badge.gearshape",
            description: Text(verbatim: "Launch into study mode by enabling the `--mode study:ID` flag in Xcode (via the `⌘ ⇧ ,` shortcut)")
        )
        #endif
        #else
        // The camera fills the sheet, bar and all: the glass bar and the notice float over it.
        DataScannerView(isScanning: $isScanning, onSuccess: onSuccess) { reason in
            notice = .rejection(reason)
            rejections += 1
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            noticePanel
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .sensoryFeedback(.error, trigger: rejections)
        .task(id: rejections) {
            guard rejections > 0 else {
                return
            }
            try? await Task.sleep(for: Self.rejectionHold)
            withAnimation(.smooth(duration: 0.3)) {
                notice = .guidance
            }
        }
        .onAppear {
            isScanning = true
        }
        .onDisappear {
            isScanning = false
        }
        #endif
    }

    /// The notice on glass over the camera, low enough to leave the code room and high enough to clear the thumb.
    private var noticePanel: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.symbol)
                .font(.title3)
                .foregroundStyle(notice == .guidance ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .accessibilityHidden(true)
                .contentTransition(.symbolEffect(.replace))
            Text(notice.text)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .modifier(GlassPanel())
        .animation(.smooth(duration: 0.3), value: notice)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ScanNotice")
    }
    
    private var permissionsDeniedInfo: some View {
        ContentUnavailableView {
            Text("Unable to access Camera")
        } description: {
            Text("You must allow Plainly to access the camera in order to be able to scan a QR code")
        } actions: {
            Button("Allow in Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                UIApplication.shared.open(url)
            }
        }
    }
}


/// A Liquid Glass panel where there is glass, a material where there is not.
private struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }
}


#if targetEnvironment(simulator) && DEBUG
/// No camera in a simulator, so the studies the app ships stand in for the codes that would enrol in them.
private struct SimulatorStudyList: View {
    let onSuccess: @Sendable @MainActor (_ payload: String) -> QRCodeScanningResponse

    var body: some View {
        List {
            Section {
                ForEach(Study.allStudies) { study in
                    Button {
                        enrol(in: study)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(study.title)
                            Text(study.id)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Studies")
            } footer: {
                Text("A simulator has no camera; choosing a study here enrols the way its code would.")
            }
        }
    }

    private func enrol(in study: Study) {
        let payload = StudyQRCodeHandler.QRCodePayload(studyId: study.id, expires: nil, participantId: "")
        guard let encoded = try? payload.qrCodePayload() else {
            return
        }
        _ = onSuccess(encoded)
    }
}
#endif


// periphery:ignore - used only from physical-device builds (the scan indexes a simulator destination)
private struct DataScannerView: UIViewControllerRepresentable {
    typealias UIViewControllerType = DataScannerViewController
    
    let isScanning: Binding<Bool>
    let onSuccess: @Sendable @MainActor (_ payload: String) -> QRCodeScanningResponse
    /// Told why a code that was read is no use, so the scanner can say so.
    let onRejection: @MainActor (_ reason: LocalizedStringResource) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let viewController = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        viewController.delegate = context.coordinator
        return viewController
    }
    
    func updateUIViewController(_ viewController: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        switch (self.isScanning.wrappedValue, viewController.isScanning) {
        case (true, true), (false, false):
            break
        case (true, false):
            do {
                try viewController.startScanning()
            } catch {
                AppDiagnostics.study.logError(error, context: "Starting study QR code scanner")
            }
        case (false, true):
            viewController.stopScanning()
        }
    }
}


// periphery:ignore - used only from physical-device builds (the scan indexes a simulator destination)
extension DataScannerView {
    fileprivate final class Coordinator: DataScannerViewControllerDelegate {
        var parent: DataScannerView
        private var shouldProcessResults = true
        
        init(parent: DataScannerView) {
            self.parent = parent
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard shouldProcessResults else {
                return
            }
            for item in addedItems {
                guard case .barcode(let barcode) = item else {
                    continue
                }
                guard barcode.observation.symbology == .qr, let payload = barcode.payloadStringValue else {
                    break
                }
                switch parent.onSuccess(payload) {
                case .stopScanning:
                    shouldProcessResults = false
                    dataScanner.stopScanning()
                    parent.isScanning.wrappedValue = false
                    return
                case .continueScanning:
                    continue
                case .rejected(let reason):
                    parent.onRejection(reason)
                    continue
                }
            }
        }
    }
}


extension View {
    /// Presents a sheet with a QR code scanner.
    ///
    /// - Note: The caller is responsible for dismissing the sheet.
    ///
    /// - parameter isPresented: Controls the visibility of the sheet.
    /// - parameter onSuccess: A closure that is called with the first QR the scanner has found.
    func qrCodeScanningSheet(
        isPresented: Binding<Bool>,
        onSuccess: @escaping @Sendable @MainActor (_ payload: String) -> QRCodeScanningResponse
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ScanQRCodeSheet(onSuccess: onSuccess)
        }
    }
}
