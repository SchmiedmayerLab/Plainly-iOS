// swift-tools-version: 6.2
//
// This source file is part of the Plainly iOS project
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
        .package(
            url: "https://github.com/SchmiedmayerLab/Spezi.git",
            revision: "b5ce1a15688afffd83d7f757884e86e17a65b65c",
            traits: [.trait(name: "Textual")]
        ),
        .package(url: "https://github.com/apple/FHIRModels.git", .upToNextMinor(from: "0.9.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0")
    ],
    targets: [
        .target(
            name: "PlainlyShared",
            dependencies: [
                .product(name: "SpeziFoundation", package: "Spezi"),
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "SpeziLLM", package: "Spezi"),
                .product(name: "SpeziLLMOpenAI", package: "Spezi"),
                .product(name: "SpeziLocalStorage", package: "Spezi"),
                .product(name: "SpeziQuestionnaire", package: "Spezi"),
                .product(name: "SpeziFHIR", package: "Spezi")
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
                .product(name: "SpeziHealthKit", package: "Spezi")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "PlainlySharedTests",
            dependencies: ["PlainlyShared", "PlainlyStudyDefinitions"]
        )
    ]
)
