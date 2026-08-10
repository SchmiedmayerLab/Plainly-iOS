//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsDSTU2
import ModelsR4
import PlainlyShared
import SpeziFHIR
import Testing


@Suite
struct FHIRResourceDateTests {
    @Test("R4 observations use the start of an ongoing effective period")
    func r4ObservationOngoingPeriod() throws {
        let start = ModelsR4.DateTime("2026-01-02T03:04:05Z")
        let observation = ModelsR4.Observation(
            code: ModelsR4.CodeableConcept(),
            effective: .period(ModelsR4.Period(start: start.asPrimitive())),
            id: ModelsR4.FHIRString("observation").asPrimitive(),
            status: ModelsR4.ObservationStatus.final.asPrimitive()
        )
        let resource = FHIRResource(resource: observation, displayName: "Observation")

        #expect(resource.date == (try start.asNSDate()))
    }

    @Test("DSTU2 medication statements use the start of an ongoing effective period")
    func dstu2MedicationStatementOngoingPeriod() throws {
        let start = ModelsDSTU2.DateTime("2026-01-02T03:04:05Z")
        let medicationStatement = ModelsDSTU2.MedicationStatement(
            effective: .period(ModelsDSTU2.Period(start: start.asPrimitive())),
            id: ModelsDSTU2.FHIRString("medication-statement").asPrimitive(),
            medication: .codeableConcept(ModelsDSTU2.CodeableConcept()),
            patient: ModelsDSTU2.Reference(),
            status: ModelsDSTU2.MedicationStatementStatus.active.asPrimitive()
        )
        let resource = FHIRResource(resource: medicationStatement, displayName: "Medication Statement")

        #expect(resource.date == (try start.asNSDate()))
    }
}
