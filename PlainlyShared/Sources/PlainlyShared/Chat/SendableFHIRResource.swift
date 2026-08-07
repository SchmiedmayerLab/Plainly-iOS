//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

// periphery:ignore:all - API

public import Foundation
public import SpeziFHIR
/// Sendable mechanism for `FHIRResource`s with limited access needed for Plainly.
public struct SendableFHIRResource: Hashable, Sendable {
    private var resource: FHIRResource
    
    
    public var id: FHIRResource.ID {
        resource.id
    }
    
    public var functionCallIdentifier: String {
        resource.functionCallIdentifier
    }
    
    public var date: Date? {
        resource.date
    }
    
    public var jsonDescription: String {
        resource.jsonDescription
    }
    
    
    public init(resource: FHIRResource) {
        self.resource = resource
    }
    
    
    public mutating func stringifyAttachments() throws {
        try resource.stringifyAttachments()
    }
}
