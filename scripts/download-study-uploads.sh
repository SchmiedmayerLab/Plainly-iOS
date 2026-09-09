#!/bin/bash
#
# This source file is part of the Plainly iOS open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University
#
# SPDX-License-Identifier: MIT
#
# Mirrors a study's uploads out of the production bucket and lays every report out flat the way the
# app names them today. Reports from older builds sit under studies/<study>/users/<uid>/<uuid>.json;
# those are renamed from their content and the bucket's upload time.
# Usage: download-study-uploads.sh <study id> [destination]
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") <study id> [destination]" >&2
  exit 1
fi
study="$1"
destination="${2:-./study-uploads/$study}"
bucket="gs://som-rit-phi-lit-ai-prod.firebasestorage.app"
mirror="$destination/bucket"
reports="$destination/reports"

if [ -z "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" ]; then
  gcloud auth login
fi

mkdir -p "$mirror" "$reports"
gcloud storage rsync --recursive "$bucket/studies/$study" "$mirror"
gcloud storage ls --json --recursive "$bucket/studies/$study/users" > "$destination/upload-times.json" 2>/dev/null || echo '[]' > "$destination/upload-times.json"

python3 - "$study" "$mirror" "$reports" "$destination/upload-times.json" <<'EOF'
import json, os, shutil, sys
from datetime import datetime, timezone

study, mirror, reports, upload_times = sys.argv[1:5]
allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")


def component(value):
    return "".join(c if c in allowed else "".join(f"%{b:02X}" for b in c.encode()) for c in value)


def stamp(iso):
    moment = datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(timezone.utc)
    return moment.strftime("%Y-%m-%dT%H-%M-%S.") + f"{moment.microsecond // 1000:03d}Z"


created = {}
for entry in json.load(open(upload_times)):
    url, metadata = entry.get("url", ""), entry.get("metadata") or {}
    if "timeCreated" in metadata:
        created[url.split("/users/", 1)[-1]] = metadata["timeCreated"]

for name in os.listdir(mirror):
    if name.endswith(".json"):
        shutil.copy2(os.path.join(mirror, name), os.path.join(reports, name))

users = os.path.join(mirror, "users")
renamed = 0
for uid in sorted(os.listdir(users)) if os.path.isdir(users) else []:
    folder = os.path.join(users, uid)
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(folder, name)
        with open(path) as file:
            report = json.load(file)
        parts = [component(study)]
        pid = (report.get("metadata", {}).get("userInfo") or {}).get("pid", "").strip()
        if pid:
            parts.append("pid-" + component(pid))
        uploaded = created.get(f"{uid}/{name}")
        if uploaded is None:
            timestamps = [event.get("data", {}).get("timestamp") for event in report.get("timeline", [])]
            uploaded = max(t for t in timestamps if t) if any(timestamps) else None
        parts.append(stamp(uploaded) if uploaded else "unknown-time")
        parts.append(name[:8].lower())
        shutil.copy2(path, os.path.join(reports, "_".join(parts) + ".json"))
        renamed += 1
print(f"{renamed} older reports renamed into {reports}")
EOF

echo "$(find "$reports" -type f | wc -l | tr -d ' ') reports in $reports"
