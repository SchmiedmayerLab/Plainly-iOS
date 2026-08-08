//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziFHIR
import SpeziFoundation
import SpeziHealthKit
import SpeziHealthKitFHIR
import SpeziViews
import SwiftUI


actor PlainlyStandard: Standard, EnvironmentAccessible {
    static let recordTypes: [SampleType<HKClinicalRecord>] = [
        .allergyRecord, .clinicalNoteRecord, .conditionRecord,
        .coverageRecord, .immunizationRecord, .labResultRecord,
        .medicationRecord, .procedureRecord, .vitalSignRecord
    ]
    
    @Dependency(FHIRStore.self) private var fhirStore
    @Dependency(HealthKit.self) private var healthKit
    
    private var resourceLimit: Int {
        LocalPreferencesStore.standard[.resourceLimit]
    }
    @MainActor var useHealthKitResources = !FeatureFlags.disableHealthRecords
    
    @MainActor @Dependency private var waitingState = FHIRResourceWaitingState()
    
    @MainActor
    func configure() {
        Task {
            await waitingState.run {
                await initialSetup()
            }
        }
    }
    
    private func initialSetup() async {
        AppDiagnostics.healthRecords.notice("Waiting for HealthKit module configuration")
        await healthKit.waitForConfigurationDone()
        guard healthKit.isFullyAuthorized else {
            AppDiagnostics.healthRecords.warning(
                "HealthKit module configured without full authorization; initial record fetch skipped"
            )
            return
        }
        AppDiagnostics.healthRecords.notice("HealthKit module configured; starting initial record fetch")
        await fetchRecordsFromHealthKit()
    }
    
    
    @MainActor
    func fetchRecordsFromHealthKit() async {
        await waitingState.run {
            await _fetchRecordsFromHealthKit()
        }
    }
    
    @MainActor
    private func _fetchRecordsFromHealthKit() async {
        guard useHealthKitResources else {
            AppDiagnostics.healthRecords.notice("Health Records fetch skipped by runtime configuration")
            return
        }
        let resourceLimit = await self.resourceLimit
        AppDiagnostics.healthRecords.notice(
            "Health Records refresh started; configuredRecordTypes=\(Self.recordTypes.count); resourceLimit=\(resourceLimit)"
        )
        await fhirStore.removeAllResources()
        let healthKit = await healthKit
        await withTaskGroup { taskGroup in
            for recordType in Self.recordTypes {
                taskGroup.addTask { @concurrent [self] in
                    do {
                        let records = try await healthKit.query(
                            recordType,
                            timeRange: .ever,
                            limit: resourceLimit,
                            sortedBy: [SortDescriptor(\.startDate, order: .reverse)]
                        )
                        let recordTypeDescription = String(describing: recordType)
                        AppDiagnostics.healthRecords.info("""
                            Health Records query completed; recordType=\(recordTypeDescription, privacy: .public); \
                            recordCount=\(records.count, privacy: .private(mask: .hash))
                            """)
                        await addRecords(records)
                    } catch {
                        AppDiagnostics.healthRecords.logError(error, context: "Health Records query")
                    }
                }
            }
        }
        await healthKit.triggerDataSourceCollection()
        AppDiagnostics.healthRecords.notice("Health Records refresh completed")
    }
    
    private func addRecords(_ records: [HKClinicalRecord]) async {
        await withTaskGroup { taskGroup in
            for record in records {
                taskGroup.addTask { [self] in
                    do {
                        try await fhirStore.add(record, using: healthKit, loadHealthKitAttachments: true)
                    } catch {
                        AppDiagnostics.healthRecords.logError(error, context: "Transforming Health Records sample to FHIR")
                    }
                }
            }
        }
    }
}


extension PlainlyStandard: HealthKitConstraint {
    func handleNewSamples<Sample>(_ addedSamples: some Collection<Sample>, ofType sampleType: SampleType<Sample>) async {
        for sample in addedSamples {
            guard let sample = sample as? HKClinicalRecord else {
                continue
            }
            try? await fhirStore.add(sample, using: healthKit)
        }
    }
    
    func handleDeletedObjects<Sample>(_ deletedObjects: some Collection<HKDeletedObject>, ofType sampleType: SampleType<Sample>) async {
        for object in deletedObjects {
            await fhirStore.remove(object)
        }
    }
}
