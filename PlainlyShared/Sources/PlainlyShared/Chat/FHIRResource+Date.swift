//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
private import ModelsDSTU2
private import ModelsR4
public import SpeziFHIR


extension FHIRResource {
    /// The clinically relevant date associated with the resource, when available.
    public var date: Date? {
        switch versionedResource {
        case .r4(let resource):
            r4Date(for: resource)
        case .dstu2(let resource):
            dstu2Date(for: resource)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func r4Date(for resource: any ModelsR4.Resource) -> Date? {
        switch resource {
        case let carePlan as ModelsR4.CarePlan:
            carePlan.period?.date
        case let careTeam as ModelsR4.CareTeam:
            careTeam.period?.date
        case let claim as ModelsR4.Claim:
            try? claim.billablePeriod?.end?.value?.asNSDate()
        case let condition as ModelsR4.Condition:
            condition.onset?.date
        case let device as ModelsR4.Device:
            try? device.manufactureDate?.value?.asNSDate()
        case let diagnosticReport as ModelsR4.DiagnosticReport:
            diagnosticReport.effective?.date
        case let documentReference as ModelsR4.DocumentReference:
            try? documentReference.date?.value?.asNSDate()
        case let encounter as ModelsR4.Encounter:
            try? encounter.period?.end?.value?.asNSDate()
        case let explanationOfBenefit as ModelsR4.ExplanationOfBenefit:
            try? explanationOfBenefit.billablePeriod?.end?.value?.asNSDate()
        case let immunization as ModelsR4.Immunization:
            immunization.occurrence.date
        case let medicationRequest as ModelsR4.MedicationRequest:
            try? medicationRequest.authoredOn?.value?.asNSDate()
        case let medicationAdministration as ModelsR4.MedicationAdministration:
            medicationAdministration.effective.date
        case let observation as ModelsR4.Observation:
            observation.date
        case let procedure as ModelsR4.Procedure:
            procedure.performed?.date
        case let patient as ModelsR4.Patient:
            try? patient.birthDate?.value?.asNSDate()
        case let provenance as ModelsR4.Provenance:
            try? provenance.recorded.value?.asNSDate()
        case let supplyDelivery as ModelsR4.SupplyDelivery:
            supplyDelivery.occurrence?.date
        default:
            nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func dstu2Date(for resource: any ModelsDSTU2.Resource) -> Date? {
        switch resource {
        case let observation as ModelsDSTU2.Observation:
            if let issuedDate = observation.issued {
                try? issuedDate.value?.asNSDate()
            } else if case let .dateTime(effectiveDate) = observation.effective {
                try? effectiveDate.value?.asNSDate()
            } else {
                nil
            }
        case let medicationOrder as ModelsDSTU2.MedicationOrder:
            try? medicationOrder.dateWritten?.value?.asNSDate()
        case let medicationStatement as ModelsDSTU2.MedicationStatement:
            if case let .dateTime(date) = medicationStatement.effective {
                try? date.value?.asNSDate()
            } else {
                nil
            }
        case let condition as ModelsDSTU2.Condition:
            if case let .dateTime(date) = condition.onset {
                try? date.value?.asNSDate()
            } else {
                nil
            }
        case let procedure as ModelsDSTU2.Procedure:
            switch procedure.performed {
            case let .dateTime(date):
                try? date.value?.asNSDate()
            case let .period(period):
                try? period.end?.value?.asNSDate()
            default:
                nil
            }
        default:
            nil
        }
    }
}


extension ModelsR4.Observation {
    fileprivate var date: Date? {
        if let issued {
            try? issued.value?.asNSDate()
        } else if case let .dateTime(effectiveDate) = effective {
            try? effectiveDate.value?.asNSDate()
        } else {
            nil
        }
    }
}


extension ModelsR4.Period {
    fileprivate var date: Date? {
        if let endDate = try? end?.value?.asNSDate() {
            endDate
        } else if let startDate = try? start?.value?.asNSDate() {
            startDate
        } else {
            nil
        }
    }
}


extension ModelsR4.Condition.OnsetX {
    fileprivate var date: Date? {
        switch self {
        case let .dateTime(date):
            try? date.value?.asNSDate()
        case let .period(period):
            period.date
        case .age, .range, .string:
            nil
        }
    }
}


extension ModelsR4.DiagnosticReport.EffectiveX {
    fileprivate var date: Date? {
        switch self {
        case let .dateTime(date):
            try? date.value?.asNSDate()
        case let .period(period):
            period.date
        }
    }
}


extension ModelsR4.Immunization.OccurrenceX {
    fileprivate var date: Date? {
        switch self {
        case let .dateTime(date):
            try? date.value?.asNSDate()
        case .string:
            nil
        }
    }
}


extension ModelsR4.MedicationAdministration.EffectiveX {
    fileprivate var date: Date? {
        switch self {
        case let .dateTime(date):
            try? date.value?.asNSDate()
        case let .period(period):
            period.date
        }
    }
}


extension ModelsR4.Procedure.PerformedX {
    fileprivate var date: Date? {
        switch self {
        case let .dateTime(date):
            try? date.value?.asNSDate()
        case let .period(period):
            period.date
        case .age, .range, .string:
            nil
        }
    }
}


extension ModelsR4.SupplyDelivery.OccurrenceX {
    fileprivate var date: Date? {
        switch self {
        case let .dateTime(date):
            try? date.value?.asNSDate()
        case let .period(period):
            period.date
        case .timing:
            nil
        }
    }
}
