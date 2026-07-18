#!/bin/bash
set -euo pipefail

script_directory=$(cd "$(dirname "$0")" && pwd)
repository_root=$(cd "$script_directory/.." && pwd)
configuration=${1:-debug}

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: scripts/run-app.sh [debug|release]" >&2
    exit 2
fi

cd "$repository_root"
swift build --configuration "$configuration" --product PresentationApp
binary_directory=$(swift build --configuration "$configuration" --show-bin-path)
application_path="$binary_directory/Presentation Coach.app"
contents_path="$application_path/Contents"

case "$application_path" in
    "$repository_root"/.build/*/"Presentation Coach.app") ;;
    *)
        echo "Refusing to replace unexpected application path: $application_path" >&2
        exit 3
        ;;
esac

rm -rf "$application_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
ditto "$binary_directory/PresentationApp" "$contents_path/MacOS/PresentationApp"
ditto "$repository_root/Support/Info.plist" "$contents_path/Info.plist"

codesign \
    --force \
    --sign - \
    --entitlements "$repository_root/Support/PresentationCoach.entitlements" \
    "$application_path"

echo "Opening $application_path"
open "$application_path"
