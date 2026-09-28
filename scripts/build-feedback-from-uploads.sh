#!/bin/bash
#
# This source file is part of the Plainly iOS open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University
#
# SPDX-License-Identifier: MIT
#
# Builds one conversation feedback page from the reports participants uploaded to a study.
#
# Pulls the study's reports with download-study-uploads.sh (already downloaded reports are not fetched again),
# keeps the ones picked by --since and --latest, and bakes them into a single HTML file with
# tools/conversation-feedback/build.ts. The upload time is read from the report's file name; reports whose
# upload time is unknown are left out as soon as a filter is given.
# Usage: build-feedback-from-uploads.sh <study id>|all [-o <output.html>] [--since <YYYY-MM-DD[THH-MM-SS]>]
#          [--latest <n>] [--project <firebase project>] [--destination <dir>] [--skip-download]
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <study id>|all [-o <output.html>] [--since <YYYY-MM-DD[THH-MM-SS]>] [--latest <n>]" >&2
  echo "         [--project <firebase project>] [--destination <dir>] [--skip-download]" >&2
  exit 1
}

here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/../tools/conversation-feedback"

study=""
output="conversation-feedback.html"
since=""
latest=""
project="som-rit-phi-lit-ai-dev"
destination="$here/../study-uploads"
download=true
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) output="$2"; shift 2;;
    --since) since="$2"; shift 2;;
    --latest) latest="$2"; shift 2;;
    --project) project="$2"; shift 2;;
    --destination) destination="$2"; shift 2;;
    --skip-download) download=false; shift;;
    -h|--help) usage;;
    -*) echo "unknown option: $1" >&2; usage;;
    *) [ -z "$study" ] || usage; study="$1"; shift;;
  esac
done
[ -n "$study" ] || usage
if [ -n "$latest" ] && ! [[ "$latest" =~ ^[1-9][0-9]*$ ]]; then
  echo "--latest takes a positive number, not '$latest'" >&2
  exit 1
fi

if $download; then
  "$here/download-study-uploads.sh" --project "$project" --study "$study" --destination "$destination"
fi

if [ "$study" = "all" ]; then
  folders=("$destination"/*/)
else
  folders=("$destination/$study/")
fi

# One "<upload time>\t<path>" line per report, with the time the app puts in the file name or "-" when it has none.
listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
for folder in "${folders[@]}"; do
  [ -d "$folder" ] || { echo "no reports downloaded for $(basename "$folder") in $folder" >&2; exit 1; }
  for file in "$folder"*.json; do
    [ -e "$file" ] || continue
    uploaded="$(basename "$file" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}\.[0-9]{3}Z' || echo -)"
    printf '%s\t%s\n' "$uploaded" "$file" >> "$listing"
  done
done

reports=()
while IFS=$'\t' read -r uploaded file; do
  reports+=("$file")
done < <(
  sort "$listing" | awk -F'\t' -v since="$since" -v filtered="${since}${latest}" '
    filtered != "" && $1 == "-" { next }
    since != "" && substr($1, 1, length(since)) < since { next }
    { print }
  ' | if [ -n "$latest" ]; then tail -n "$latest"; else cat; fi
)
if [ ${#reports[@]} -eq 0 ]; then
  echo "no reports match the filters" >&2
  exit 1
fi
echo "building the feedback page from ${#reports[@]} reports"

if [ ! -x "$tool/node_modules/.bin/tsx" ]; then
  (cd "$tool" && npm install --silent)
fi
"$tool/node_modules/.bin/tsx" "$tool/build.ts" "${reports[@]}" -o "$output"
