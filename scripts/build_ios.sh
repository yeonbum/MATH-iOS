#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Exact pin corresponding to Android llama.cpp a2b3018.
# Do not use a 7-character SHA with `git fetch --depth=1`: that is not a remote ref.
REV="a2b301831d05b07860de508d229d430207127802"
mkdir -p Vendor

# Make failing line/command visible in Actions output if a later tool fails.
trap 'rc=$?; echo "[MATE] ERROR at ${BASH_SOURCE[0]}:${LINENO} (exit ${rc}): ${BASH_COMMAND}" >&2' ERR

if [[ ! -d "Vendor/llama.xcframework" ]]; then
  echo "[MATE] Preparing pinned llama.cpp source: $REV"
  mkdir -p .third_party/llama.cpp

  # A pinned source archive avoids the shallow `git fetch` exit-128 failure.
  # No model file is downloaded or changed here.
  ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/mate-llama.XXXXXXXX.tar.gz")"
  if ! curl --fail --location --show-error --retry 4 --retry-all-errors \
       --connect-timeout 30 \
       "https://codeload.github.com/ggml-org/llama.cpp/tar.gz/${REV}" \
       -o "$ARCHIVE"; then
    echo "[MATE] Could not download llama.cpp source archive at $REV" >&2
    rm -f "$ARCHIVE"
    exit 10
  fi
  tar -xzf "$ARCHIVE" -C .third_party/llama.cpp --strip-components=1
  rm -f "$ARCHIVE"

  [[ -f .third_party/llama.cpp/build-xcframework.sh ]] || {
    echo '[MATE] Archive did not contain build-xcframework.sh' >&2
    exit 11
  }
  pushd .third_party/llama.cpp >/dev/null
  echo '[MATE] Building llama.cpp iOS device + simulator XCFramework (Metal + mtmd)'
  bash ./build-xcframework.sh ios-device ios-sim
  popd >/dev/null
  [[ -d .third_party/llama.cpp/build-apple/llama.xcframework ]] || {
    echo '[MATE] llama.cpp XCFramework was not created' >&2
    exit 12
  }
  cp -R .third_party/llama.cpp/build-apple/llama.xcframework Vendor/llama.xcframework
fi
# All XCFramework slices expose the same public C headers.
mkdir -p Vendor/Headers
HEADER="$(find Vendor/llama.xcframework -type f -name 'mtmd.h' -print -quit)"
if [[ -z "$HEADER" ]]; then
  echo 'ERROR: llama XCFramework does not export mtmd. Verify pinned upstream build.' >&2
  exit 3
fi
cp -f "$(dirname "$HEADER")"/*.h Vendor/Headers/
./scripts/install_katex.sh
if ! command -v xcodegen >/dev/null; then
  echo 'Install xcodegen with: brew install xcodegen' >&2
  exit 4
fi
xcodegen generate --spec project.yml
xcodebuild -project MATE.xcodeproj -scheme MATE -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
