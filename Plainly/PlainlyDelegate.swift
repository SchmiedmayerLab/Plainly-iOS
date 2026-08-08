//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable type_contents_order all

import FirebaseCore
import GeneratedOpenAIClient // periphery:ignore - false positive
import PlainlyShared
@_spi(APISupport) import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziFirebaseConfiguration
import SpeziFirebaseStorage
import SpeziFoundation
import SpeziHealthKit
import SpeziKeychainStorage
import SpeziLLM
import SpeziLLMOpenAI


final class PlainlyDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        return Configuration(standard: PlainlyStandard()) {
            if !FeatureFlags.disableFirebase, let config = firebaseConfig {
                firebaseModules(using: config)
            }
            let openAIInterceptor = OpenAIRequestInterceptor()
            openAIInterceptor
            FHIRInterpretationModule()
            HealthKit {
                if !FeatureFlags.disableHealthRecords, HKHealthStore().supportsHealthRecords() {
                    RequestReadAccess(other: PlainlyStandard.recordTypes)
                    for type in PlainlyStandard.recordTypes {
                        CollectSamples(type, start: .manual, continueInBackground: false, timeRange: .newSamples)
                    }
                }
            }
            LLMRunner {
                LLMOpenAIPlatform(configuration: .init(
                    authToken: self.openAITokenConfig,
                    concurrentStreams: 100,
                    retryPolicy: .attempts(3),  // Automatically perform up to 3 retries on retryable OpenAI API status codes
                    middlewares: [openAIInterceptor]
                ))
            }
        }
    }

    private var firebaseConfig: AppConfigFile.FirebaseConfigDictionary? {
        let config = FeatureFlags.useFirebaseEmulator ? .emulator : AppConfigFile.current().firebaseConfig
        guard let config else {
            AppDiagnostics.configuration.fault("Firebase configuration is unavailable")
            return nil
        }
        let missingKeys = config.missingRequiredKeys
        guard missingKeys.isEmpty else {
            AppDiagnostics.configuration.fault(
                "Firebase configuration contains missing or invalid required keys: \(missingKeys.joined(separator: ","), privacy: .public)"
            )
            return nil
        }
        return config
    }
    
    @ModuleBuilder
    private func firebaseModules(using config: AppConfigFile.FirebaseConfigDictionary) -> ModuleCollection {
        let options = firebaseOptions(using: config)
        ConfigureFirebaseApp(options: options)
        AccountConfiguration(
            service: FirebaseAccountService(
                providers: [],
                emulatorSettings: accountEmulatorSettings
            ),
            configuration: []
        )
        if FeatureFlags.useFirebaseEmulator {
            FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
            FirebaseFunctions(emulatorHost: "localhost", port: 5001)
        } else {
            FirebaseStorageConfiguration()
            FirebaseFunctions()
        }
        FirebaseUpload()
    }

    private func firebaseOptions(using config: AppConfigFile.FirebaseConfigDictionary) -> FirebaseOptions {
        guard let options = FirebaseOptions(config) else {
            AppDiagnostics.configuration.fault("FirebaseOptions could not be created from the configured keys")
            preconditionFailure("Invalid Firebase configuration")
        }
        return options
    }
    
    private var accountEmulatorSettings: (host: String, port: Int)? {
        if FeatureFlags.useFirebaseEmulator {
            (host: "localhost", port: 9099)
        } else {
            nil
        }
    }
    
    nonisolated private var openAITokenConfig: RemoteLLMInferenceAuthToken {
        if Plainly.mode.requiresUserProvidedAPIKey {
            return .keychain(tag: .openAIKey, username: "Plainly_OpenAI_Token")
        } else {
            return .closure { @MainActor in
                guard let study = Self.spezi?.module(FHIRInterpretationModule.self)?.currentStudy else {
                    AppDiagnostics.configuration.error("Inference credential requested before a study was selected")
                    return nil
                }
                let key = study.config.openAIAPIKey
                if case .regular = study.config.openAIEndpoint, key?.isEmpty != false {
                    AppDiagnostics.configuration.fault("Direct inference is missing its configured credential")
                }
                return key
            }
        }
    }
}


extension FirebaseOptions {
    convenience init?(_ config: AppConfigFile.FirebaseConfigDictionary) {
        let fileManager = FileManager.default
        let tmpUrl = URL.temporaryDirectory.appendingPathComponent("FirebaseConfig", conformingTo: .propertyList)
        try? fileManager.removeItem(at: tmpUrl)
        do {
            try config.asNSDictionary().write(to: tmpUrl)
        } catch {
            AppDiagnostics.configuration.logError(error, context: "Writing temporary Firebase configuration")
            return nil
        }
        defer {
            try? fileManager.removeItem(at: tmpUrl)
        }
        self.init(contentsOfFile: tmpUrl.absoluteURL.path(percentEncoded: false))
    }
}
