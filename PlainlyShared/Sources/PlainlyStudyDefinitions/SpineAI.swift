//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable line_length

import GroveQuestionnaire
public import PlainlyShared


extension Study {
    /// The canonical FHIR identifier of the SpineAI intake questionnaire.
    public static let spineAIQuestionnaireIdentifier = "https://spineai.stanford.edu/fhir/Questionnaire/lumbar-spine-triage"

    /// Plainly's SpineAI study
    public static var spineAI: Study {
        let effectivenessQuestion: Questionnaire.Task = .scale("How effective was the app in helping to answer your spine-related health question?", options: effectivenessOptions)
        return Study(
            id: "edu.stanford.plainly.spineAI",
            title: "SpineAI",
            explainer: "Welcome to the SpineAI Study!",
            llmModel: .gpt5_5,
            ragEnabled: true,
            summarizeSingleResourcePrompt: .spineAIResourcePrompt,
            interpretMultipleResourcesPrompt: .spineAISystemPrompt,
            chatTitleConfig: .studyTitle,
            initialQuestionnaire: "SpineAI_InitialSurvey",
            tasks: [
                Task(
                    id: "0",
                    title: nil,
                    instructions: "Ask SpineAI to explain your most recent MRI or X-ray report in plain language, then ask any follow-up questions about what the findings mean for your pain and function.",
                    assistantMessagesLimit: 2...5,
                    questions: [
                        effectivenessQuestion,
                        .freeText("What surprised you about the app’s answer, either positively or negatively?", isOptional: true)
                    ]
                ),
                Task(
                    id: "1",
                    title: nil,
                    instructions: "Ask SpineAI what treatment options exist for your specific condition, including the non-surgical ones, and have it compare the pros and cons of each for your situation.",
                    assistantMessagesLimit: 1...5,
                    questions: [effectivenessQuestion]
                ),
                // The protocol gates this task and the recovery task below on baseline gate
                // question G1 ("Is surgery currently one of the options being discussed for your
                // spine condition?"), answered before the session. Tasks cannot branch, so both
                // are always shown and their prompts carry the condition instead.
                Task(
                    id: "2",
                    title: nil,
                    instructions: "If surgery is one of your options, ask SpineAI what the recommended procedure would involve and what the risks and complications would be for someone with your profile.",
                    assistantMessagesLimit: 1...5,
                    questions: [effectivenessQuestion]
                ),
                Task(
                    id: "3",
                    title: nil,
                    instructions: "Ask SpineAI how to manage your current pain and medications — how to take them, what side effects to watch for, and what to do if the pain isn’t improving as expected.",
                    assistantMessagesLimit: 1...5,
                    questions: [effectivenessQuestion]
                ),
                Task(
                    id: "4",
                    title: nil,
                    instructions: "Ask SpineAI what recovery would realistically look like if you had the recommended procedure — week by week, and when you could return to work, driving, and the activities that matter most to you.",
                    assistantMessagesLimit: 1...5,
                    questions: [effectivenessQuestion]
                ),
                Task(
                    id: "5",
                    title: nil,
                    instructions: "Ask SpineAI how to get a second opinion and what your insurance is likely to cover, and tell it about any fears you have about your condition or a possible operation and ask what can help you cope.",
                    assistantMessagesLimit: 1...5,
                    questions: [effectivenessQuestion]
                ),
                Task(
                    id: "6",
                    title: nil,
                    instructions: "Before we end our session, feel free to ask the app any medical questions you might have related to your spine problem or symptoms.",
                    assistantMessagesLimit: 1...10,
                    questions: freeExplorationQuestions
                ),
                Task(
                    id: "7",
                    title: nil,
                    instructions: nil,
                    assistantMessagesLimit: nil,
                    questions: postInterventionQuestions
                ),
                Task(
                    id: "8",
                    title: nil,
                    instructions: nil,
                    assistantMessagesLimit: nil,
                    questions: confidenceQuestions
                )
            ],
            // Tried out in simulators and development deployments; participants see neither yet.
            previews: .init(defaultExplanationLevel: .balanced, generatesImages: true)
        )
    }
}


// The study's questionnaire corrects the shared effectiveness scale's middle option and rates the
// other questions on scales that carry an explicit N/A choice, so none of these can reuse the
// shared scales, which studies that are already collecting pin.
private let effectivenessOptions: Study.Task.AnswerOptions = [
    "Very effective",
    "Somewhat effective",
    "Neither effective nor ineffective",
    "Somewhat ineffective",
    "Very ineffective"
]

private let websiteComparisonOptions: Study.Task.AnswerOptions = [
    "Significantly better",
    "Slightly better",
    "No change",
    "Slightly worse",
    "Significantly worse",
    "N/A — I have not used websites for this"
]

private let doctorComparisonOptions: Study.Task.AnswerOptions = [
    "Significantly better",
    "Slightly better",
    "No change",
    "Slightly worse",
    "Significantly worse",
    "N/A"
]

private let appointmentChangeOptions: Study.Task.AnswerOptions = [
    "Yes, a lot",
    "Yes, somewhat",
    "No",
    "Not sure"
]

private let agreementOptions: Study.Task.AnswerOptions = [
    "Strongly Disagree",
    "Disagree",
    "Agree",
    "Strongly Agree",
    "N/A"
]

private let confidenceOptions: Study.Task.AnswerOptions = [
    "Not at all confident",
    "Slightly confident",
    "Moderately confident",
    "Very confident",
    "Extremely confident",
    "N/A"
]


private let freeExplorationQuestions: [Questionnaire.Task] = [
    .scale("Compared to health information websites, how do you rate the app’s responses?", options: websiteComparisonOptions),
    .scale("Compared to what your doctor has told you, how do you rate the app’s responses?", options: doctorComparisonOptions),
    .freeText("What were the most and least useful features of the app? Do you have any suggestions to share?", isOptional: true),
    .scale("Has using the app changed what you plan to ask or discuss at your upcoming appointment?", options: appointmentChangeOptions),
    .freeText("If yes: What will you ask that you would not have asked before?", isOptional: true),
    .scale(
        "On a scale of 0–10, how likely are you to recommend this tool to a friend or colleague?",
        range: 0...10,
        labels: [0: "Would not recommend", 10: "Would recommend"]
    )
]


private let postInterventionQuestions: [Questionnaire.Task] = [
    .instructional(
        """
        Please complete the survey below. Thank you!

        In the future, if you had SpineAI available…

        These are the same statements you answered in the online questionnaire before this session. Please answer them again now, based on how you would feel about managing your spine condition with continued access to an application like SpineAI.
        """
    ),
    .instructional(
        """
        Section A — Managing my spine condition

        Below are some statements that people sometimes make when they talk about their spine condition. Please indicate how much you agree or disagree with each statement as it applies to you personally. Your answers should be what is true for you and not just what you think others want you to say. If a statement does not apply to you, select N/A.
        """
    ),
    .scale("When all is said and done, I am the person who is responsible for managing my spine condition.", options: agreementOptions),
    .scale("Taking an active role in my spine care affects my back/neck health and ability to function.", options: agreementOptions),
    .scale("I understand what each of my treatments or medications for my spine condition is for.", options: agreementOptions),
    .scale("I am confident I can tell my spine care provider concerns I have, even when he or she does not ask.", options: agreementOptions),
    .scale("I am confident I can tell whether I need to see a doctor for my spine problem or whether I can manage it on my own.", options: agreementOptions),
    .scale("I am confident I can help prevent or reduce problems associated with my spine condition.", options: agreementOptions),
    .scale("I know the lifestyle changes — like activity, posture, and exercise — that are recommended for my spine condition.", options: agreementOptions),
    .scale("I am confident I can follow through on treatments for my spine condition that I may need to do at home (e.g., exercises, stretches).", options: agreementOptions),
    .scale("I am confident I can take actions that will help prevent or minimize symptoms of my spine condition.", options: agreementOptions),
    .scale("I am confident I can follow through on recommendations my spine provider makes, such as physical therapy or exercise.", options: agreementOptions),
    .scale("I understand the nature and causes of my spine condition.", options: agreementOptions),
    .scale("I know the different treatment options available for my spine condition (e.g., physical therapy, injections, surgery).", options: agreementOptions),
    .scale("I have been able to keep up with the activity or exercise changes I have made for my spine health.", options: agreementOptions),
    .scale("I know how to prevent further problems with my spine.", options: agreementOptions),
    .scale("I know about the self-care and self-treatments for my spine condition.", options: agreementOptions),
    .scale("I have made the changes in my activity and exercise that are recommended for my spine condition.", options: agreementOptions),
    .scale("I am confident I can figure out solutions when new problems arise with my spine.", options: agreementOptions),
    .scale("I am able to handle symptoms of my spine condition on my own at home.", options: agreementOptions),
    .scale("I am confident I can maintain activity and exercise changes for my spine, even during times of stress.", options: agreementOptions),
    .scale("I am able to handle flare-ups of my spine condition on my own at home.", options: agreementOptions),
    .scale("I am confident I can keep my spine problems from interfering with the things I want to do.", options: agreementOptions),
    .scale("Managing recommendations by my physicians for my spine condition is too hard for me on a daily basis.", options: agreementOptions)
]


// Clusters follow the session-task order of the document. The document gates Cluster 3 and
// Cluster 5 on G1 like their session tasks and marks that in their headers; without branching
// support every cluster is always shown, so the headers drop the gate annotation and N/A plus
// skippable questions stand in for it. The document's per-cluster "Session task." reminders are
// staff-facing context and are not rendered.
private let confidenceClusters: [(header: String, questions: [String])] = [
    ("Cluster 1 — Diagnosis & imaging", [
        "How confident are you that you could explain what your MRI or X-ray report says, in your own words?",
        "How confident are you that you could describe what exactly is wrong with your spine, and how severe it is?",
        "How confident are you that you know what is causing your pain, and whether anything else could be causing your symptoms?",
        "How confident are you that you know what is likely to happen to your spine if you do nothing right now?"
    ]),
    ("Cluster 2 — Treatment options & decision-making", [
        "How confident are you that you could list all of your treatment options, including the non-surgical ones?",
        "How confident are you that you know the pros and cons of physical therapy, injections and surgery for your condition?",
        "How confident are you that you could explain the difference between a decompression, a fusion and a disc replacement, and which would fit your situation?",
        "How confident are you that you know the specific things you need to do at home to treat your spine condition?",
        "How confident are you that you know whether it would be better to operate sooner or to wait, and what the risks of waiting would be?"
    ]),
    ("Cluster 3 — Procedure, risks & surgeon", [
        "How confident are you that you know what the operation would involve, if surgery were recommended for you?",
        "How confident are you that you know what complications could happen, and how likely they would be for someone like you?",
        "How confident are you that you know what anaesthesia options you would have, and what you should know about them?",
        "How confident are you that you know how to find out how experienced a surgeon is with this procedure, and what their outcomes are?"
    ]),
    ("Cluster 8 — Pain & medication", [
        "How confident are you that you know how to take your pain medication — whether with food, whether you can stop it suddenly or need to taper, and what to do about side effects?",
        "How confident are you that you know what to do if your pain is not improving as fast as you expected, and whether that is a bad sign?"
    ]),
    ("Cluster 5 — Recovery expectations", [
        "How confident are you that you know what recovery would look like week by week, if you had surgery for your spine condition?",
        "How confident are you that you know when you could go back to work, drive, and return to the activities that matter to you?"
    ]),
    ("Cluster 9 — System, insurance & emotions", [
        "How confident are you that you know whether your insurance would cover the treatments you are considering, and what to ask your insurer before deciding?",
        "How confident are you that you know how to get a second opinion, and which records to bring?",
        "How confident are you that you know what can help you cope with worries about your condition or about a possible operation?"
    ])
]

private let confidenceQuestions: [Questionnaire.Task] = {
    var questions: [Questionnaire.Task] = [
        .instructional(
            """
            Below are the same statements you answered in the online questionnaire before this session. Now that you have used the app, please rate again how confident you feel about your own situation, and — if you can — briefly write what you would say. If a statement does not apply to you, select N/A.

            Some questions ask you to think about treatments, including surgery, that you may or may not need. Some people find this uncomfortable. You may skip any question, and you may stop at any time.
            """
        )
    ]
    for (header, clusterQuestions) in confidenceClusters {
        questions.append(.instructional(header))
        for question in clusterQuestions {
            // The introduction promises that any question can be skipped, so the scales are
            // optional like the free-text answers.
            questions.append(.scale(question, options: confidenceOptions, isOptional: true))
            questions.append(.freeText("In a sentence, what would you say?", isOptional: true))
        }
    }
    return questions
}()


extension FHIRPrompt {
    fileprivate static let spineAISystemPrompt: Self = """
        You are SpineAI, a clear, evidence-based clinical assistant giving a second-opinion-style explanation to a patient who has already spoken with their care team. You are not a substitute for a licensed physician and you do not issue final treatment orders, but you give grounded interpretations rather than vague neutrality.

        ANSWER LENGTH
        - Match the answer's length to the question's complexity, and keep it short either way: about 350 to 400 words typically. Lead with the answer, give only the reasoning that changes what the patient does, then stop.
        - This ceiling never applies when safety or urgent triage is at issue. Say everything the patient needs to recognize a red flag and act on it, however long that takes.
        - That is a ceiling, not a target, and being brief means cutting padding, not substance — still ground the answer in the documents you retrieved. One or two sentences is a good answer when the question is simple.
        - Never restate a point the patient already has from earlier in the answer or the conversation. Depth is available on request: trust them to ask, and give more when they do.

        GROUND ANSWERS IN THIS PATIENT WHERE IT MATTERS
        - When a question depends on this patient's situation, use the "get_resources" tool to retrieve the minimum FHIR resources needed to answer accurately; never expose JSON, FHIR structure, or other technical details.
        - Treat any question about medication safety, drug interactions, or how a treatment interacts with an existing condition as always depending on this patient's situation: retrieve their current medications and relevant conditions before answering, even if you believe you already know the answer generally.
        - The resource identifiers you see when choosing what to retrieve are not themselves verified chart data. If you have not actually called "get_resources" and read the returned resource, do not present what you inferred from an identifier's name as something "your chart shows" — retrieve it first, or speak in general terms and say you'd need to pull the specific record to confirm.
        - General educational questions may be answered from established clinical knowledge, but check the chart whenever this patient's own findings could change the answer: symptom duration, dominant symptom, imaging findings, and especially any reported weakness or neurologic change.
        - If a referenced record or note is unavailable, say so in one sentence, then give what general guidance you responsibly can and name what the missing record would clarify. If retrieval turns up nothing relevant, say that plainly in one or two sentences and stop — do not pad the response with generic content to compensate.
        - Do not assume a record's date is the present day. If you cannot determine the current date, say so rather than guessing whether information is up to date.

        BE CLEAR AND CALIBRATED; AVOID FALSE BALANCE
        - Lead with the most likely answer, then brief reasoning, then what to do next.
        - When evidence or guidelines are strong, state the favored approach directly and do not present a rarely-indicated option as if it were co-equal. For example, for central canal stenosis without instability, decompression is usually the indicated procedure and fusion is generally reserved for instability; when fusion is discussed, name its real downsides (longer recovery, risk of non-union, added stress on adjacent segments).
        - When evidence is moderate or uncertain, do not stop at uncertainty: state the leading interpretation, what lowers confidence, and what next step would clarify the issue. If a management decision depends on a missing discriminator (for example instability on imaging, duration of symptoms, or response to conservative care), name it explicitly.
        - Do not answer a conditional or nuanced question with a flat "yes" or "no." If the honest answer is "usually, but it depends on X," say that — lead with the likely answer, but keep the condition attached to it rather than dropping it for simplicity. When a term the patient used is vernacular rather than a precise clinical category (for example "low grade," or a term like "instability" that has no single agreed clinical definition), say so plainly instead of answering as if it were exact.
        - When you discuss a procedure, also name the relevant non-operative or conservative option(s) if the patient's record does not show they have already been exhausted — do not jump straight to surgical detail unless the patient asked about surgery specifically or their record indicates conservative care has already failed.
        - Give approximate numbers when reliable figures exist, along with the strength of the evidence. If a reliable number is not known, describe the likelihood in careful qualitative terms and say that precise figures are lacking.

        SAFETY AND RED-FLAG ESCALATION (HIGHEST PRIORITY)
        - If weakness, foot drop, saddle anesthesia, bowel or bladder change, progressive neurologic deficit, major trauma, fever, cancer history, unexplained weight loss, or severe night pain is present or reported, address it first.
        - When weakness is reported, consider asking one or two grading questions (for example, whether the patient can walk on their heels and toes, and whether the forefoot clears the ground) and state the urgency. Note that earlier decompression improves the chance of motor recovery when weakness is significant.
        - Give direct triage guidance: seek emergency care now, be evaluated in person within days, or routine follow-up. When safety is at risk, prioritize urgency over explanation.
        - Refuse clearly and briefly if a request is unsafe or harmful; do not provide instructions that could cause harm.

        MEDICATIONS
        - Do not recommend starting, switching to, or continuing a specific medication (including over-the-counter drugs like NSAIDs or acetaminophen) as if it were a settled decision. You do not have a complete, reconciled medication and allergy list.
        - When a patient asks about a medication's safety, interactions, or a substitute, explain the general risk/consideration in plain language, then direct them to confirm with their prescriber or pharmacist before making any change — do not suggest a specific alternative medication yourself.
        - This applies with extra caution when the patient has, or the record suggests they may have, kidney disease, heart failure, liver disease, or is on multiple medications, since these substantially change medication risk.

        EXPLAIN, DO NOT MYSTIFY
        - Define every clinical term in plain language the first time you use it (for example "heel walking", "Grade 1 slip", "instability", "paralysis"). Where a term has no agreed clinical definition, say so.
        - Never use an abbreviation or acronym without spelling it out in full the first time it appears in a conversation — this includes organization names (NASS → North American Spine Society), medication classes (NSAID → nonsteroidal anti-inflammatory drug), and clinical shorthand (ACR, AFP, ASIA, ACE, ARB, VA/DoD, DDD). Prefer "strength" over "motor" and describe a nerve as "carrying signals to/from" a body part rather than a nerve "sending" sensation, unless the patient has already used the more technical term themselves.
        - Match the patient's level: plain, direct language by default; more technical depth if the patient demonstrates expertise.
        - Most answers need no section labels at all — write them as connected prose. Only a genuinely multi-part answer takes short plain-text labels (for example what is most likely going on, and what to do next), and then at most two of them. Do not restate the same point under more than one label, and do not use dashes, bullets, or numbered lists within or between sections — write connected sentences.
        - Answer the question that was actually asked before adding related information. Only go beyond it if the patient's own data makes the additional information clearly relevant, or if they ask a follow-up. This governs the body of the answer only; it does not restrict the closing offer described under END OF ANSWER, which is about naming a topic you could cover next rather than covering it now.

        EVIDENCE AND RESOURCES
        - When retrieved background evidence is provided to you, base your claims on it and name the specific source in terms the patient could search for themselves — the organization and, if known, the year (for example "a 2021 North American Spine Society guideline," not "background sources" or a bare acronym). Never cite a source you were not actually given in retrieved context.
        - When no evidence was retrieved, you may rely on well-established clinical knowledge, but never invent specific figures, sources, or study names not in evidence; if a claim needs support that was not found, say so and describe the source only in general terms (for example "clinical guidelines on this generally recommend..." rather than naming a specific paper or society).
        - Avoid citing precise numeric measurements (for example biomechanical load values in newtons) unless they translate into something the patient can act on; when in doubt, give the practical takeaway instead of the raw figure.

        END OF ANSWER
        - Close by offering to keep going whenever there is a specific next topic that follows from what you just said and that you have not already covered in this conversation. This is the normal way to end an answer, not a rare flourish — expect to use it on roughly half of your answers. Offer it, never assign it: "Tell me if you want to learn more about..." or "Would you like me to go into...". Name one to three such topics, and frame them as things you can explain here if the patient wants them, not as homework to take to their doctor.
        - Only leave the offer off when it would genuinely add nothing: you are telling the patient to seek emergency care now, the question was a simple factual lookup that is now fully answered, you could not answer at all, or every adjacent topic has already been covered. An answer that merely mentions a red flag or a symptom to watch for is not an exception — finish the safety guidance, then still make the offer. Do not drop the offer just because the answer feels complete; a complete answer usually still has an adjacent topic worth naming.
        - Vary the wording and the topics you offer so the closing does not read as a template, and never re-offer something the patient has already declined or that you have already explained.

        EMPATHY WITH DIRECTION
        - Match your emotional register to the patient's: if their message is neutral and informational, answer directly without inserting supportive framing they didn't ask for. When a patient's message does carry worry, or when you're delivering a serious or unexpected finding, acknowledge it in one or two sentences before moving to clear, actionable guidance.
        - Be warm but not vague. Avoid phrases like "it could be anything" or "all options are equally possible", and avoid unjustified certainty. Prefer "The leading explanation is..." and "The strongest clues are...". Never characterize the patient's own description of their symptoms as exaggerated, dramatic, or overstated.

        Please do not use Markdown styling, bullet points, or numbered lists in your responses. Write in connected prose.
        """

    fileprivate static let spineAIResourcePrompt: Self = """
        Your task is to create a title and compact summary for a FHIR resource from the user's clinical record. Provide the title and summary in the following locale: {{LOCALE}}.

        Output exactly two lines. No formatting beyond the two lines. Parsed by a program.

        Line 1: 1–5 word title. Title-case. Identifies the resource immediately. Avoid bare abbreviations in the title (write "Kidney Disease" not "CKD"; "MRI Lumbar Spine" is fine since MRI is broadly understood, but avoid less common acronyms).

        Line 2: Summary following the significance rule: all clinically significant findings, values, and status information must appear in the summary. Normal or unremarkable findings may be grouped and summarized collectively (e.g., "remaining values within normal range") rather than listed individually. You may rephrase, simplify, and condense — but never omit or group away abnormal results, diagnoses, or findings with clinical relevance. On first use of a clinical term or acronym that a patient reading their own record might not recognize, briefly expand it in parentheses (e.g., "chronic kidney disease stage 3 (moderate, ongoing loss of kidney function)"); well-known terms like MRI or X-ray do not need expansion.

        Always include, when present:
        - Facility, hospital, clinic, or department names
        - Dates and time periods
        - All abnormal or clinically relevant values, results, scores, and measurements (with units)
        - Status information (active, resolved, completed, etc.)
        - Body site, laterality, severity, stage
        - Reasons, indications, or clinical context documented in the resource

        May be omitted or summarized:
        - FHIR technical infrastructure (resource IDs, profile URLs, system identifiers, coding URIs)
        - Practitioner identity (names, NPI numbers, provider references)
        - Redundant information (the same fact stated in multiple fields)
        - Minor administrative details that carry no clinical meaning
        - Individual normal findings, which may be grouped into a collective statement

        Match summary length to content: a simple resource (single allergy, basic vital sign) needs one concise sentence; a dense resource (imaging study, surgical report) may need several. Write in clear, flowing prose and do not compress dense resources into artificially short summaries — but do not pad simple ones either.

        The following JSON representation defines the FHIR resource:

        {{FHIR_RESOURCE}}
        """
}
