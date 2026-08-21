// swift-tools-version: 6.2
//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PackageDescription


let package = Package(
    name: "PlainlyShared",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PlainlyShared", targets: ["PlainlyShared"]),
        .library(name: "PlainlyStudyDefinitions", targets: ["PlainlyStudyDefinitions"]),
        .executable(name: "PlainlyCLI", targets: ["PlainlyCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/SchmiedmayerLab/Grove.git", exact: "0.3.0-beta.4"),
        .package(url: "https://github.com/SchmiedmayerLab/FHIRModels.git", .upToNextMinor(from: "0.9.3")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0")
    ],
    targets: [
        .target(
            name: "PlainlyShared",
            dependencies: [
                .product(name: "GroveFoundation", package: "Grove"),
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "GroveLLM", package: "Grove"),
                .product(name: "GroveLLMOpenAI", package: "Grove"),
                .product(name: "GroveLocalStorage", package: "Grove"),
                .product(name: "GroveQuestionnaire", package: "Grove"),
                .product(name: "GroveFHIR", package: "Grove")
            ],
            resources: [
                .copy("Resources/Synthetic Patients")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault")
            ]
        ),
        .target(
            name: "PlainlyStudyDefinitions",
            dependencies: [
                "PlainlyShared",
                .product(name: "ModelsR4", package: "FHIRModels")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault")
            ]
        ),
        .executableTarget(
            name: "PlainlyCLI",
            dependencies: [
                "PlainlyShared",
                "PlainlyStudyDefinitions",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GroveHealthKit", package: "Grove")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "PlainlySharedTests",
            dependencies: ["PlainlyShared", "PlainlyStudyDefinitions", "PlainlyCLI"]
        )
    ]
)
