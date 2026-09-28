<!--

This source file is part of the Plainly iOS open-source project

SPDX-FileCopyrightText: 2026 Stanford University

SPDX-License-Identifier: MIT

-->

# Conversation Feedback tool

A replacement for the multi-sheet Excel review workbooks. It produces **one
self-contained HTML file** that a reviewer opens in any browser, fills out inline, and
exports as a JSON file we can read programmatically.

- Works fully offline — no server, no network requests, no installs for the reviewer.
- Feedback fields mirror the old Excel columns exactly (satisfaction + what was good / bad
  / resources / further comments), plus **inline notes**: reviewers can highlight any span
  of an answer and attach a comment (like the ALL-CAPS notes they used to type into cells).
- Each answer also shows its **sources** — the documents the model drew on, as the app shows
  them to the participant — in a collapsed `Sources — N` block under the answer.
- Autosaves continuously to the browser and can Export / Import JSON to resume.

## Files

| File            | Purpose                                                                 |
| --------------- | ----------------------------------------------------------------------- |
| `template.html` | The review app (all CSS/JS inline). Ships with an empty data block.     |
| `clinician-template.html` | The clinician evaluation variant (see [Clinician evaluation](#clinician-evaluation)). |
| `build.ts`      | Generator that bakes conversations into a ready-to-send copy of the app.|

## Generating a file to send

Input is the Plainly **`StudyReport`** export format — the `NN-session-1.json` files
under `PlainlyShared/.run/output/<timestamp>/`.

```bash
# from tools/conversation-feedback, after `npm install`
npx tsx build.ts \
  /path/to/PlainlyShared/.run/output/2026-04-14T164536.759Z \
  -o reviewer.html
```

- Pass a **directory** (its `.json` files are embedded, non-recursively) and/or individual
  `.json` files.
- `-o` sets the output path (default `conversation-feedback.html`).
- `-t` overrides the template path (default `./template.html`).
- `--clinician` uses the clinician evaluation template instead of the feedback form.
- `--scope answer|conversation` picks, for either template, whether the reviewer fills the form in
  for every answer (default) or once per conversation, below its last answer. Answers keep their
  inline notes in both scopes.

| Version                           | Flags                                  |
| --------------------------------- | -------------------------------------- |
| Feedback form, per answer         | (none)                                 |
| Feedback form, per conversation   | `--scope conversation`                 |
| Clinician evaluation, per answer  | `--clinician`                          |
| Clinician evaluation, per conversation | `--clinician --scope conversation` |

To build the file straight from the reports participants uploaded to a study, use
`scripts/build-feedback-from-uploads.sh <study id>|all -o reviewer.html` from the repository root.
It downloads the reports, keeps those picked by `--since <YYYY-MM-DD>` and `--latest <n>`, and
passes `--clinician` and `--scope` through.

Then email `reviewer.html` to the reviewer. They open it, fill it in, click **Export
JSON**, and send the JSON back.

## Reviewer workflow

1. Open the HTML file (double-click; any modern browser).
2. Enter name + email at the top.
3. For each answer: pick a satisfaction level and fill in the text fields. To comment on a
   specific passage, **select text in the answer** and add an inline note. Open **Sources**
   under an answer to see the documents it drew on; web sources open in a new tab.
4. Click **Export JSON** to download the results.

The reviewer can also **drag additional `StudyReport` JSON files** onto the page, and
**Import** a previous export to resume.

## Persistence & recovery

- Work is **autosaved to the browser's local storage** on every edit and when the tab
  closes, keyed to the set of conversations in the file. Reopening the same file in the
  same browser restores everything automatically.
- Because browser storage for local files can be cleared or isolated per browser/profile,
  reviewers should **Export JSON periodically** as a durable backup. An exported file can
  always be re-loaded with **Import** to continue.

## Export format

```json
{
  "schemaVersion": 2,
  "exportedAt": "2026-07-06T12:00:00.000Z",
  "reviewer": { "name": "...", "email": "..." },
  "conversations": [
    {
      "conversationId": "00-session-1",
      "comment": "Diabetes follow-up scenario",
      "studyID": "edu.stanford.plainly.spineAI",
      "patientBundle": "bundles/Rickie717_Ebert178.json",
      "model": "gpt-5.4",
      "answers": [
        {
          "index": 0,
          "question": "...",
          "answer": "...",
          "sources": [
            { "title": "Lumbar Stenosis Guideline", "file": "stenosis.pdf" },
            { "title": "Spinal Stenosis", "url": "https://www.spine-health.org/stenosis" }
          ],
          "satisfaction": "neutral",
          "whatWasGood": "...",
          "whatWasBad": "...",
          "resourcesToMention": "...",
          "furtherComments": "...",
          "inlineAnnotations": [
            { "quote": "...", "start": 123, "end": 156, "comment": "..." }
          ]
        }
      ]
    }
  ]
}
```

`satisfaction` is one of `very dissatisfied`, `dissatisfied`, `neutral`, `satisfied`,
`very satisfied`, or `null`. Field names map 1:1 to the old Excel columns.

The export also carries `"scope": "answer"` or `"scope": "conversation"`. In the `conversation`
scope, the five fields sit once per conversation under `feedback`, and answers only keep
`inlineAnnotations`. An export without `scope` predates it and is an `answer` export. Each scope
saves to its own browser storage (the `answer` scope keeps the key it always had), and the page
refuses to import an export of the other scope or of the clinician evaluation.

`sources` is copied from the answer's `citations` in the StudyReport, so the export can be read
on its own without joining it back. Each entry has a `title` plus at most one of `url` (a page
on the web) or `file` (a document the model was given); an entry carries neither when the
report gave an address the reviewer's copy would not link to. The array is empty for an answer
with no sources, and for any report exported before reports carried them (`schemaVersion: 1`).

Each conversation's display title is the session's free-form **`comment`** (propagated to
`metadata.userInfo.comment` in the StudyReport). When no comment is present, the title
falls back to the patient bundle name.

## Clinician evaluation

`clinician-template.html` replaces the satisfaction and free-text fields with the rubric of the
clinician evaluation sheet: 14 criteria (scientific consensus, extent and likelihood of harm,
evidence of correct and incorrect comprehension, retrieval and reasoning, inappropriate and missing
content, possibility of bias, capturing the user's intent, helpfulness), each rated on one scale:
`1` Not at all, `2` To a small extent, `3` To a moderate extent, `4` To a large extent,
`5` Extremely. An optional comment and inline notes stay. The criteria live in the `CRITERIA` array
at the top of the template's script.

Like the feedback form, it comes in the `answer` and `conversation` scopes. Each scope saves to its own browser storage, and the page refuses to import an export of the other
scope or of the feedback form. The export carries the form, scope, criteria and scale, and puts each
rubric under `evaluation`: on the conversation in the `conversation` scope, on every answer in the
`answer` scope.

```json
{
  "form": "clinician-evaluation",
  "scope": "answer",
  "schemaVersion": 1,
  "exportedAt": "2026-09-28T12:00:00.000Z",
  "reviewer": { "name": "...", "email": "..." },
  "criteria": [{ "key": "scientificConsensus", "label": "Scientific consensus", "question": "..." }],
  "scale": [{ "value": 1, "label": "Not at all" }],
  "conversations": [
    {
      "conversationId": "...",
      "patient": "Rickie717_Ebert178",
      "pid": "",
      "studyID": "edu.stanford.plainly.spineAI",
      "answers": [
        {
          "index": 0,
          "question": "...",
          "answer": "...",
          "sources": [],
          "evaluation": {
            "ratings": { "scientificConsensus": 4, "extentOfHarm": 1, "helpfulness": null },
            "comment": "...",
            "evaluatedAt": "2026-09-28T11:58:02.000Z"
          },
          "inlineAnnotations": []
        }
      ]
    }
  ]
}
```

`ratings` holds every criterion's key, with `null` for one not rated yet. `evaluatedAt` is when the
rubric was last changed. `patient` is the synthetic patient bundle, or the participant's `pid` for
reports uploaded from the app.
