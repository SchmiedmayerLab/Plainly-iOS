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

`sources` is copied from the answer's `citations` in the StudyReport, so the export can be read
on its own without joining it back. Each entry has a `title` plus at most one of `url` (a page
on the web) or `file` (a document the model was given); an entry carries neither when the
report gave an address the reviewer's copy would not link to. The array is empty for an answer
with no sources, and for any report exported before reports carried them (`schemaVersion: 1`).

Each conversation's display title is the session's free-form **`comment`** (propagated to
`metadata.userInfo.comment` in the StudyReport). When no comment is present, the title
falls back to the patient bundle name.
