#!/bin/bash
#
# This source file is part of the Plainly iOS open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University
#
# SPDX-License-Identifier: MIT
#
# Mirrors a study's uploads out of the production bucket: the reports the app now writes flat into
# studies/<study>/ and the older ones under studies/<study>/users/<uid>/.
# Usage: download-study-uploads.sh <study id> [destination]
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") <study id> [destination]" >&2
  exit 1
fi
study="$1"
destination="${2:-./study-uploads/$study}"
bucket="gs://som-rit-phi-lit-ai-prod.firebasestorage.app"

if [ -z "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" ]; then
  gcloud auth login
fi

mkdir -p "$destination"
gcloud storage rsync --recursive "$bucket/studies/$study" "$destination"
echo "$(find "$destination" -type f | wc -l | tr -d ' ') files in $destination"
