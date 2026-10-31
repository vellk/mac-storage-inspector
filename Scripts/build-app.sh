#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

sdk_args=()
if ! xcodebuild -version >/dev/null 2>&1 && [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk
fi

export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift build --disable-sandbox -c release

binary_path="$(swift build --disable-sandbox -c release --show-bin-path)/MacStorageInspector"
app_path="$project_dir/dist/Mac Storage Inspector.app"
contents_path="$app_path/Contents"

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$binary_path" "$contents_path/MacOS/MacStorageInspector"
cp "$project_dir/Support/Info.plist" "$contents_path/Info.plist"
chmod 755 "$contents_path/MacOS/MacStorageInspector"

codesign --force --deep --sign - "$app_path"
echo "Built: $app_path"
