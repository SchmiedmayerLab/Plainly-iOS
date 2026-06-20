<!--

This source file is part of the Stanford AI Health Literacy iOS project

SPDX-FileCopyrightText: 2023 Stanford University

SPDX-License-Identifier: MIT

-->

# AIHealthLiteracy

[![codecov](https://codecov.io/gh/SchmiedmayerLab/AIHealthLiteracy-iOS/branch/main/graph/badge.svg?token=9fvSAiFJUY)](https://codecov.io/gh/SchmiedmayerLab/AIHealthLiteracy-iOS)

## Study Overview

This repository demonstrates how large language models can interpret FHIR-formatted patient data and other relevant clinical context. The application is designed as a research study to evaluate the effectiveness of conversational AI in helping users understand their health records. Participants can engage with their health data through a conversational interface, ask follow-up questions, and receive AI-generated summaries and explanations tailored to their system language.

## Disclaimer

AIHealthLiteracy is an experimental iOS app. It is designed for general informational purposes, providing users with a platform to interact with health records stored in Apple Health using OpenAI models.

- **Not a Substitute for Professional Advice:** AIHealthLiteracy is not intended as a substitute for professional medical advice, diagnosis, or treatment.

- **Limitations of AI Models:** AI models can sometimes make mistakes or generate misleading information. Always cross-check and verify the information provided.

- **Use at Your Own Risk:** Any use of AIHealthLiteracy is at the user's own risk. Always consult a qualified healthcare provider for personalized advice regarding your health and well-being.

- **Demonstration Only:** This app is intended for demonstration only and should not be used to process any personal health information.

Remember that your health data will be sent to OpenAI for processing.
Please review the [OpenAI API data usage policies and settings](https://openai.com/policies/api-data-usage-policies) accordingly.


## HealthKit Access

AIHealthLiteracy requires access to the FHIR health records stored in the Apple Health app. You can select the different types of health records you wish to inspect in AIHealthLiteracy.

If no health records are available, follow the instructions to connect and retrieve your health records from your provider. If your health records are visible in the Apple Health app, ensure that AIHealthLiteracy has access to your health records in the Apple Health app. You can find these settings in the privacy section of your profile in Apple Health.

> [!TIP]
> You can also use a set of [Synthea](https://pubmed.ncbi.nlm.nih.gov/29025144/)-based patients to test out the application without the need to connect it to HealthKit. You can select the synthetic patients in the account settings view of the application.

## Build and Run the Application

You can build and run the application using [Xcode](https://developer.apple.com/xcode/) by opening **AIHealthLiteracy.xcodeproj**.

When running AIHealthLiteracy via Xcode, you can use the `--mode` CLI flag to control the behavior of the app (configurable via the Run scheme):
- `--mode standalone` performs a regular launch, where AIHealthLiteracy can be used with a custom OpenAI API key to use the chat mode;
- `--mode study:<study-id>` launches AIHealthLiteracy into its study mode, loads the study with the specified ID from the UserStudyConfig.plist file, and automatically opens it;
- `--mode study` launches AIHealthLiteracy into its study mode, showing a "Scan QR Code" button to select and open a study.


### UserStudyConfig.plist File

AIHealthLiteracy contains a UserStudyConfig.plist file, which is loaded on launch and used to configure the app and populate it with studies.
The UserStudyConfig.plist file contains the following:
- Firebase configuration: used, if present, to connect the app to a Firebase environment for uploading study reports
- app launch mode: used to control how the app should behave upon launch (e.g., whether study-only mode should be enabled and whether to directly launch a study)
- list of available studies (see the `Study` type within the iOS codebase for more details)

The UserStudyConfig.plist file bundled with the repository is missing some data (the OpenAI key, the Firebase credentials, and the study report encryption key).
You can use the `export-config` tool in the AIHealthLiteracyShared folder to generate a complete config file:
```bash
swift run AIHealthLiteracyCLI export-config \
    -f ~/GoogleService-Info.plist \
    -o edu.stanford.aihealthliteracy.study1:sk-123 \
    -o edu.stanford.aihealthliteracy.study2:sk-456 \
    -k edu.stanford.aihealthliteracy.study1:./public_key1.pem \
    -k edu.stanford.aihealthliteracy.study2:./public_key2.pem \
    ../AIHealthLiteracy/Supporting\ Files/UserStudyConfig.plist
```

Some flags use a `-x <studyId>:<value>` format and can be specified multiple times to specify each study's value.
You can also add one entry that uses `*` as the study ID to define a default value for all studies not explicitly listed.
For example, `-o '*':$OPENAI_KEY` would define the OpenAI key used by all studies that don't have a `-o` entry of their own.

### Study Report File Encryption

The report files generated from the usability study are optionally encrypted using the public key stored in UserStudyConfig.plist.

You can generate a public/private key pair using the following commands:
```bash
# generate private key
openssl genpkey -algorithm X25519 -out private_key.pem

# extract public key
openssl pkey -in private_key.pem -pubout -out public_key.pem
```

Use the `export-config` tool shown above to place your public key in the user study config file:

To decrypt a report file created by the app, you can use the `decrypt-study-report` tool in the AIHealthLiteracyShared folder:
```bash
swift run AIHealthLiteracyCLI decrypt-study-report -k private_key.pem studyReport report.json
```

## Session Simulation

The AIHealthLiteracyShared subpackage contains a tool that lets you simulate user chat sessions.

During a simulated chat session, the LLM is provided with the same context and data it would receive during normal app usage, except that the inputs (both the patient's health records and the questions being asked by the user) are predefined.
This allows you to evaluate how different models (or even the same model across multiple conversations) handle various scenarios and situations.

For each simulated session, a report file is generated with the same structure as the report files generated during regular app sessions.

```bash
swift run AIHealthLiteracyCLI simulate-session config.json output/
```

Session simulation is controlled via a JSON config file. **API credentials are never stored in the config file** — they are read from environment variables at runtime:

| Service | Required env var |
|---------|-----------------|
| `OpenAI` | `OPENAI_API_KEY` |
| `Firebase` | `GOOGLE_CREDENTIALS_PLIST` (path to `GoogleService-Info.plist`) |
| `Firebase-Emulator` | *(none — connects to the local emulator suite)* |

Additional optional environment variables:

| Env var | Default | Effect |
|---------|---------|--------|
| `FIREBASE_REGION` | `us-central1` | Firebase Functions/Auth region |
| `FIREBASE_PROJECT_ID` | `demo-project` | Project ID override for the emulator when `GOOGLE_CREDENTIALS_PLIST` is not set (emulator mode only) |
| `FIREBASE_AUTH_EMULATOR_HOST` | `localhost:9099` | Auth emulator address (`host:port`) |
| `FIREBASE_FUNCTIONS_EMULATOR_HOST` | `localhost:5001` | Functions emulator address (`host:port`) |

Each entry in the JSON config defines the parameters of one simulation:
- `numberOfRuns` — how many times to repeat this session
- `studyId` — the study whose prompts and context to use
- `bundleName` — name of an embedded synthetic patient, or a path to a FHIR bundle JSON file (resolved relative to the config file)
- `model` / `temperature` — OpenAI model and sampling temperature
- `userQuestions` — the questions the simulated patient asks
- `service` *(optional)* — `"OpenAI"`, `"Firebase"`, or `"Firebase-Emulator"`; if omitted, inferred from the environment (`OPENAI_API_KEY` → OpenAI, `GOOGLE_CREDENTIALS_PLIST` → Firebase, otherwise Firebase-Emulator)
- `name` *(optional)* — human-readable label used as the output filename prefix
- `customSystemPrompt` *(optional)* — custom system prompt, replaces the study's default system prompt

The example config below performs six simulated runs of the `edu.stanford.aihealthliteracy.gynStudy` study, three each using GPT-4o and GPT-4o-mini, against two different backends:
```json
[{
    "numberOfRuns": 3,
    "name": "gyn-gpt4o-openai",
    "studyId": "edu.stanford.aihealthliteracy.gynStudy",
    "bundleName": "Elena Kim",
    "model": "gpt-4o",
    "temperature": 1,
    "service": "OpenAI",
    "userQuestions": [
        "Tell me about my recent diagnoses and how they affect my fertility.",
        "How are my hormonal levels?"
    ]
}, {
    "numberOfRuns": 3,
    "name": "gyn-gpt4o-firebase",
    "studyId": "edu.stanford.aihealthliteracy.gynStudy",
    "bundleName": "Elena Kim",
    "model": "gpt-4o",
    "temperature": 1,
    "service": "Firebase",
    "userQuestions": [
        "Tell me about my recent diagnoses and how they affect my fertility.",
        "How are my hormonal levels?"
    ]
}]
```

Run with the appropriate credentials:

```bash
# OpenAI
OPENAI_API_KEY=sk-proj-...
swift run AIHealthLiteracyCLI simulate-session config.json output/
```

```bash
# Firebase (production)
GOOGLE_CREDENTIALS_PLIST=~/GoogleService-Info.plist
swift run AIHealthLiteracyCLI simulate-session config.json output/
```

```bash
# Firebase emulator (no credentials needed)
FIREBASE_PROJECT_ID=...
swift run AIHealthLiteracyCLI simulate-session config.json output/
```

Reports are saved to a timestamped subdirectory inside the output directory, named `<index>-<name>-<run>.json` (e.g. `00-gyn-gpt4o-openai-1.json`).


## Contributing

Contributions to this project are welcome. Please read the [contribution guidelines](https://github.com/SchmiedmayerLab/.github/blob/main/CONTRIBUTING.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.


## License

This project is licensed under the MIT License. See [Licenses](LICENSES) for more information.

![Stanford and Stanford Medicine logos](https://raw.githubusercontent.com/SchmiedmayerLab/.github/main/assets/stanford-footer-light.png#gh-light-mode-only)
![Stanford and Stanford Medicine logos](https://raw.githubusercontent.com/SchmiedmayerLab/.github/main/assets/stanford-footer-dark.png#gh-dark-mode-only)
