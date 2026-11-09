#!/usr/bin/env python3
#
# This source file is part of the Plainly iOS open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University
#
# SPDX-License-Identifier: MIT
#
"""Lists study reports whose task surveys were skipped by the Next Task bug.

Every build up to Plainly-iOS#47 let a participant close a task's questionnaire and tap Next Task, which moved on to
the next task without any answers and, past the last task, uploaded the report without them. A skipped task leaves no
`surveyTask` event in the report's timeline, so a report misses answers when a task that has questions has no event.

Which tasks have questions depends on the study and on the build: study definitions changed many times. The file
`find_skipped_surveys.definitions.json` next to this script holds every study definition that shipped in a deployed
build (TestFlight staging or production), read from the Swift sources at each deployed commit. Each report is matched
to the definitions that fit it: same task ids, same question texts where the source spells them out, and deployed no
later than the report started. When those disagree about what is missing, the report is listed as AMBIGUOUS with the
most likely reading (the newest build deployed before the session) and every alternative.

Usage:
    python3 find_skipped_surveys.py <folder with reports> [--csv out.csv] [--all]
    python3 find_skipped_surveys.py --refresh-definitions <Plainly-iOS checkout>   # needs git and gh

Reports are found recursively (`*.json`), e.g. in the folder `scripts/download-study-uploads.sh` downloads into.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


DEFINITIONS_FILE = Path(__file__).with_name("find_skipped_surveys.definitions.json")

# A question whose text the source does not spell out as a plain literal (an instruction, an interpolated string, a
# question built in a loop) matches any text; `None` stands for it. A task whose question list is not a literal at
# all is stored with `None` instead of a list, and then only its id is compared.
Questions = Optional[list]


# MARK: - Reading reports

@dataclass
class Report:
    path: Path
    study_id: str
    participant: str
    app_version: str
    reports_app: bool
    started: Optional[datetime]
    conversation_events: int
    answered: dict
    status: str = ""
    missing: list = field(default_factory=list)
    matched: str = ""
    note: str = ""


def parse_date(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def load_report(path: Path) -> Optional[Report]:
    try:
        with path.open(encoding="utf-8") as file:
            data = json.load(file)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    metadata, timeline = data.get("metadata"), data.get("timeline")
    if not isinstance(metadata, dict) or not isinstance(timeline, list) or "studyID" not in metadata:
        return None
    answered = {}
    conversation_events = 0
    for event in timeline:
        if not isinstance(event, dict):
            continue
        payload = event.get("data") or {}
        if event.get("type") == "surveyTask":
            questions = payload.get("questions") or []
            answered[str(payload.get("taskId"))] = [str(q.get("questionText", "")) for q in questions]
        elif event.get("type") in ("chatMessage", "voiceTurn"):
            conversation_events += 1
    app = metadata.get("app") if isinstance(metadata.get("app"), dict) else {}
    user_info = metadata.get("userInfo") if isinstance(metadata.get("userInfo"), dict) else {}
    return Report(
        path=path,
        study_id=str(metadata.get("studyID")),
        participant=str(user_info.get("pid", "")).strip(),
        app_version=" ".join(v for v in (app.get("version"), app.get("build") and f"({app['build']})") if v),
        reports_app="app" in metadata,
        started=parse_date(metadata.get("startTime")),
        conversation_events=conversation_events,
        answered=answered,
    )


# MARK: - Matching reports to the study definitions that shipped

def task_order(task_id: str) -> tuple:
    return (0, int(task_id), "") if task_id.isdigit() else (1, 0, task_id)


def fits(tasks: list, answered: dict, compare_texts: bool = True) -> bool:
    """Whether every survey the report contains is one of the definition's tasks, asking the same questions."""
    known = {task_id: questions for task_id, questions in tasks}
    for task_id, texts in answered.items():
        if task_id not in known:
            return False
        questions = known[task_id]
        if questions is None or not compare_texts:
            continue
        if len(questions) != len(texts):
            return False
        if any(expected is not None and expected.strip() != text.strip() for expected, text in zip(questions, texts)):
            return False
    return True


def describe(definition: dict) -> str:
    return f"{definition['commits'][0][:8]} (deployed {definition['firstDeployed'][:10]})"


def classify_against_definitions(report: Report, definitions: list) -> bool:
    """Decides the report from the shipped study definitions; `False` when none of them fits it."""
    notes = []
    applicable = [d for d in definitions if report.study_id in d["studies"]]
    fitting = [d for d in applicable if fits(d["studies"][report.study_id], report.answered)]
    if not fitting:
        # Question texts are read from the Swift sources; should one be read wrong, the task ids still decide.
        fitting = [d for d in applicable if fits(d["studies"][report.study_id], report.answered, compare_texts=False)]
        if not fitting:
            return False
        notes.append("matched by task ids only: its question texts differ from every shipped build's")
    candidates = fitting
    # Builds from some point on record their version in the report, so whether it has one tells which side its build was on.
    same_kind = [d for d in candidates if d["reportsApp"] == report.reports_app]
    if same_kind:
        candidates = same_kind
    if report.started is not None:
        # A build cannot produce a session that started before the build was deployed.
        deployed_before = [d for d in candidates if parse_date(d["firstDeployed"]) <= report.started]
        if deployed_before:
            candidates = deployed_before
        else:
            notes.append("started before any fitting build was deployed; device clock?")

    readings = {}
    for definition in candidates:
        tasks = definition["studies"][report.study_id]
        missing = tuple(task_id for task_id, _ in tasks if task_id not in report.answered)
        readings.setdefault(missing, []).append(definition)

    if len(readings) == 1:
        report.missing = list(next(iter(readings)))
        report.status = "MISSING" if report.missing else "OK"
        newest = max(candidates, key=lambda d: d["firstDeployed"])
        report.matched = f"{len(candidates)} build definition(s), newest {describe(newest)}"
    else:
        # Participants' builds update on their own, so the newest build before the session is the likely one.
        likely = max(candidates, key=lambda d: d["firstDeployed"])
        likely_missing = next(m for m, ds in readings.items() if likely in ds)
        report.status = "AMBIGUOUS"
        report.missing = list(likely_missing)
        report.matched = f"likely {describe(likely)}"
        alternatives = [
            f"[{', '.join(missing) or 'nothing'}] per {', '.join(describe(d) for d in ds)}"
            for missing, ds in readings.items() if missing != likely_missing
        ]
        notes.append(
            f"builds disagree; shown is the newest build before the session, {describe(likely)}; "
            "otherwise missing " + "; or ".join(alternatives)
        )
    report.note = "; ".join(notes)
    return True


def classify_by_peers(unmatched: list) -> None:
    """Compares reports that fit no shipped definition with the other such reports of their study.

    Reports whose shared tasks ask the same questions came from the same definition, so a task one of them answered
    is a task the others had too. A task nobody in the group answered cannot be seen this way.
    """
    by_study = {}
    for report in unmatched:
        by_study.setdefault(report.study_id, []).append(report)
    for reports in by_study.values():
        groups, members = [], []
        for report in sorted(reports, key=lambda r: len(r.answered), reverse=True):
            for index, group in enumerate(groups):
                if all(group.get(task_id, texts) == texts for task_id, texts in report.answered.items()):
                    group.update(report.answered)
                    members[index].append(report)
                    break
            else:
                groups.append(dict(report.answered))
                members.append([report])
        for group, group_reports in zip(groups, members):
            for report in group_reports:
                report.missing = sorted((t for t in group if t not in report.answered), key=task_order)
                report.status = "MISSING" if report.missing else "UNVERIFIED"
                report.matched = f"compared with {len(group_reports) - 1} other report(s)"
                report.note = "fits no shipped definition; a task nobody in this group answered cannot be seen"


def classify(reports: list, definitions: list) -> None:
    unmatched = []
    for report in reports:
        if report.conversation_events == 0 and not report.answered:
            # A screening stop reports the intake questionnaire alone, before any chat: not this bug.
            report.status = "NO-SESSION"
            report.note = "no chat and no surveys, e.g. stopped by screening"
        elif not classify_against_definitions(report, definitions):
            unmatched.append(report)
    classify_by_peers(unmatched)


def check(folder: Path, csv_path: Optional[Path], show_all: bool) -> int:
    if not DEFINITIONS_FILE.exists():
        sys.exit(f"{DEFINITIONS_FILE.name} is missing; it has to sit next to this script.")
    definitions = json.loads(DEFINITIONS_FILE.read_text(encoding="utf-8"))["definitions"]

    reports, skipped = [], 0
    for path in sorted(folder.rglob("*.json")):
        report = load_report(path)
        if report:
            reports.append(report)
        else:
            skipped += 1
    classify(reports, definitions)

    columns = ["status", "study", "participant", "app", "started", "missing_tasks", "matched", "note", "file"]
    rows = [
        {
            "status": r.status,
            "study": r.study_id,
            "participant": r.participant,
            "app": r.app_version or "?",
            "started": r.started.isoformat() if r.started else "",
            "missing_tasks": " ".join(r.missing),
            "matched": r.matched,
            "note": r.note,
            "file": str(r.path.relative_to(folder)),
        }
        for r in reports
    ]
    if csv_path:
        with csv_path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=columns)
            writer.writeheader()
            writer.writerows(rows)

    attention = {"MISSING", "AMBIGUOUS"}
    shown = rows if show_all else [row for row in rows if row["status"] in attention]
    if shown:
        printed = ["status", "study", "participant", "app", "missing_tasks", "file"]
        widths = {c: max(len(c), *(len(row[c]) for row in shown)) for c in printed}
        print("  ".join(c.upper().ljust(widths[c]) for c in printed))
        for row in shown:
            print("  ".join(row[c].ljust(widths[c]) for c in printed).rstrip())
            if row["note"]:
                print(f"    note: {row['note']}")
        print()

    counts = {}
    for r in reports:
        counts.setdefault(r.study_id, {}).setdefault(r.status, 0)
        counts[r.study_id][r.status] += 1
    print(f"{len(reports)} report(s) read" + (f", {skipped} other JSON file(s) skipped" if skipped else ""))
    for study, by_status in sorted(counts.items()):
        print(f"  {study}: " + ", ".join(f"{count} {status}" for status, count in sorted(by_status.items())))
    affected = sum(1 for r in reports if r.status in attention)
    print(f"{affected} report(s) missing survey answers" + (f"; every report is in {csv_path}" if csv_path else ""))
    return 0


# MARK: - Refreshing the shipped definitions from the Swift sources

STRING = re.compile(r'#*"""|#*"')


def skip_string(src: str, i: int) -> int:
    """Returns the index just past the string literal that starts at `i`."""
    match = STRING.match(src, i)
    hashes = match.group(0).count("#")
    delimiter = '"""' if match.group(0).endswith('"""') else '"'
    end = delimiter + "#" * hashes
    j = match.end()
    while j < len(src):
        if hashes == 0 and src[j] == "\\":
            j += 2
            continue
        if src.startswith(end, j):
            return j + len(end)
        j += 1
    return j


def skip_trivia(src: str, i: int) -> int:
    while i < len(src):
        if src[i].isspace():
            i += 1
        elif src.startswith("//", i):
            i = src.find("\n", i) if "\n" in src[i:] else len(src)
        elif src.startswith("/*", i):
            i = src.find("*/", i) + 2 if "*/" in src[i:] else len(src)
        else:
            break
    return i


def matching(src: str, i: int) -> int:
    """Given an opening bracket at `i`, returns the index of its closing bracket, skipping strings and comments."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = []
    j = i
    while j < len(src):
        if src.startswith("//", j) or src.startswith("/*", j):
            j = skip_trivia(src, j)
            continue
        if STRING.match(src, j):
            j = skip_string(src, j)
            continue
        char = src[j]
        if char in pairs:
            stack.append(pairs[char])
        elif stack and char == stack[-1]:
            stack.pop()
            if not stack:
                return j
        j += 1
    return len(src) - 1


def split_top_level(src: str, separator: str = ",") -> list:
    """Splits the inside of a bracket into its comma-separated parts (or parts joined by another separator)."""
    parts, start, j = [], 0, 0
    while j < len(src):
        if src.startswith("//", j) or src.startswith("/*", j):
            j = skip_trivia(src, j)
            continue
        if STRING.match(src, j):
            j = skip_string(src, j)
            continue
        if src[j] in "([{":
            j = matching(src, j) + 1
            continue
        if src[j] == separator:
            parts.append(src[start:j])
            start = j + 1
        j += 1
    parts.append(src[start:])
    return [strip_comments(part).strip() for part in parts if strip_comments(part).strip()]


def strip_comments(src: str) -> str:
    out, j = [], 0
    while j < len(src):
        if src.startswith("//", j) or src.startswith("/*", j):
            j = skip_trivia(src, j)
            out.append(" ")
            continue
        if STRING.match(src, j):
            end = skip_string(src, j)
            out.append(src[j:end])
            j = end
            continue
        out.append(src[j])
        j += 1
    return "".join(out)


def literal(src: str) -> Optional[str]:
    """The value of a plain single-line string literal, or `None` for anything else."""
    src = src.strip()
    if not (len(src) >= 2 and src[0] == '"' and src[-1] == '"' and not src.startswith('"""')):
        return None
    body = src[1:-1]
    if "\\(" in body:
        return None
    escapes = {'"': '"', "\\": "\\", "n": "\n", "t": "\t", "r": "\r", "0": "\0", "'": "'"}
    out, j = [], 0
    while j < len(body):
        if body[j] == "\\" and j + 1 < len(body):
            if body[j + 1] == "u" and body[j + 2:j + 3] == "{":
                close = body.index("}", j)
                out.append(chr(int(body[j + 3:close], 16)))
                j = close + 1
                continue
            out.append(escapes.get(body[j + 1], body[j + 1]))
            j += 2
            continue
        out.append(body[j])
        j += 1
    return "".join(out)


def call_arguments(expression: str) -> Optional[tuple]:
    """Splits `name(arguments)` into the name and its arguments, or `None` if the expression is not one call."""
    expression = expression.strip()
    open_index = expression.find("(")
    if open_index <= 0 or not re.fullmatch(r"[\w.]+", expression[:open_index].strip()):
        return None
    close = matching(expression, open_index)
    if expression[close + 1:].strip():
        return None
    return expression[:open_index].strip(), split_top_level(expression[open_index + 1:close])


def labeled(arguments: list, label: str) -> Optional[str]:
    for argument in arguments:
        match = re.match(rf"{label}\s*:(?!:)", argument)
        if match:
            return argument[match.end():].strip()
    return None


def bindings(src: str) -> dict:
    """`let name = value` and `let name: Type = value` in the file; a name bound twice is left unresolved."""
    found = {}
    for match in re.finditer(r"\blet\s+(\w+)\s*(?::[^=\n]+)?=\s*", src):
        start = skip_trivia(src, match.end())
        end = start
        while end < len(src) and (src[end].isalnum() or src[end] in "._"):
            end += 1
        end = skip_trivia(src, end)
        if end < len(src) and src[end] in "([":
            end = matching(src, end) + 1
        else:
            continue
        name = match.group(1)
        found[name] = None if name in found else src[start:end]
    return found


def question_text(expression: str, scope: dict, depth: int = 0) -> Optional[str]:
    """The text a report writes for a question, if the source spells it out; `None` matches any text."""
    expression = expression.strip()
    if re.fullmatch(r"\w+", expression) and scope.get(expression) and depth < 5:
        return question_text(scope[expression], scope, depth + 1)
    call = call_arguments(expression)
    if call is None:
        return None
    name, arguments = call
    if name.endswith("instructional"):
        return None  # Releases up to 1.0.3 wrote its (empty) title, later ones its text.
    for label in ("text", "title"):
        value = labeled(arguments, label)
        if value is not None:
            return literal(value)
    unlabeled = [a for a in arguments if not re.match(r"\w+\s*:(?!:)", a)]
    return literal(unlabeled[0]) if unlabeled else None


def question_list(expression: str, scope: dict, depth: int = 0) -> Questions:
    """The texts of a task's questions, `[]` for none, or `None` when the source does not list them."""
    expression = expression.strip()
    if re.fullmatch(r"\w+", expression):
        bound = scope.get(expression)
        return question_list(bound, scope, depth + 1) if bound and depth < 5 else None
    operands = split_top_level(expression, separator="+")
    if len(operands) > 1:
        lists = [question_list(operand, scope, depth + 1) for operand in operands]
        return None if any(texts is None for texts in lists) else [text for texts in lists for text in texts]
    if not (expression.startswith("[") and matching(expression, 0) == len(expression) - 1):
        return None
    elements = split_top_level(expression[1:-1])
    texts = []
    for element in elements:
        if re.fullmatch(r"\w+", element) and scope.get(element) and scope[element].lstrip().startswith("["):
            nested = question_list(element, scope, depth + 1)
            if nested is None:
                return None
            texts.extend(nested)
        else:
            texts.append(question_text(element, scope))
    return texts


def studies_in(src: str) -> dict:
    """Every study defined in one Swift file: its id, and for each task with questions, those questions."""
    scope = bindings(src)
    studies = {}
    for match in re.finditer(r"(?<![\w.])Study\s*\(", src):
        open_index = src.index("(", match.start())
        arguments = split_top_level(src[open_index + 1:matching(src, open_index)])
        study_id = literal(labeled(arguments, "id") or "")
        tasks_expression = labeled(arguments, "tasks")
        if not study_id or tasks_expression is None:
            continue
        if re.fullmatch(r"\w+", tasks_expression) and scope.get(tasks_expression):
            tasks_expression = scope[tasks_expression]
        if not tasks_expression.startswith("["):
            raise ValueError(f"tasks of {study_id} are not a literal list")
        tasks = []
        for element in split_top_level(tasks_expression.strip()[1:-1]):
            call = call_arguments(element)
            task_id = literal(labeled(call[1], "id") or "") if call else None
            questions_expression = labeled(call[1], "questions") if call else None
            if task_id is None or questions_expression is None:
                raise ValueError(f"unreadable task in {study_id}: {element[:80]}")
            questions = question_list(questions_expression, scope)
            if questions != []:
                tasks.append([task_id, questions])
        studies[study_id] = tasks
    return studies


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True).stdout


def deployed_commits(repository: str) -> dict:
    """Every commit a successful deployment or release run built, with when it was first deployed."""
    commits = {}
    for workflow in ("deployment.yml", "release.yml"):
        output = subprocess.run(
            ["gh", "run", "list", "--repo", repository, "--workflow", workflow, "--limit", "1000",
             "--json", "headSha,conclusion,createdAt", "--jq", '.[] | select(.conclusion=="success") | "\\(.createdAt) \\(.headSha)"'],
            check=True, capture_output=True, text=True,
        ).stdout
        for line in output.splitlines():
            created, sha = line.split()
            commits[sha] = min(commits.get(sha, created), created)
    return commits


def refresh_definitions(repo: Path, repository: str) -> int:
    commits = deployed_commits(repository)
    definitions = {}
    for sha, deployed in sorted(commits.items(), key=lambda item: item[1]):
        if subprocess.run(["git", "-C", str(repo), "cat-file", "-e", sha], capture_output=True).returncode != 0:
            git(repo, "fetch", "--quiet", "origin", sha)
        files = [f for f in git(repo, "ls-tree", "-r", "--name-only", sha).splitlines()
                 if re.search(r"StudyDefinitions/[^/]+\.swift$", f)]
        studies = {}
        for file in files:
            studies.update(studies_in(git(repo, "show", f"{sha}:{file}")))
        report_files = [f for f in git(repo, "ls-tree", "-r", "--name-only", sha).splitlines() if f.endswith("/StudyReport.swift")]
        reports_app = any(re.search(r"\blet app\s*:", git(repo, "show", f"{sha}:{f}")) for f in report_files)
        key = json.dumps([studies, reports_app], sort_keys=True)
        entry = definitions.setdefault(
            key, {"commits": [], "firstDeployed": deployed, "reportsApp": reports_app, "studies": studies}
        )
        entry["commits"].append(sha)
    output = {
        "repository": repository,
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "deployedCommits": len(commits),
        "definitions": sorted(definitions.values(), key=lambda d: d["firstDeployed"]),
    }
    DEFINITIONS_FILE.write_text(json.dumps(output, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(commits)} deployed commit(s), {len(definitions)} distinct definition(s) written to {DEFINITIONS_FILE}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("folder", type=Path, nargs="?", help="folder with study report JSON files, searched recursively")
    parser.add_argument("--csv", type=Path, help="also write every report's result to this CSV file")
    parser.add_argument("--all", action="store_true", help="list every report, not only those missing answers")
    parser.add_argument("--refresh-definitions", type=Path, metavar="CHECKOUT",
                        help="re-read the shipped study definitions from this Plainly-iOS checkout (needs git and gh)")
    parser.add_argument("--repository", default="SchmiedmayerLab/Plainly-iOS", help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.refresh_definitions:
        return refresh_definitions(args.refresh_definitions, args.repository)
    if args.folder is None or not args.folder.is_dir():
        parser.error("pass a folder that contains study reports")
    return check(args.folder, args.csv, args.all)


if __name__ == "__main__":
    sys.exit(main())
