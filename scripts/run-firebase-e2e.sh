#!/bin/bash
#
# This source file is part of the Plainly iOS project
#
# SPDX-FileCopyrightText: 2026 Stanford University
#
# SPDX-License-Identifier: MIT
#

set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

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

git -C "$repository_root" submodule update --init Plainly-Firebase
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
  firebase_cli=(npx --yes firebase-tools@15.25.1)
fi

"${firebase_cli[@]}" emulators:exec \
  --project demo-plainly \
  --only auth,functions,storage \
  "$test_command"
