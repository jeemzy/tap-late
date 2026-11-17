#!/bin/bash
set -euo pipefail
archive="${RUNNER_TEMP:?}/xcodegen.zip"
curl --fail --location --retry 3 https://github.com/yonaskolb/XcodeGen/releases/download/2.47.0/xcodegen.zip -o "$archive"
printf '6ef12a3ef5327c2c713397f46d9160550f8b1cdc5c925cd884d65c77c9f696cd  %s\n' "$archive" | shasum -a 256 -c -
unzip -q "$archive" -d "$RUNNER_TEMP/xcodegen"
generator=$(find "$RUNNER_TEMP/xcodegen" -type f -name xcodegen | head -1)
chmod +x "$generator"
"$generator" --version
"$generator" generate --spec ios/project.yml
