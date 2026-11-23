#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REV="a2b3018"
mkdir -p Vendor
if [[ ! -d "Vendor/llama.xcframework" ]]; then
  echo '[MATE] Building pinned llama.cpp iOS XCFramework with Metal + mtmd'
  if [[ ! -d ".third_party/llama.cpp/.git" ]]; then
    mkdir -p .third_party
    git clone --filter=blob:none https://github.com/ggml-org/llama.cpp.git .third_party/llama.cpp
  fi
  pushd .third_party/llama.cpp >/dev/null
  git fetch --depth=1 origin "$REV"
  git checkout --detach FETCH_HEAD
  ./build-xcframework.sh ios-device ios-sim
  popd >/dev/null
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
