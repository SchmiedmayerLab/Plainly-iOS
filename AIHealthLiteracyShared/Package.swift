// swift-tools-version: 6.2
//
// This source file is part of the Stanford AI Health Literacy iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PackageDescription


let package = Package(
    name: "AIHealthLiteracyShared",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "AIHealthLiteracyShared", targets: ["AIHealthLiteracyShared"]),
        .library(name: "AIHealthLiteracyStudyDefinitions", targets: ["AIHealthLiteracyStudyDefinitions"]),
        .executable(name: "AIHealthLiteracyCLI", targets: ["AIHealthLiteracyCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/SchmiedmayerLab/Spezi.git", from: "0.1.7"),
        .package(url: "https://github.com/apple/FHIRModels.git", .upToNextMinor(from: "0.8.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0")
    ],
    targets: [
        .target(
            name: "AIHealthLiteracyShared",
            dependencies: [
                .product(name: "SpeziFoundation", package: "Spezi"),
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "SpeziLLM", package: "Spezi"),
                .product(name: "SpeziLLMOpenAI", package: "Spezi"),
                .product(name: "SpeziLocalStorage", package: "Spezi"),
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
            name: "AIHealthLiteracyStudyDefinitions",
            dependencies: [
                "AIHealthLiteracyShared",
                .product(name: "ModelsR4", package: "FHIRModels")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault")
            ]
        ),
        .executableTarget(
            name: "AIHealthLiteracyCLI",
            dependencies: [
                "AIHealthLiteracyShared",
                "AIHealthLiteracyStudyDefinitions",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "AIHealthLiteracySharedTests",
            dependencies: ["AIHealthLiteracyShared", "AIHealthLiteracyStudyDefinitions"],
            resources: [.process("Resources")]
        )
    ]
)
