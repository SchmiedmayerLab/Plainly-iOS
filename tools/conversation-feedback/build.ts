#!/usr/bin/env -S npx tsx
//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

/**
 * build.ts — bake a folder of Plainly StudyReport JSON exports into a single,
 * self-contained HTML feedback file that reviewers can open and fill out offline.
 *
 * Usage:
 *   npx tsx build.ts <dir-or-file...> [-o output.html] [-t template.html]
 *
 * Examples:
 *   npx tsx build.ts ../../.run/output/2026-04-14T164536.759Z -o reviewer.html
 *   npx tsx build.ts a.json b.json c.json -o batch.html
 *
 * The script itself imports no third-party npm packages — Node built-ins only —
 * though running it requires the `tsx` dev dependency (see package.json) to execute
 * TypeScript directly. The generated file also accepts drag-and-drop / file-picker
 * loading, so parsing lives in the browser; this script only embeds the raw reports.
 */

import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname, basename, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";

const here = dirname(fileURLToPath(import.meta.url));

interface Args {
  inputs: string[];
  output: string;
  template: string;
}

function parseArgs(argv: string[]): Args {
  const inputs: string[] = [];
  let output = "conversation-feedback.html";
  let template = join(here, "template.html");
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "-o" || a === "--output") {
      if (i + 1 >= argv.length) {
        console.error("Error: -o/--output requires a path.");
        printUsageAndExit(1);
      }
      output = argv[++i];
    } else if (a === "-t" || a === "--template") {
      if (i + 1 >= argv.length) {
        console.error("Error: -t/--template requires a path.");
        printUsageAndExit(1);
      }
      template = argv[++i];
    } else if (a === "-h" || a === "--help") {
      printUsageAndExit(0);
    } else if (a.startsWith("-")) {
      console.error(`Unknown option: ${a}`);
      printUsageAndExit(1);
    } else {
      inputs.push(a);
    }
  }
  if (!inputs.length) {
    console.error("Error: no input files or directories given.\n");
    printUsageAndExit(1);
  }
  if (!output) {
    console.error("Error: -o/--output requires a path.");
    process.exit(1);
  }
  return { inputs, output, template };
}

function printUsageAndExit(code: number): never {
  console.log(
    [
      "Usage: npx tsx build.ts <dir-or-file...> [-o output.html] [-t template.html]",
      "",
      "  <dir-or-file...>  One or more StudyReport .json files, or directories",
      "                    containing them (searched non-recursively).",
      "  -o, --output      Output HTML path (default: conversation-feedback.html).",
      "  -t, --template    Template HTML path (default: ./template.html).",
    ].join("\n"),
  );
  process.exit(code);
}

/** Collect .json files from the given paths (files used directly; dirs listed one level deep). */
function collectJsonFiles(inputs: string[]): string[] {
  const files: string[] = [];
  for (const input of inputs) {
    const p = resolve(input);
    let st;
    try {
      st = statSync(p);
    } catch {
      console.error(`Warning: skipping missing path: ${input}`);
      continue;
    }
    if (st.isDirectory()) {
      const entries = readdirSync(p)
        .filter((name: string) => extname(name).toLowerCase() === ".json")
        .sort();
      for (const name of entries) files.push(join(p, name));
    } else if (extname(p).toLowerCase() === ".json") {
      files.push(p);
    } else {
      console.error(`Warning: skipping non-JSON file: ${input}`);
    }
  }
  return files;
}

interface EmbeddedConversation {
  id: string;
  report: unknown;
}

function looksLikeStudyReport(json: unknown): boolean {
  return (
    typeof json === "object" &&
    json !== null &&
    Array.isArray((json as { timeline?: unknown }).timeline)
  );
}

function main(): void {
  const { inputs, output, template } = parseArgs(process.argv.slice(2));

  const files = collectJsonFiles(inputs);
  if (!files.length) {
    console.error("Error: no .json files found in the given inputs.");
    process.exit(1);
  }

  let templateHtml: string;
  try {
    templateHtml = readFileSync(template, "utf8");
  } catch (e) {
    console.error(`Error: could not read template at ${template}: ${(e as Error).message}`);
    process.exit(1);
  }

  const placeholder = /<script id="conversations-data" type="application\/json">[\s\S]*?<\/script>/;
  if (!placeholder.test(templateHtml)) {
    console.error('Error: template is missing the <script id="conversations-data"> placeholder.');
    process.exit(1);
  }

  const conversations: EmbeddedConversation[] = [];
  const seen = new Set<string>();
  for (const file of files) {
    let report: unknown;
    try {
      report = JSON.parse(readFileSync(file, "utf8"));
    } catch (e) {
      console.error(`Warning: skipping ${basename(file)} (invalid JSON: ${(e as Error).message})`);
      continue;
    }
    if (!looksLikeStudyReport(report)) {
      console.error(`Warning: skipping ${basename(file)} (does not look like a StudyReport — no timeline[]).`);
      continue;
    }
    let id = basename(file, extname(file));
    if (seen.has(id)) {
      let n = 2;
      while (seen.has(`${id}-${n}`)) n++;
      id = `${id}-${n}`;
    }
    seen.add(id);
    conversations.push({ id, report });
  }

  if (!conversations.length) {
    console.error("Error: no valid StudyReport conversations to embed.");
    process.exit(1);
  }

  // Escape "</script" so the embedded JSON can't terminate the host <script> tag.
  const dataJson = JSON.stringify(conversations).replace(/<\/(script)/gi, "<\\/$1");
  const block = `<script id="conversations-data" type="application/json">${dataJson}</script>`;
  const html = templateHtml.replace(placeholder, block);

  const outPath = resolve(output);
  writeFileSync(outPath, html, "utf8");

  const sizeKb = (Buffer.byteLength(html, "utf8") / 1024).toFixed(0);
  console.log(`Embedded ${conversations.length} conversation(s) → ${outPath} (${sizeKb} KB)`);
  console.log(`Conversations: ${conversations.map((c) => c.id).join(", ")}`);
}

main();
