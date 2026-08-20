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
        // No traits: Grove's default `Textual` renders no text at all in the study chat, so messages are
        // laid out with the height they need and nothing drawn. Markdown goes through `AttributedString`
        // instead, which also keeps a message readable to VoiceOver.
        .package(url: "https://github.com/SchmiedmayerLab/Grove.git", revision: "665d619d01d98c86e15d9c84661ee55cf265c58e", traits: []),
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
