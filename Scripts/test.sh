#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

if ! xcodebuild -version >/dev/null 2>&1 && [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk
fi
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

if xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1; then
  swift test --disable-sandbox
else
  echo "Full XCTest platform support is unavailable; running the standalone integration checks."
  swift run --disable-sandbox StorageCoreCheck
fi
