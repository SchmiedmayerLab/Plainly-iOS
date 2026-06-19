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
        .package(url: "https://github.com/StanfordSpezi/SpeziFoundation.git", from: "2.7.2"),
        .package(url: "https://github.com/apple/FHIRModels.git", .upToNextMajor(from: "0.7.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/StanfordSpezi/SpeziLLM.git", from: "0.13.8"),
        .package(url: "https://github.com/StanfordSpezi/SpeziStorage.git", from: "2.1.4"),
        .package(url: "https://github.com/StanfordSpezi/SpeziFHIR.git", from: "0.10.0")
    ],
    targets: [
        .target(
            name: "AIHealthLiteracyShared",
            dependencies: [
                .product(name: "SpeziFoundation", package: "SpeziFoundation"),
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "SpeziLLM", package: "SpeziLLM"),
                .product(name: "SpeziLLMOpenAI", package: "SpeziLLM"),
                .product(name: "SpeziLocalStorage", package: "SpeziStorage"),
                .product(name: "SpeziFHIR", package: "SpeziFHIR")
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
