//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveFHIR
import GroveFoundation
import GroveHealthKit
import GroveViews
import SwiftUI


actor PlainlyStandard: Standard, EnvironmentAccessible {
    static let recordTypes: [SampleType<HKClinicalRecord>] = [
        .allergyRecord, .clinicalNoteRecord, .conditionRecord,
        .coverageRecord, .immunizationRecord, .labResultRecord,
        .medicationRecord, .procedureRecord, .vitalSignRecord
    ]
    
    @MainActor @Dependency(FHIRStore.self) private var fhirStore
    @Dependency(HealthKit.self) private var healthKit
    
    private var resourceLimit: Int {
        LocalPreferencesStore.standard[.resourceLimit]
    }
    @MainActor var useHealthKitResources = !FeatureFlags.disableHealthRecords
    
    @MainActor @Dependency private var waitingState = FHIRResourceWaitingState()
    /// The store identity of the resource each clinical record was added as, to remove it when the record is deleted.
    ///
    /// Changed together with the store on the main actor, so the two cannot drift apart.
    @MainActor private var resourceIDs: [UUID: FHIRResource.ID] = [:]
    
    @MainActor
    func configure() {
        Task {
            await waitingState.run {
                await initialSetup()
            }
        }
    }
    
    private func initialSetup() async {
        await healthKit.waitForConfigurationDone()
        guard healthKit.isFullyAuthorized else {
            return
        }
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
            return
        }
        let resourceLimit = await self.resourceLimit
        removeAllResources()
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
                        await addRecords(records)
                    } catch {
                        AppDiagnostics.healthRecords.logError(error, context: "Health Records query")
                    }
                }
            }
        }
        await healthKit.triggerDataSourceCollection()
    }
    
    private func addRecords(_ records: [HKClinicalRecord]) async {
        await withTaskGroup { taskGroup in
            for record in records {
                taskGroup.addTask { [self] in
                    do {
                        try await add(record)
                    } catch {
                        AppDiagnostics.healthRecords.logError(error, context: "Transforming Health Records sample to FHIR")
                    }
                }
            }
        }
    }
}


extension PlainlyStandard {
    private func add(_ record: HKClinicalRecord) async throws {
        let resource = try await FHIRResource.clinicalRecord(record, using: healthKit.healthStore)
        await insert(resource, for: record.uuid)
    }
    
    @MainActor
    private func insert(_ resource: FHIRResource, for recordID: UUID) {
        resourceIDs[recordID] = resource.id
        fhirStore.insert(resource)
    }
    
    /// Removes the resource of a deleted record, unless another record still maps to it.
    ///
    /// An updated clinical record arrives as a new record and a deletion of the old one, both with the same FHIR
    /// identity, and additions are delivered before deletions.
    @MainActor
    private func removeResource(for recordID: UUID) {
        guard let id = resourceIDs.removeValue(forKey: recordID), !resourceIDs.values.contains(id) else {
            return
        }
        fhirStore.removeResource(withID: id)
    }
    
    @MainActor
    private func removeAllResources() {
        resourceIDs.removeAll()
        fhirStore.removeAllResources()
    }
}


extension PlainlyStandard: HealthKitConstraint {
    /// The store is rebuilt from HealthKit on every fetch, so a record that cannot be converted is logged and skipped
    /// instead of holding back the collection anchor.
    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) async throws -> HealthKitAnchorCommitAction? {
        for sample in addedSamples {
            guard let record = sample as? HKClinicalRecord else {
                continue
            }
            do {
                try await add(record)
            } catch {
                AppDiagnostics.healthRecords.logError(error, context: "Transforming Health Records sample to FHIR")
            }
        }
        return nil
    }
    
    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject> & Sendable,
        ofType sampleType: SampleType<Sample>,
        deletedAfter: Date?
    ) async throws -> HealthKitAnchorCommitAction? {
        for object in deletedObjects {
            await removeResource(for: object.uuid)
        }
        return nil
    }
}
