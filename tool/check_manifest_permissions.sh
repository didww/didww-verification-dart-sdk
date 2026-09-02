#!/usr/bin/env bash
# Asserts that an app using the SMS plugin declares no SMS or call-log
# permission, over the MERGED manifest of every variant of the example app.
#
# A thin wrapper on purpose. The assertion itself is a Gradle task, so it has the
# merged manifest as a declared input and runs the same way here, in CI and in
# an IDE, rather than existing twice and drifting.
set -euo pipefail

cd "$(dirname "$0")/../packages/didww_verification_sms/example/android"
exec ./gradlew --console=plain :app:checkManifestComponents "$@"
