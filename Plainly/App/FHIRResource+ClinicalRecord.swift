//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIR
import HealthKit
import ModelsDSTU2
import ModelsR4


enum ClinicalRecordError: Error {
    case unsupportedFHIRResource
}


extension FHIRResource {
    /// Creates a resource from the FHIR resource the provider issued for a clinical record.
    ///
    /// Document references and diagnostic reports also carry the attachments the health store keeps for the record.
    /// A resource without a logical id is identified by the record's HealthKit UUID.
    @concurrent
    static func clinicalRecord(_ record: HKClinicalRecord, using healthStore: HKHealthStore) async throws -> FHIRResource {
        guard let fhirResource = record.fhirResource else {
            throw ClinicalRecordError.unsupportedFHIRResource
        }
        let identitySource = IdentitySource.explicit(record.uuid.uuidString)
        let decoder = JSONDecoder()
        var versionedResource: VersionedFHIRResource
        switch fhirResource.fhirVersion.fhirRelease {
        case .r4:
            versionedResource = .r4(try decoder.decode(ModelsR4.ResourceProxy.self, from: fhirResource.data).get())
        case .dstu2:
            versionedResource = .dstu2(try decoder.decode(ModelsDSTU2.ResourceProxy.self, from: fhirResource.data).get())
        default:
            throw ClinicalRecordError.unsupportedFHIRResource
        }
        let resource = try FHIRResource(versionedResource: versionedResource, displayName: record.displayName, identitySource: identitySource)
        guard resource.category == .document || resource.category == .diagnostic else {
            return resource
        }
        let attachmentStore = HKAttachmentStore(healthStore: healthStore)
        for attachment in try await attachmentStore.attachments(for: record) {
            let data = try await attachmentStore.dataReader(for: attachment).data
            let contentType = attachment.contentType.preferredMIMEType ?? attachment.contentType.identifier
            switch versionedResource {
            case .r4(let resource):
                versionedResource = .r4(resource.addingAttachment(data, contentType: contentType))
            case .dstu2(let resource):
                versionedResource = .dstu2(resource.addingAttachment(data, contentType: contentType))
            }
        }
        return try FHIRResource(versionedResource: versionedResource, displayName: record.displayName, identitySource: identitySource)
    }
}


extension ModelsR4.Resource {
    /// Fills the first attachment of the same content type that has no data, or else adds a new one.
    fileprivate func addingAttachment(_ data: Data, contentType: String) -> any ModelsR4.Resource {
        let contentType: ModelsR4.FHIRPrimitive<ModelsR4.FHIRString> = contentType.asFHIRStringPrimitive()
        let content = ModelsR4.FHIRPrimitive(ModelsR4.Base64Binary(data.base64EncodedString()))
        switch self {
        case var reference as ModelsR4.DocumentReference:
            if let index = reference.content.firstIndex(where: { $0.attachment.contentType == contentType && $0.attachment.data == nil }) {
                reference.content[index].attachment.data = content
            } else {
                let attachment = ModelsR4.Attachment(contentType: contentType, data: content)
                reference.content.append(ModelsR4.DocumentReferenceContent(attachment: attachment))
            }
            return reference
        case var report as ModelsR4.DiagnosticReport:
            var presentedForm = report.presentedForm ?? []
            if let index = presentedForm.firstIndex(where: { $0.contentType == contentType && $0.data == nil }) {
                presentedForm[index].data = content
            } else {
                presentedForm.append(ModelsR4.Attachment(contentType: contentType, data: content))
            }
            report.presentedForm = presentedForm
            return report
        default:
            return self
        }
    }
}


extension ModelsDSTU2.Resource {
    /// Fills the first attachment of the same content type that has no data, or else adds a new one.
    fileprivate func addingAttachment(_ data: Data, contentType: String) -> any ModelsDSTU2.Resource {
        let contentType: ModelsDSTU2.FHIRPrimitive<ModelsDSTU2.FHIRString> = contentType.asFHIRStringPrimitive()
        let content = ModelsDSTU2.FHIRPrimitive(ModelsDSTU2.Base64Binary(data.base64EncodedString()))
        switch self {
        case var reference as ModelsDSTU2.DocumentReference:
            if let index = reference.content.firstIndex(where: { $0.attachment.contentType == contentType && $0.attachment.data == nil }) {
                reference.content[index].attachment.data = content
            } else {
                let attachment = ModelsDSTU2.Attachment(contentType: contentType, data: content)
                reference.content.append(ModelsDSTU2.DocumentReferenceContent(attachment: attachment))
            }
            return reference
        case var report as ModelsDSTU2.DiagnosticReport:
            var presentedForm = report.presentedForm ?? []
            if let index = presentedForm.firstIndex(where: { $0.contentType == contentType && $0.data == nil }) {
                presentedForm[index].data = content
            } else {
                presentedForm.append(ModelsDSTU2.Attachment(contentType: contentType, data: content))
            }
            report.presentedForm = presentedForm
            return report
        default:
            return self
        }
    }
}
