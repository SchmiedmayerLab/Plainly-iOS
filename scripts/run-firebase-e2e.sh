#!/bin/bash
#
# This source file is part of the Plainly iOS open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University
#
# SPDX-License-Identifier: MIT
#

set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# fastlane decodes xcodebuild's output as the locale's encoding, and raises on the first byte that is not
# valid in it, so a shell without a UTF-8 locale fails the run before any test starts.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
firebase_root="$repository_root/Plainly-Firebase"
secret_file="$firebase_root/functions/.secret.local"
created_secret=false

cleanup() {
  if [[ "$created_secret" == true ]]; then
    rm -f "$secret_file"
  fi
}
trap cleanup EXIT

if [[ ! -e "$firebase_root/.git" ]]; then
  git -C "$repository_root" submodule update --init Plainly-Firebase
fi
npm --prefix "$firebase_root/functions" ci
npm --prefix "$firebase_root/functions" run build

if [[ ! -f "$secret_file" ]]; then
  cp "$secret_file.example" "$secret_file"
  created_secret=true
fi

export FIREBASE_CLI_DISABLE_UPDATE_CHECK=true
export PLAINLY_MOCK_CHAT_RESPONSE="${PLAINLY_MOCK_CHAT_RESPONSE:-Plainly Firebase end-to-end response.}"

test_command="cd $(printf '%q' "$repository_root") && PLAINLY_RUN_FIREBASE_E2E=1 fastlane firebase_uitest"
cd "$firebase_root"
if command -v firebase >/dev/null 2>&1; then
  firebase_cli=(firebase)
else
  # 15.25 prompts for string params despite their defaults, which hangs a headless run.
  firebase_cli=(npx --yes firebase-tools@15.28.0)
fi

"${firebase_cli[@]}" emulators:exec \
  --project demo-plainly \
  --only auth,functions,firestore,storage \
  "$test_command"
