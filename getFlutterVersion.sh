OS_NAME=$(echo "$RUNNER_OS" | awk '{print tolower($0)}')
ARCH=$(echo "$RUNNER_ARCH" | awk '{print tolower($0)}')
MANIFEST_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}/flutter_infra_release/releases"
MANIFEST_JSON_PATH="releases_$OS_NAME.json"
MANIFEST_URL="$MANIFEST_BASE_URL/$MANIFEST_JSON_PATH"
CHANNEL=stable
GIT_SOURCE="https://github.com/flutter/flutter.git"
VERSION="$1"

filter_by_channel() {
	jq --arg channel "$1" '[.releases[] | select($channel == "any" or .channel == $channel)]'
}

filter_by_arch() {
	jq --arg arch "$1" '[.[] | select(.dart_sdk_arch == $arch or ($arch == "x64" and (has("dart_sdk_arch") | not)))]'
}

filter_by_hash() {
    jq --arg hash "$1" '.[].hash |= gsub("^v"; "") | (if $hash == "any" then .[0] else (map(select(.hash == $hash or (.hash | startswith(($hash | sub("\\.x$"; "")) + ".")) and .hash != $hash)) | .[0]) end)'
}

RELEASE_MANIFEST=$(curl --silent --connect-timeout 15 --retry 5 "$MANIFEST_URL")
VERSION_MANIFEST=$(echo "$RELEASE_MANIFEST" | filter_by_channel "$CHANNEL" | filter_by_arch "$ARCH" | filter_by_hash "$VERSION")
echo "$VERSION_MANIFEST" | jq -j '.version'