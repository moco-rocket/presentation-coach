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

signing_identity=${PRESENTATION_COACH_SIGNING_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
    signing_identity=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -1)
fi

if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
    echo "Warning: Apple Development証明書がないため、アドホック署名で起動します。" >&2
    echo "マイク・画面収録の許可にはXcodeでApple Development証明書を作成してください。" >&2
else
    echo "Signing with $signing_identity"
fi

codesign \
    --force \
    --sign "$signing_identity" \
    --entitlements "$repository_root/Support/PresentationCoach.entitlements" \
    "$application_path"

echo "Opening $application_path"
open_arguments=(--new)
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    open_arguments+=(--env "OPENAI_API_KEY=$OPENAI_API_KEY")
fi
if [[ -n "${OPENAI_MODEL:-}" ]]; then
    open_arguments+=(--env "OPENAI_MODEL=$OPENAI_MODEL")
fi
open "${open_arguments[@]}" "$application_path"
