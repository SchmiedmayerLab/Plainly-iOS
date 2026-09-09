#!/bin/bash
#
# This source file is part of the Plainly iOS open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University
#
# SPDX-License-Identifier: MIT
#
# Pulls a study's reports out of the production bucket into <destination>/<study>/, flat, named the way
# the app names them today. Reports from older builds sit under users/<uid>/<uuid>.json in the bucket;
# those are renamed from their content and the bucket's upload time. RAG files are left alone.
# Usage: download-study-uploads.sh --study <id>|all [--destination <dir>]
set -euo pipefail

study=""
destination="./study-uploads"
while [ $# -gt 0 ]; do
  case "$1" in
    --study) study="$2"; shift 2;;
    --destination) destination="$2"; shift 2;;
    *) echo "usage: $(basename "$0") --study <id>|all [--destination <dir>]" >&2; exit 1;;
  esac
done
if [ -z "$study" ]; then
  echo "usage: $(basename "$0") --study <id>|all [--destination <dir>]" >&2
  exit 1
fi
bucket="gs://som-rit-phi-lit-ai-prod.firebasestorage.app"

if [ -z "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" ]; then
  gcloud auth login
fi

if [ "$study" = "all" ]; then
  studies=$(gcloud storage ls "$bucket/studies/" | sed -E 's#.*/studies/([^/]+)/?$#\1#')
else
  studies="$study"
fi

for id in $studies; do
  target="$destination/$id"
  mkdir -p "$target"
  listing="$(mktemp)"
  gcloud storage ls --json --recursive "$bucket/studies/$id/" > "$listing"
  python3 - "$id" "$target" "$listing" "$bucket" <<'EOF'
import json, os, shutil, subprocess, sys, tempfile
from datetime import datetime, timezone

study, target, listing, BUCKET = sys.argv[1:5]
allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")


def component(value):
    return "".join(c if c in allowed else "".join(f"%{b:02X}" for b in c.encode()) for c in value)


def stamp(iso):
    moment = datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(timezone.utc)
    return moment.strftime("%Y-%m-%dT%H-%M-%S.") + f"{moment.microsecond // 1000:03d}Z"


def current_name(relative, path, created):
    """Reports already named by the app keep their name; older ones get the app's current naming."""
    if not relative.startswith("users/"):
        return os.path.basename(relative)
    with open(path) as file:
        report = json.load(file)
    parts = [component(study)]
    pid = (report.get("metadata", {}).get("userInfo") or {}).get("pid", "").strip()
    if pid:
        parts.append("pid-" + component(pid))
    uploaded = created
    if uploaded is None:
        timestamps = [event.get("data", {}).get("timestamp") for event in report.get("timeline", [])]
        uploaded = max(t for t in timestamps if t) if any(timestamps) else None
    parts.append(stamp(uploaded) if uploaded else "unknown-time")
    parts.append(os.path.basename(relative)[:8].lower())
    return "_".join(parts) + ".json"


prefix = f"studies/{study}/"
entries = json.load(open(listing))
wanted = []
skipped = []
for entry in entries:
    metadata = entry.get("metadata") or {}
    # The object's name inside the bucket; the URL form carries a "#generation" suffix.
    name = metadata.get("name") or entry.get("url", "").split("/", 3)[-1].split("#", 1)[0]
    if not name.startswith(prefix) or name.endswith("/"):
        continue
    relative = name[len(prefix):]
    if relative.startswith("rag_files/"):
        continue
    if not relative.endswith(".json"):
        skipped.append(relative)
        continue
    url = f"{BUCKET}/{name}"
    wanted.append((url, relative, metadata.get("timeCreated"), metadata.get("md5Hash") or metadata.get("crc32c") or ""))
if skipped:
    print(f"{study}: left {len(skipped)} objects alone that are neither reports nor RAG files, for example:", file=sys.stderr)
    for relative in skipped[:8]:
        print(f"    {relative}", file=sys.stderr)

# .downloads remembers each object's hash from the bucket listing, so a report is fetched once and
# again only if the bucket holds a different version of it.
ledger_path = os.path.join(target, ".downloads")
ledger = json.load(open(ledger_path)) if os.path.exists(ledger_path) else {}
pending = [
    (url, relative, created, digest) for url, relative, created, digest in wanted
    if ledger.get(relative, {}).get("hash") != digest or not os.path.exists(os.path.join(target, ledger[relative]["file"]))
]
print(f"{study}: {len(wanted)} reports in the bucket, {len(pending)} to fetch", flush=True)
with tempfile.TemporaryDirectory() as scratch:
    for index, (url, relative, created, digest) in enumerate(pending, 1):
        local = os.path.join(scratch, relative.replace("/", "__"))
        subprocess.run(["gcloud", "storage", "cp", "--no-user-output-enabled", url, local], check=True)
        name = current_name(relative, local, created)
        shutil.move(local, os.path.join(target, name))
        ledger[relative] = {"hash": digest, "file": name}
        with open(ledger_path, "w") as file:
            json.dump(ledger, file, indent=2, sort_keys=True)
        print(f"  [{index}/{len(pending)}] {name}", flush=True)
print(f"{study}: {len([f for f in os.listdir(target) if f.endswith('.json')])} reports in {target}")
EOF
  rm -f "$listing"
done
